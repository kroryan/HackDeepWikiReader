/// Chat protocol models -- mirror src/utils/websocketClient.ts's
/// ChatMessage/ChatCompletionRequest (which itself mirrors
/// api/chat_models.py::ChatCompletionRequest) exactly, field-for-field, so
/// this app talks to the *same* /ws/chat endpoint the web app uses with no
/// backend changes required.
library;

class ChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
      );
}

/// One request sent over /ws/chat. See api/chat_models.py::ChatCompletionRequest
/// for the authoritative field list -- keep these two in sync.
class ChatCompletionRequest {
  final String repoUrl;
  final List<ChatMessage> messages;
  final String? filePath;
  final String? token;
  final String type; // 'github' | 'gitlab' | 'bitbucket' | 'local' | 'website' | 'zim'
  final String? currentPageId;
  final bool enableToolCalling;
  final String provider;
  final String? model;
  final String language;
  final String? apiKey;
  final String? apiEndpoint;
  // 🔐 Security context (this app's chat screen exposes the same toggle the
  // web app's Ask.tsx does).
  final bool includeSecurityContext;
  final String? owner;
  final String? repo;

  const ChatCompletionRequest({
    required this.repoUrl,
    required this.messages,
    this.filePath,
    this.token,
    this.type = 'github',
    this.currentPageId,
    this.enableToolCalling = true,
    this.provider = 'ollama',
    this.model,
    this.language = 'en',
    this.apiKey,
    this.apiEndpoint,
    this.includeSecurityContext = false,
    this.owner,
    this.repo,
  });

  Map<String, dynamic> toJson() => {
        'repo_url': repoUrl,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (filePath != null) 'filePath': filePath,
        if (token != null) 'token': token,
        'type': type,
        if (currentPageId != null) 'current_page_id': currentPageId,
        'enable_tool_calling': enableToolCalling,
        'provider': provider,
        if (model != null) 'model': model,
        'language': language,
        if (apiKey != null) 'api_key': apiKey,
        if (apiEndpoint != null) 'api_endpoint': apiEndpoint,
        'include_security_context': includeSecurityContext,
        if (owner != null) 'owner': owner,
        if (repo != null) 'repo': repo,
      };
}

/// A saved chat conversation for one wiki -- mirrors the shape of Ask.tsx's
/// ChatSession on the web app closely enough to keep the UX consistent.
class ChatSession {
  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final List<ChatMessage> messages;

  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'New chat',
        createdAt: json['createdAt'] as int? ?? 0,
        updatedAt: json['updatedAt'] as int? ?? 0,
        messages: (json['messages'] as List?)
                ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  ChatSession copyWith({List<ChatMessage>? messages, int? updatedAt, String? title}) => ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );
}
