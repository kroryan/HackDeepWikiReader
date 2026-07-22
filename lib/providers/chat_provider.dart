import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../llm/context_builder.dart';
import '../llm/llm_client.dart';
import '../models/chat_models.dart';
import '../models/llm_config.dart';
import '../models/vuln_models.dart';
import '../models/web_vuln_models.dart';
import '../providers/wiki_source.dart';
import '../storage/local_storage.dart';
import 'settings_provider.dart';

/// Chat state for one wiki -- fully independent of any HackDeepWiki server.
/// Talks directly to whichever LLM connection the user picks (configured in
/// Settings, see SettingsProvider/lib/llm/), building its own context from
/// the WikiSource already loaded locally (see lib/llm/context_builder.dart)
/// since there's no server-side RAG pipeline available to this app. Kept
/// alive by ChatOverlayController across navigation/minimize so a running
/// answer, or the message history, survives leaving and re-entering a wiki.
class ChatProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  final WikiSource source;
  final SettingsProvider settings;
  String? currentPageId;

  ChatProvider({required this.source, required this.settings, this.currentPageId}) {
    _sessions = LocalStorage.loadChatSessions(source.sourceId);
    if (_sessions.isEmpty) {
      _startNewSession();
    } else {
      _activeSessionId = _sessions.first.id;
    }
    _connectionId = settings.defaultConnection?.id;
  }

  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  bool _isLoading = false;
  String _streamingAnswer = '';
  String? _error;
  String? _connectionId;

  bool includeSecurityContext = false;

  VulnReport? _vulnReport;
  WebVulnReport? _webVulnReport;
  bool _securityLoadAttempted = false;

  StreamSubscription<String>? _streamSub;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession get activeSession =>
      _sessions.firstWhere((s) => s.id == _activeSessionId, orElse: _startNewSession);
  bool get isLoading => _isLoading;
  String get streamingAnswer => _streamingAnswer;
  String? get error => _error;

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
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : _startNewSession().id;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String question) async {
    if (question.trim().isEmpty || _isLoading) return;

    final connection = activeConnection;
    if (connection == null) {
      _error = 'No LLM provider configured. Open Settings to add one before chatting.';
      notifyListeners();
      return;
    }

    _error = null;
    _isLoading = true;
    _streamingAnswer = '';
    notifyListeners();

    final session = activeSession;
    final history = [...session.messages, ChatMessage(role: 'user', content: question)];
    _replaceActiveSessionMessages(history, title: session.messages.isEmpty ? question.trim() : null);

    if (includeSecurityContext && !_securityLoadAttempted) {
      _securityLoadAttempted = true;
      try {
        _vulnReport = await source.loadVulnReport();
      } catch (_) {}
      try {
        _webVulnReport = await source.loadWebVulnReport();
      } catch (_) {}
    }

    final systemPrompt = buildSystemPrompt(
      wikiTitle: source.title,
      wikiDescription: source.description,
      structure: source.structure,
      currentPage: currentPageId != null ? source.structure.pageById(currentPageId!) : null,
      vulnReport: _vulnReport,
      webVulnReport: _webVulnReport,
      includeSecurityContext: includeSecurityContext,
    );

    final client = buildLlmClient(connection);
    final completer = Completer<void>();
    _streamSub = client.streamChat(systemPrompt: systemPrompt, messages: history).listen(
      (delta) {
        _streamingAnswer += delta;
        notifyListeners();
      },
      onError: (Object e) {
        _error = e is LlmClientException ? e.message : e.toString();
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    await completer.future;

    if (_streamingAnswer.isNotEmpty) {
      final finalHistory = [...history, ChatMessage(role: 'assistant', content: _streamingAnswer)];
      _replaceActiveSessionMessages(finalHistory);
    }
    _isLoading = false;
    _streamingAnswer = '';
    _streamSub = null;
    notifyListeners();
  }

  void _replaceActiveSessionMessages(List<ChatMessage> messages, {String? title}) {
    final session = activeSession;
    final updated = session.copyWith(
      messages: messages,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      title: title != null ? (title.length > 48 ? title.substring(0, 48) : title) : null,
    );
    _sessions = _sessions.map((s) => s.id == updated.id ? updated : s).toList();
    LocalStorage.saveChatSession(source.sourceId, updated);
  }

  void cancel() {
    _streamSub?.cancel();
    _streamSub = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
