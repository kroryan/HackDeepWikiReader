import '../models/chat_models.dart';
import '../models/llm_config.dart';
import 'anthropic_client.dart';
import 'ollama_client.dart';
import 'openai_compatible_client.dart';

/// One LLM wire protocol, talked to directly by this app -- no HackDeepWiki
/// backend involved. The app is a read-only VIEWER of wiki content, but a
/// fully independent CLIENT for chat: see lib/llm/context_builder.dart for
/// how local wiki content is turned into the prompt context these clients
/// send.
///
/// To add a new provider: implement this interface in its own file (see
/// ollama_client.dart / openai_compatible_client.dart / anthropic_client.dart
/// for the pattern) and add one case to [buildLlmClient] below -- nothing
/// else in the app needs to change.
abstract class LlmClient {
  /// Streams answer text deltas as they arrive. [systemPrompt] carries the
  /// wiki/security context; providers that support a first-class system
  /// role (Ollama, OpenAI-compatible) get it as a leading message, Anthropic
  /// gets it via its separate `system` field (its Messages API forbids a
  /// `system` role inside `messages`).
  Stream<String> streamChat({required String? systemPrompt, required List<ChatMessage> messages});
}

class LlmClientException implements Exception {
  final String message;
  LlmClientException(this.message);
  @override
  String toString() => message;
}

LlmClient buildLlmClient(LlmConnection connection) {
  switch (connection.kind) {
    case LlmProviderKind.ollama:
      return OllamaLlmClient(baseUrl: connection.normalizedBaseUrl, model: connection.model);
    case LlmProviderKind.openaiCompatible:
      return OpenAiCompatibleLlmClient(
        baseUrl: connection.normalizedBaseUrl,
        apiKey: connection.apiKey ?? '',
        model: connection.model,
      );
    case LlmProviderKind.anthropic:
      return AnthropicLlmClient(
        baseUrl: connection.normalizedBaseUrl,
        apiKey: connection.apiKey ?? '',
        model: connection.model,
      );
  }
}
