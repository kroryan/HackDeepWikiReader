import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/chat_models.dart';
import 'llm_client.dart';

/// Native Anthropic Messages API (POST {baseUrl}/messages, `stream: true`
/// SSE), a from-scratch Dart re-implementation of the exact protocol
/// api/anthropic_client.py's `AnthropicClient.astream` talks on the
/// HackDeepWiki backend -- same auth-header logic (a standard API key,
/// which always starts with "sk-ant-api", goes in `x-api-key`; anything
/// else is treated as a Claude Pro/Max subscription OAuth token and sent as
/// `Authorization: Bearer` with the `anthropic-beta: oauth-2025-04-20`
/// header Anthropic requires for OAuth-authenticated requests), same event
/// filtering (only `content_block_delta` events with `delta.type ==
/// "text_delta"` carry answer text).
///
/// Unlike the other two providers, Anthropic's Messages API has no `system`
/// role inside `messages` -- system context is a separate top-level field.
class AnthropicLlmClient implements LlmClient {
  final String baseUrl; // e.g. https://api.anthropic.com/v1
  final String apiKey;
  final String model;

  static const _version = '2023-06-01';
  static const _oauthBeta = 'oauth-2025-04-20';
  static const _maxTokens = 8192;

  AnthropicLlmClient({required this.baseUrl, required this.apiKey, required this.model});

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json', 'anthropic-version': _version};
    if (apiKey.startsWith('sk-ant-api')) {
      headers['x-api-key'] = apiKey;
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
      headers['anthropic-beta'] = _oauthBeta;
    }
    return headers;
  }

  @override
  Stream<String> streamChat({
    required String? systemPrompt,
    required List<ChatMessage> messages,
    void Function(String delta)? onThinking,
  }) async* {
    if (apiKey.isEmpty) {
      throw LlmClientException(
        'No Anthropic API key (or subscription token) configured for this connection. Add one in Settings.',
      );
    }
    final uri = Uri.parse('$baseUrl/messages');
    final request = http.Request('POST', uri)
      ..headers.addAll(_headers())
      ..body = jsonEncode({
        'model': model,
        'max_tokens': _maxTokens,
        'stream': true,
        if (systemPrompt != null && systemPrompt.isNotEmpty) 'system': systemPrompt,
        'messages': messages.map((m) => m.toJson()).toList(),
      });

    final http.StreamedResponse response;
    try {
      response = await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      throw LlmClientException("Could not reach $baseUrl. Check the base URL in Settings ($e).");
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw LlmClientException('Anthropic API error (${response.statusCode}): $body');
    }

    await for (final line in withLlmStallTimeout(
      response.stream.transform(utf8.decoder).transform(const LineSplitter()),
    )) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      Map<String, dynamic> event;
      try {
        event = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final type = event['type'];
      if (type == 'content_block_delta') {
        final delta = event['delta'] as Map?;
        if (delta?['type'] == 'text_delta') {
          final text = delta?['text'] as String?;
          if (text != null && text.isNotEmpty) yield text;
        }
      } else if (type == 'error') {
        final error = event['error'];
        throw LlmClientException('Anthropic API stream error: ${error is Map ? error['message'] : error}');
      }
    }
  }

  @override
  Future<List<String>> listModels() async {
    if (apiKey.isEmpty) {
      throw LlmClientException('No Anthropic API key (or subscription token) configured yet.');
    }
    final uri = Uri.parse('$baseUrl/models');
    http.Response response;
    try {
      response = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw LlmClientException("Could not reach $baseUrl ($e).");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmClientException('Anthropic API error (${response.statusCode}): ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final models = (data['data'] as List? ?? [])
        .map((m) => (m as Map<String, dynamic>)['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    return models;
  }
}
