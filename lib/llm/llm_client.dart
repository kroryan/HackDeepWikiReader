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

  /// Lists model ids this connection's base URL/credentials can serve right
  /// now -- backs the "Refresh models" button on the add/edit provider
  /// form (lib/screens/llm_connection_form_screen.dart), same idea as
  /// HackDeepWiki's own provider setup: point at an endpoint, fetch what it
  /// actually has, pick one, instead of needing to already know a valid
  /// model id. Typing a model id by hand always stays an option -- this is
  /// a convenience, not a requirement.
  Future<List<String>> listModels();
}

class LlmClientException implements Exception {
  final String message;
  LlmClientException(this.message);
  @override
  String toString() => message;
}

/// How long a provider stream may go completely silent -- no line, no
/// byte -- before it's treated as dead. This resets on every event (see
/// [Stream.timeout]), so it never interrupts a genuinely slow-but-active
/// generation (a cold-loading local Ollama model, a reasoning model
/// thinking between chunks); it only fires once nothing has arrived for
/// this long. Without it, every provider client's `await for` loop over
/// the response stream had no bound at all: a connection that stops
/// producing bytes without ever closing (seen with a stalled local
/// endpoint) left ChatProvider.sendMessage's completer waiting forever --
/// the chat panel just stays on "loading" indefinitely with no error and
/// nothing the user can do except force-quit the app, since the composer's
/// send button disables itself while loading and there was previously no
/// cancel affordance either.
const llmStreamStallTimeout = Duration(seconds: 100);

/// Wraps a decoded provider stream with [llmStreamStallTimeout]. Shared by
/// every LlmClient implementation's streamChat -- see the constant above
/// for why this exists.
Stream<T> withLlmStallTimeout<T>(Stream<T> stream) {
  return stream.timeout(
    llmStreamStallTimeout,
    onTimeout: (sink) {
      sink.addError(LlmClientException(
        'No response from the server for ${llmStreamStallTimeout.inSeconds} seconds -- '
        'the connection appears to have stalled. Please try again.',
      ));
      sink.close();
    },
  );
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

/// Builds a client from raw form fields rather than a saved [LlmConnection]
/// -- used by the add/edit provider form's "Test" and "Refresh models"
/// actions, which need to call a provider before there's anything saved to
/// build a real connection from yet.
LlmClient buildLlmClientFromFields({
  required LlmProviderKind kind,
  required String baseUrl,
  String? apiKey,
  String model = '',
}) {
  baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  switch (kind) {
    case LlmProviderKind.ollama:
      return OllamaLlmClient(baseUrl: baseUrl, model: model);
    case LlmProviderKind.openaiCompatible:
      return OpenAiCompatibleLlmClient(baseUrl: baseUrl, apiKey: apiKey ?? '', model: model);
    case LlmProviderKind.anthropic:
      return AnthropicLlmClient(baseUrl: baseUrl, apiKey: apiKey ?? '', model: model);
  }
}
