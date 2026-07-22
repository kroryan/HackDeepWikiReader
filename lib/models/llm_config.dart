/// A user-configured LLM connection, owned entirely by this app -- NOT
/// fetched from any HackDeepWiki server. This is the core of the
/// independent-chat architecture: the app is a read-only VIEWER of
/// HackDeepWiki content, but talks to LLM providers directly and on its
/// own, exactly like the web app's own provider clients do (see
/// api/provider_streaming.py, api/openai_client.py, api/anthropic_client.py
/// on the deepwiki-open backend -- this app re-implements the same three
/// wire protocols natively in Dart instead of proxying through a backend).
library;

enum LlmProviderKind { ollama, openaiCompatible, anthropic }

/// UI-facing preset, purely to prefill sensible defaults (base URL) in the
/// add/edit form -- 'chatgpt' and 'customOpenAi' both store as
/// [LlmProviderKind.openaiCompatible] underneath, since they're the exact
/// same wire protocol.
enum LlmPreset { ollama, chatgpt, customOpenAi, anthropic }

extension LlmPresetX on LlmPreset {
  LlmProviderKind get kind => switch (this) {
        LlmPreset.ollama => LlmProviderKind.ollama,
        LlmPreset.chatgpt || LlmPreset.customOpenAi => LlmProviderKind.openaiCompatible,
        LlmPreset.anthropic => LlmProviderKind.anthropic,
      };

  String get label => switch (this) {
        LlmPreset.ollama => 'Ollama',
        LlmPreset.chatgpt => 'ChatGPT (OpenAI)',
        LlmPreset.customOpenAi => 'Custom OpenAI-compatible',
        LlmPreset.anthropic => 'Anthropic Claude',
      };

  String? get defaultBaseUrl => switch (this) {
        LlmPreset.ollama => 'http://127.0.0.1:11434',
        LlmPreset.chatgpt => 'https://api.openai.com/v1',
        LlmPreset.customOpenAi => null,
        LlmPreset.anthropic => 'https://api.anthropic.com/v1',
      };

  String get modelHint => switch (this) {
        LlmPreset.ollama => 'e.g. llama3.1, qwen2.5-coder',
        LlmPreset.chatgpt => 'e.g. gpt-4o, gpt-4o-mini',
        LlmPreset.customOpenAi => 'e.g. the model id your endpoint serves',
        LlmPreset.anthropic => 'e.g. claude-sonnet-4-5-20250929',
      };

  bool get needsApiKey => this != LlmPreset.ollama;
}

/// Stored as a plain JSON map in Hive -- see lib/storage/local_storage.dart.
class LlmConnection {
  final String id;
  final String name;
  final LlmProviderKind kind;
  final LlmPreset preset;
  final String baseUrl;
  final String? apiKey;
  final String model;
  final bool isDefault;

  const LlmConnection({
    required this.id,
    required this.name,
    required this.kind,
    required this.preset,
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'preset': preset.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'isDefault': isDefault,
      };

  factory LlmConnection.fromJson(Map<String, dynamic> json) => LlmConnection(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: LlmProviderKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => LlmProviderKind.openaiCompatible,
        ),
        preset: LlmPreset.values.firstWhere(
          (p) => p.name == json['preset'],
          orElse: () => LlmPreset.customOpenAi,
        ),
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String?,
        model: json['model'] as String? ?? '',
        isDefault: json['isDefault'] as bool? ?? false,
      );

  LlmConnection copyWith({
    String? name,
    LlmProviderKind? kind,
    LlmPreset? preset,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? isDefault,
  }) =>
      LlmConnection(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        preset: preset ?? this.preset,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        isDefault: isDefault ?? this.isDefault,
      );

  String get normalizedBaseUrl => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}
