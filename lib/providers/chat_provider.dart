import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/chat_socket.dart';
import '../api/stream_parser.dart';
import '../models/chat_models.dart';
import '../models/endpoint.dart';
import '../storage/local_storage.dart';

/// Chat state for one wiki -- direct port of Ask.tsx's core behavior:
/// send a question, stream the answer (with interleaved process/tool-call
/// events), keep history, persist sessions locally. Deep Research and the
/// 🔐 Security-context toggle are exposed as plain booleans a screen can
/// bind checkboxes to.
class ChatProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  final Endpoint endpoint;
  final String sourceId; // WikiSource.sourceId -- keys chat history storage
  final String repoUrl;
  final String repoType;
  final String owner;
  final String repo;
  final String language;
  final String? currentPageId;

  ChatProvider({
    required this.endpoint,
    required this.sourceId,
    required this.repoUrl,
    required this.repoType,
    required this.owner,
    required this.repo,
    required this.language,
    this.currentPageId,
  }) {
    _sessions = LocalStorage.loadChatSessions(sourceId);
    if (_sessions.isEmpty) {
      _startNewSession();
    } else {
      _activeSessionId = _sessions.first.id;
    }
  }

  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  bool _isLoading = false;
  String _streamingAnswer = '';
  final List<ProcessEvent> _streamingEvents = [];
  String? _error;

  bool deepResearch = false;
  bool includeSecurityContext = false;
  String provider = 'ollama';
  String? model;

  /// Setters that notify listeners -- prefer these over mutating the plain
  /// fields above directly from a widget (which a screen might still do
  /// once, e.g. right after fetching /models/config on init, before any
  /// listener is attached yet; that's fine, but anything driven by user
  /// interaction should go through here so the UI actually rebuilds).
  void setProvider(String value) {
    provider = value;
    notifyListeners();
  }

  void setModel(String? value) {
    model = value;
    notifyListeners();
  }

  void setDeepResearch(bool value) {
    deepResearch = value;
    notifyListeners();
  }

  void setIncludeSecurityContext(bool value) {
    includeSecurityContext = value;
    notifyListeners();
  }

  ChatSocket? _socket;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession get activeSession =>
      _sessions.firstWhere((s) => s.id == _activeSessionId, orElse: _startNewSession);
  bool get isLoading => _isLoading;
  String get streamingAnswer => _streamingAnswer;
  List<ProcessEvent> get streamingEvents => List.unmodifiable(_streamingEvents);
  String? get error => _error;

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
    await LocalStorage.deleteChatSession(sourceId, id);
    _sessions = _sessions.where((s) => s.id != id).toList();
    if (_activeSessionId == id) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : _startNewSession().id;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String question) async {
    if (question.trim().isEmpty || _isLoading) return;
    _error = null;
    _isLoading = true;
    _streamingAnswer = '';
    _streamingEvents.clear();
    notifyListeners();

    final session = activeSession;
    final history = [...session.messages, ChatMessage(role: 'user', content: question)];
    _replaceActiveSessionMessages(history, title: session.messages.isEmpty ? question.trim() : null);

    final request = ChatCompletionRequest(
      repoUrl: repoUrl,
      messages: history,
      type: repoType,
      currentPageId: currentPageId,
      provider: provider,
      model: model,
      language: language,
      includeSecurityContext: includeSecurityContext,
      owner: owner,
      repo: repo,
    );

    _socket = ChatSocket(endpoint);
    try {
      await for (final result in _socket!.send(request)) {
        _streamingAnswer += result.text;
        _streamingEvents.addAll(result.events);
        notifyListeners();
      }
      final finalHistory = [...history, ChatMessage(role: 'assistant', content: _streamingAnswer)];
      _replaceActiveSessionMessages(finalHistory);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _streamingAnswer = '';
      _streamingEvents.clear();
      notifyListeners();
    }
  }

  void _replaceActiveSessionMessages(List<ChatMessage> messages, {String? title}) {
    final session = activeSession;
    final updated = session.copyWith(
      messages: messages,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      title: title != null ? (title.length > 48 ? title.substring(0, 48) : title) : null,
    );
    _sessions = _sessions.map((s) => s.id == updated.id ? updated : s).toList();
    LocalStorage.saveChatSession(sourceId, updated);
  }

  void cancel() {
    _socket?.close();
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }
}
