import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import 'llm_client.dart';

/// Talks directly to Ollama's own REST API (POST /api/chat), the same
/// endpoint adalflow.components.model_client.ollama_client.OllamaClient
/// wraps via the official `ollama` Python package on the HackDeepWiki
/// backend (see api/provider_streaming.py's `if provider == "ollama":`
/// branch) -- this is a from-scratch Dart re-implementation of that same
/// wire protocol, since this app never talks to the HackDeepWiki backend
/// for chat at all.
///
/// Response is newline-delimited JSON, one object per token/chunk:
/// {"message":{"role":"assistant","content":"..."},"done":false}
/// ending with a final {"done":true, ...stats}.
class OllamaLlmClient implements LlmClient {
  final String baseUrl; // e.g. http://127.0.0.1:11434
  final String model;

  OllamaLlmClient({required this.baseUrl, required this.model});

  @override
  Stream<String> streamChat({
    required String? systemPrompt,
    required List<ChatMessage> messages,
    void Function(String delta)? onThinking,
    bool allowToolCalling = true,
  }) async* {
    final uri = Uri.parse('$baseUrl/api/chat');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': [
          if (systemPrompt != null && systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
          ...messages.map((m) => m.toJson()),
        ],
        // Gives a real schema to whatever this model's OWN native
        // tool-calling training reaches for on its own -- see this method's
        // doc and _extractQueryArgument for why guessing the argument shape
        // without one is unreliable. Harmless for a model with no such
        // training: it just never gets used, same as any unused tool
        // definition.
        if (allowToolCalling)
          'tools': [
            {
              'type': 'function',
              'function': {
                'name': 'SEARCH_WIKI',
                'description': "Full-text search over this wiki's pages for something not already covered by the given context.",
                'parameters': {
                  'type': 'object',
                  'properties': {
                    'query': {'type': 'string', 'description': 'A short search query.'},
                  },
                  'required': ['query'],
                },
              },
            },
          ],
      });

    final http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw LlmClientException(
        "Could not reach Ollama at $baseUrl. Check it's running and the host/port in Settings ($e).",
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw LlmClientException('Ollama error (${response.statusCode}): $body');
    }

    await for (final line in withLlmStallTimeout(
      response.stream.transform(utf8.decoder).transform(const LineSplitter()),
    )) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (json['error'] != null) {
        throw LlmClientException('Ollama error: ${json['error']}');
      }
      final message = json['message'] as Map?;
      final thinking = message?['thinking'] as String?;
      if (thinking != null && thinking.isNotEmpty) onThinking?.call(thinking);
      final content = message?['content'] as String?;
      if (content != null && content.isNotEmpty) yield content;
      // gpt-oss (and other tool-trained Ollama models) will sometimes
      // decide on its OWN, from the plain-text "SEARCH_WIKI: <query>"
      // instruction in the system prompt alone, to respond with Ollama's
      // native structured tool_calls field instead of following that
      // instruction as literal text -- confirmed live via a direct replay
      // of this app's actual request/response: content stayed empty and
      // {"tool_calls":[{"function":{"name":"SEARCH_WIKI","arguments":{...}}}]}
      // arrived instead, right before done:true. This app never sends a
      // `tools` schema (matching the web backend, which also never treats
      // Ollama as a native-tool-calling provider -- see
      // api/search_tool.py's NATIVE_TOOL_PROVIDERS), so the model invents
      // its own argument key names with no schema to constrain them; take
      // whatever string-valued argument looks like the query rather than
      // assuming a fixed key, and synthesize the exact textual line
      // ChatProvider's tool sniffing already expects. Without this, that
      // whole turn produced literally nothing -- not an error, no content,
      // no indication the model had, in fact, decided to search.
      final toolCalls = message?['tool_calls'] as List?;
      if (toolCalls != null && toolCalls.isNotEmpty) {
        final call = toolCalls.first;
        if (call is Map) {
          final function = call['function'];
          if (function is Map) {
            final name = function['name'] as String?;
            final arguments = function['arguments'];
            if (name != null && name.toUpperCase() == 'SEARCH_WIKI') {
              final query = _extractQueryArgument(arguments);
              if (query != null && query.isNotEmpty) {
                yield 'SEARCH_WIKI: $query';
              }
            }
          }
        }
      }
      if (json['done'] == true) break;
    }
  }

  /// Best-effort extraction of the search query from a self-invented
  /// tool_calls.function.arguments value -- see the call site's doc for why
  /// there's no fixed schema to rely on. Prefers an argument under a
  /// plausible key name; falls back to the first string value found at all,
  /// since a model with no real schema to follow may use any key name it
  /// likes (observed live: `{"id": "SEARCH_WIKI", "payload": "..."}`).
  static String? _extractQueryArgument(Object? arguments) {
    Object? args = arguments;
    if (arguments is String) {
      try {
        args = jsonDecode(arguments);
      } catch (_) {
        return arguments.trim().isEmpty ? null : arguments.trim();
      }
    }
    if (args is! Map) return null;
    const preferredKeys = ['query', 'q', 'search', 'payload', 'input', 'text'];
    for (final key in preferredKeys) {
      final value = args[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    for (final value in args.values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  @override
  Future<List<String>> listModels() async {
    final uri = Uri.parse('$baseUrl/api/tags');
    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw LlmClientException("Could not reach Ollama at $baseUrl ($e).");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmClientException('Ollama error (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = (data['models'] as List? ?? [])
        .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    models.sort();
    return models;
  }
}
