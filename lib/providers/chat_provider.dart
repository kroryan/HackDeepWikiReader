import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../llm/context_builder.dart';
import '../llm/llm_client.dart';
import '../llm/wiki_search.dart';
import '../models/chat_models.dart';
import '../models/llm_config.dart';
import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../providers/wiki_source.dart';
import '../storage/local_storage.dart';
import '../utils/app_logger.dart';
import 'settings_provider.dart';

/// One round of the agentic tool-calling loop (see [ChatProvider._streamOneRound]).
class _RoundResult {
  final String text;
  final bool isToolCall;
  final String? toolQuery;
  const _RoundResult(this.text, {this.isToolCall = false, this.toolQuery});
}

/// Chat state for one wiki -- fully independent of any HackDeepWiki server.
/// Talks directly to whichever LLM connection the user picks (configured in
/// Settings, see SettingsProvider/lib/llm/), building its own context from
/// the WikiSource already loaded locally (see lib/llm/context_builder.dart)
/// since there's no server-side RAG pipeline available to this app. Kept
/// alive by ChatOverlayController across navigation/minimize so a running
/// answer, or the message history, survives leaving and re-entering a wiki.
class ChatProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  static const _toolPrefix = 'SEARCH_WIKI:';
  static final _toolCallPattern = RegExp(
    r'^SEARCH_WIKI:\s*(.+)$',
    caseSensitive: false,
  );
  // Mirrors the backend's own MAX_TOOL_ROUNDS (api/agent_loop.py) -- the
  // last round always has tool calling disabled (see buildSystemPrompt's
  // allowToolCalling), forcing a direct answer instead of looping forever.
  static const _maxToolRounds = 4;

  final WikiSource source;
  final SettingsProvider settings;
  String? currentPageId;

  ChatProvider({
    required this.source,
    required this.settings,
    this.currentPageId,
  }) {
    _sessions = LocalStorage.loadChatSessions(source.sourceId);
    if (_sessions.isEmpty) {
      _startNewSession();
    } else {
      _activeSessionId = _sessions.first.id;
    }
    _connectionId = settings.defaultConnection?.id;
    _securityLoadFuture = _loadSecurityContext();
  }

  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  bool _isLoading = false;
  String _streamingAnswer = '';
  String? _error;
  String? _connectionId;
  String? _toolStatus;
  // Reasoning/"thinking" text a provider streams separately from the answer
  // (see LlmClient.streamChat's onThinking doc) -- shown live in a
  // collapsed-by-default panel so a model that's genuinely still working
  // (just slowly, mid chain-of-thought) doesn't look indistinguishable from
  // a dead one. Reset at the start of every round; not persisted into
  // ChatMessage history once the round completes, same as this app's
  // existing _toolStatus.
  String _thinkingBuffer = '';

  bool includeSecurityContext = false;

  VulnReport? _vulnReport;
  WebVulnReport? _webVulnReport;
  late final Future<void> _securityLoadFuture;

  StreamSubscription<String>? _streamSub;
  // Tracks the Completer _streamOneRound is currently awaiting, so cancel()
  // can resolve it directly. Cancelling the subscription alone does NOT do
  // this: a cancelled StreamSubscription never fires its onDone/onError
  // handlers (that's what "cancel" means), so without this, the completer
  // -- and the whole sendMessage() call stack suspended on `await
  // completer.future` -- would just hang forever in the background even
  // though the UI had already moved on, silently leaking a suspended
  // Future for the rest of this ChatProvider's lifetime.
  Completer<void>? _activeCompleter;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession get activeSession => _sessions.firstWhere(
    (s) => s.id == _activeSessionId,
    orElse: _startNewSession,
  );
  bool get isLoading => _isLoading;
  String get streamingAnswer => _streamingAnswer;
  String? get error => _error;
  String get thinkingBuffer => _thinkingBuffer;

  /// Non-null while a SEARCH_WIKI tool round is running -- the UI shows this
  /// instead of the (empty, or in-progress-but-not-yet-shown) answer bubble.
  String? get toolStatus => _toolStatus;

  /// Whether there's actually a security/web-vuln report to fold into the
  /// prompt -- backs the 🔐 toggle's visibility, which should only appear
  /// when there's something for it to include (checked once up front, in
  /// the constructor, rather than lazily on first send, precisely so the
  /// toolbar can decide this before the user ever sends a message).
  bool get securityContextAvailable =>
      _vulnReport != null || _webVulnReport != null;

  Future<void> _loadSecurityContext() async {
    try {
      _vulnReport = await source.loadVulnReport();
    } catch (_) {}
    try {
      _webVulnReport = await source.loadWebVulnReport();
    } catch (_) {}
    notifyListeners();
  }

  LlmConnection? get activeConnection {
    final id = _connectionId;
    if (id != null) {
      for (final c in settings.connections) {
        if (c.id == id) return c;
      }
    }
    return settings.defaultConnection;
  }

  void setConnection(String? id) {
    _connectionId = id;
    notifyListeners();
  }

  void setIncludeSecurityContext(bool value) {
    includeSecurityContext = value;
    notifyListeners();
  }

  void setCurrentPageId(String? id) {
    currentPageId = id;
  }

  ChatSession _startNewSession() {
    final session = ChatSession(
      id: _uuid.v4(),
      title: 'New chat',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      messages: const [],
    );
    _sessions = [session, ..._sessions];
    _activeSessionId = session.id;
    return session;
  }

  void newChat() {
    _startNewSession();
    notifyListeners();
  }

  void selectSession(String id) {
    _activeSessionId = id;
    notifyListeners();
  }

  Future<void> deleteSession(String id) async {
    await LocalStorage.deleteChatSession(source.sourceId, id);
    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_activeSessionId == id) {
      _activeSessionId = _sessions.isNotEmpty
          ? _sessions.first.id
          : _startNewSession().id;
    }
    notifyListeners();
  }

  /// Sends a message and drives the agentic tool-calling loop -- this app
  /// has no server-side RAG/search pipeline, so instead of stuffing an
  /// entire wiki's content into one prompt (which for a large .zim archive,
  /// e.g. a real Wikipedia dump with 17k+ pages, silently blows past any
  /// model's context window), the model gets a bounded slice up front (see
  /// context_builder.dart) plus a SEARCH_WIKI tool it can call for anything
  /// else -- mirroring HackDeepWiki's own agentic chat (api/agent_loop.py),
  /// specifically its provider-agnostic textual fallback (sniff_and_relay),
  /// since that's the one path that works identically across every provider
  /// this app's LlmClient abstraction supports (see llm_client.dart) without
  /// needing per-provider native function-calling integration.
  Future<void> sendMessage(String question) async {
    if (question.trim().isEmpty || _isLoading) return;

    final connection = activeConnection;
    if (connection == null) {
      _error =
          'No LLM provider configured. Open Settings to add one before chatting.';
      notifyListeners();
      return;
    }

    _error = null;
    _isLoading = true;
    _streamingAnswer = '';
    _toolStatus = null;
    _thinkingBuffer = '';
    notifyListeners();

    final session = activeSession;
    final baseHistory = [
      ...session.messages,
      ChatMessage(role: 'user', content: question),
    ];
    _replaceActiveSessionMessages(
      baseHistory,
      title: session.messages.isEmpty ? question.trim() : null,
    );

    if (includeSecurityContext) await _securityLoadFuture;

    // WebView rendering reads HTML through the loopback server rather than
    // ZimWikiSource.loadHtml(), so ensure the current article's plain text is
    // present before constructing the prompt. This keeps local-ZIM chat fully
    // independent and gives it the same page-scoped context as other wikis.
    final activeSource = source;
    final activePageId = currentPageId;
    if (activeSource is ZimWikiSource && activePageId != null) {
      try {
        await activeSource.loadPlainText(activePageId);
      } catch (error) {
        _error = 'Could not read the current ZIM page for chat: $error';
        _isLoading = false;
        notifyListeners();
        return;
      }
    }

    final client = buildLlmClient(connection);
    AppLogger.instance.info(
      'sendMessage: connection=${connection.kind} model=${connection.model} '
      'question="${question.length > 80 ? question.substring(0, 80) : question}"',
    );

    // Two attempts total: an empty completion (a reasoning model that ends
    // its turn having produced only "thinking" tokens -- a real, observed,
    // non-deterministic quirk, see _runRoundLoop's doc) or a transient
    // provider-side failure (e.g. a bare "Internal Server Error" from an
    // Ollama cloud-proxied model, confirmed live: the exact same request
    // succeeded seconds later against the same endpoint) both have a good
    // chance of succeeding on a plain retry. Don't retry a permanent
    // failure (bad API key, unreachable host, etc.) endlessly -- one retry,
    // then surface whatever happened.
    String? finalAnswer;
    String? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      _error = null;
      final outcome = await _runRoundLoop(client, baseHistory);
      finalAnswer = outcome;
      lastError = _error;
      if (finalAnswer != null && finalAnswer.trim().isNotEmpty) break;
      if (attempt == 0) {
        AppLogger.instance.warn(
          'sendMessage: attempt $attempt produced no answer (error=$lastError) -- retrying once',
        );
      }
    }
    _error = lastError;

    // Mirrors the web backend's own safety net (api/agent_loop.py's
    // sent_anything tracking): even after a retry, a reasoning-heavy model
    // can legitimately end up having produced zero actual answer content
    // twice in a row -- no error, nothing malformed. Without this fallback
    // that showed as the loading spinner and the "Thinking..." panel just
    // vanishing with nothing to show for it and no indication anything
    // went wrong.
    if (finalAnswer == null || finalAnswer.trim().isEmpty) {
      AppLogger.instance.warn(
        'sendMessage: both attempts produced no answer text (error=$_error) -- using fallback message',
      );
      finalAnswer = _error != null
          ? null
          : "I wasn't able to generate a response for that. Please try rephrasing your question, or try again.";
    }

    if (finalAnswer != null && finalAnswer.isNotEmpty) {
      final finalHistory = [
        ...baseHistory,
        ChatMessage(role: 'assistant', content: finalAnswer),
      ];
      _replaceActiveSessionMessages(finalHistory);
    }
    _isLoading = false;
    _streamingAnswer = '';
    _toolStatus = null;
    _thinkingBuffer = '';
    _streamSub = null;
    notifyListeners();
  }

  /// Drives the agentic tool-calling round loop for one attempt (see
  /// [sendMessage], which may call this twice -- a fresh attempt always
  /// starts its own `workingMessages` from [baseHistory], never continuing
  /// a previous attempt's tool-call history). Returns the final answer
  /// text, or null on error (check [error] for why) or an empty completion
  /// (no error at all -- see the call site's comment on why that happens).
  Future<String?> _runRoundLoop(
    LlmClient client,
    List<ChatMessage> baseHistory,
  ) async {
    var workingMessages = List<ChatMessage>.from(baseHistory);

    for (var round = 0; round < _maxToolRounds; round++) {
      final isLastRound = round == _maxToolRounds - 1;
      final systemPrompt = buildSystemPrompt(
        wikiTitle: source.title,
        wikiDescription: source.description,
        structure: source.structure,
        isWebsite: source.isWebsite,
        currentPage: currentPageId != null
            ? source.structure.pageById(currentPageId!)
            : null,
        vulnReport: _vulnReport,
        webVulnReport: _webVulnReport,
        includeSecurityContext: includeSecurityContext,
        allowToolCalling: !isLastRound,
      );

      final result = await _streamOneRound(
        client,
        systemPrompt,
        workingMessages,
        allowToolSniffing: !isLastRound,
      );
      AppLogger.instance.info(
        'sendMessage: round=$round result=${result == null ? 'null(error/empty)' : 'text.length=${result.text.length} isToolCall=${result.isToolCall}'} error=$_error',
      );
      if (result == null) return null; // error (sets _error) or produced nothing

      if (result.isToolCall) {
        final query = result.toolQuery!;
        _toolStatus = 'Searching "$query"…';
        _streamingAnswer = '';
        notifyListeners();
        final hits = await searchWiki(source, query);
        AppLogger.instance.info(
          'sendMessage: SEARCH_WIKI "$query" -> ${hits.length} hits',
        );
        workingMessages = [
          ...workingMessages,
          ChatMessage(role: 'assistant', content: result.text.trim()),
          ChatMessage(
            role: 'user',
            content:
                '<tool_result>\n${_formatSearchResults(hits)}\n</tool_result>',
          ),
        ];
        _toolStatus = null;
        continue;
      }

      return result.text;
    }
    return null;
  }

  /// Streams one LLM turn. While [allowToolSniffing], the response is
  /// buffered (not shown live) until it's clear whether it's forming a bare
  /// `SEARCH_WIKI: <query>` line -- otherwise the raw tool-call syntax would
  /// flash on screen for a moment before being recognized. A real tool call
  /// must be the model's ENTIRE response (single line); anything else is
  /// treated as a normal answer, buffered portion included.
  Future<_RoundResult?> _streamOneRound(
    LlmClient client,
    String systemPrompt,
    List<ChatMessage> messages, {
    required bool allowToolSniffing,
  }) async {
    final completer = Completer<void>();
    _activeCompleter = completer;
    final buffer = StringBuffer();
    var sniffResolved = !allowToolSniffing;
    var hadError = false;
    _thinkingBuffer = '';

    _streamSub = client
        .streamChat(
          systemPrompt: systemPrompt,
          messages: messages,
          onThinking: (delta) {
            _thinkingBuffer += delta;
            notifyListeners();
          },
        )
        .listen(
          (delta) {
            buffer.write(delta);
            if (sniffResolved) {
              _streamingAnswer += delta;
              notifyListeners();
              return;
            }
            final text = buffer.toString();
            if (text.length < _toolPrefix.length) return;
            if (text.substring(0, _toolPrefix.length).toUpperCase() !=
                _toolPrefix) {
              sniffResolved = true;
              _streamingAnswer = text;
              notifyListeners();
            } else {
              _toolStatus = 'Thinking…';
              notifyListeners();
            }
          },
          onError: (Object e, StackTrace st) {
            _error = e is LlmClientException ? e.message : e.toString();
            hadError = true;
            AppLogger.instance.log(
              'ERROR',
              '_streamOneRound: stream error: $_error',
              error: e,
              stack: st,
            );
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            AppLogger.instance.info(
              '_streamOneRound: onDone, buffered=${buffer.length} chars, '
              'thinking=${_thinkingBuffer.length} chars, sniffResolved=$sniffResolved',
            );
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

    await completer.future;
    _streamSub = null;
    _activeCompleter = null;
    if (hadError) return null;

    final fullText = buffer.toString();
    final trimmed = fullText.trim();
    final match = _toolCallPattern.firstMatch(trimmed);
    if (allowToolSniffing && match != null && !trimmed.contains('\n')) {
      return _RoundResult(
        fullText,
        isToolCall: true,
        toolQuery: match.group(1)!.trim(),
      );
    }
    if (!sniffResolved) {
      // Short response that never got flushed to the live answer -- show it now.
      _streamingAnswer = fullText;
      notifyListeners();
    }
    return _RoundResult(fullText);
  }

  String _formatSearchResults(List<WikiSearchHit> hits) {
    if (hits.isEmpty) return 'No matching pages found.';
    final buffer = StringBuffer();
    for (final h in hits) {
      buffer.writeln('### ${h.title}');
      buffer.writeln(h.snippet);
      buffer.writeln();
    }
    return buffer.toString();
  }

  void _replaceActiveSessionMessages(
    List<ChatMessage> messages, {
    String? title,
  }) {
    final session = activeSession;
    final updated = session.copyWith(
      messages: messages,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      title: title != null
          ? (title.length > 48 ? title.substring(0, 48) : title)
          : null,
    );
    _sessions = _sessions.map((s) => s.id == updated.id ? updated : s).toList();
    LocalStorage.saveChatSession(source.sourceId, updated);
  }

  void cancel() {
    _streamSub?.cancel();
    _streamSub = null;
    // A cancelled StreamSubscription never fires onDone/onError, so without
    // this the sendMessage() call still suspended on `await
    // completer.future` inside _streamOneRound would never resume -- see
    // the field doc on _activeCompleter.
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete();
    }
    _activeCompleter = null;
    _isLoading = false;
    _toolStatus = null;
    _streamingAnswer = '';
    _thinkingBuffer = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
