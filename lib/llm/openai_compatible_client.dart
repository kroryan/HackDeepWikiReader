import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import 'llm_client.dart';

/// The generic OpenAI Chat Completions wire protocol (POST
/// {baseUrl}/chat/completions, SSE `data: {...}` chunks, one
/// `choices[0].delta.content` per line) -- covers ChatGPT/OpenAI itself
/// plus any OpenAI-compatible endpoint (OpenRouter, Together, Groq, vLLM,
/// LM Studio, a self-hosted proxy, ...), exactly like HackDeepWiki's own
/// "openai" / custom-endpoint provider concept (api/openai_client.py uses
/// the official `openai` Python SDK against the same protocol; this is a
/// from-scratch Dart re-implementation of the same wire format, not a port
/// of that file, since the SDK itself isn't available in Dart).
class OpenAiCompatibleLlmClient implements LlmClient {
  final String baseUrl; // e.g. https://api.openai.com/v1 (no trailing /chat/completions)
  final String apiKey;
  final String model;

  OpenAiCompatibleLlmClient({required this.baseUrl, required this.apiKey, required this.model});

  @override
  Stream<String> streamChat({required String? systemPrompt, required List<ChatMessage> messages}) async* {
    if (apiKey.isEmpty) {
      throw LlmClientException('No API key configured for this connection. Add one in Settings.');
    }
    final uri = Uri.parse('$baseUrl/chat/completions');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $apiKey'
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
      throw LlmClientException("Could not reach $baseUrl. Check the base URL in Settings ($e).");
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw LlmClientException('API error (${response.statusCode}): $body');
    }

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (json['error'] != null) {
        throw LlmClientException('API error: ${json['error']}');
      }
      final choices = json['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;
      final delta = choices.first['delta'] as Map?;
      final content = delta?['content'] as String?;
      if (content != null && content.isNotEmpty) yield content;
    }
  }
}
