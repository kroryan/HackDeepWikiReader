import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_models.dart';
import '../models/endpoint.dart';
import 'stream_parser.dart';

/// Opens /ws/chat on a connected endpoint and streams the response --
/// mirrors src/utils/websocketClient.ts's createChatWebSocket exactly (same
/// request JSON shape, same URL scheme swap), so this talks to the
/// unmodified backend the web app already uses.
class ChatSocket {
  final Endpoint endpoint;
  WebSocketChannel? _channel;
  final _parser = StreamParser();

  ChatSocket(this.endpoint);

  Uri get _wsUri {
    final httpUri = Uri.parse(endpoint.normalizedBaseUrl);
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme, path: '/ws/chat');
  }

  /// Sends [request] and streams (answerTextDelta, processEvents) pairs as
  /// they arrive. The stream completes when the server closes the
  /// connection. Call [close] to abort early.
  Stream<StreamFeedResult> send(ChatCompletionRequest request) {
    final channel = WebSocketChannel.connect(_wsUri);
    _channel = channel;
    channel.sink.add(jsonEncode(request.toJson()));

    final controller = StreamController<StreamFeedResult>();
    channel.stream.listen(
      (data) {
        final chunk = data is String ? data : utf8.decode(data as List<int>);
        controller.add(_parser.feed(chunk));
      },
      onError: (Object error, StackTrace st) {
        if (!controller.isClosed) controller.addError(error, st);
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: true,
    );
    return controller.stream;
  }

  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
