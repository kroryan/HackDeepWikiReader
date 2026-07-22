/// Chat message/session models. [ChatMessage] doubles as the wire shape
/// sent to this app's own LLM clients (lib/llm/*) -- role is one of
/// 'user' | 'assistant' | 'system'.
library;

class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
      );

  /// Reads a message that may have come back from Hive as a
  /// `Map<dynamic, dynamic>` (Hive doesn't preserve nested generic types on
  /// reload -- a stored `Map<String, dynamic>` is handed back as
  /// `Map<dynamic, dynamic>`, so a direct `as Map<String, dynamic>` cast in
  /// [ChatSession.fromJson] throws and the whole chat overlay refuses to
  /// open on any wiki that has saved history). This widens the input to
  /// `Map` and re-types it via `Map<String, dynamic>.from` before delegating.
  factory ChatMessage.fromJsonUntyped(Map<Object?, Object?> json) =>
      ChatMessage.fromJson(Map<String, dynamic>.from(json));
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
                ?.map((e) => ChatMessage.fromJsonUntyped(e as Map<Object?, Object?>))
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
