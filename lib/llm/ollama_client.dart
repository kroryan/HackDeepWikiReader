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
      if (json['done'] == true) break;
    }
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
