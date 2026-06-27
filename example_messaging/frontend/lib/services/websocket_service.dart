import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  final String wsUrl;
  WebSocketChannel? _channel;

  WebSocketService({this.wsUrl = 'ws://localhost:8080/ws'});

  WebSocketChannel connect(
    String currentUser,
    Function(dynamic) onMessage,
    Function(dynamic) onError,
    Function() onDone,
  ) {
    final wsUri = Uri.parse(wsUrl);
    _channel = WebSocketChannel.connect(wsUri);

    final subscribeEvent = jsonEncode({
      'event': 'subscribe',
      'channel': 'chat.$currentUser',
    });
    _channel!.sink.add(subscribeEvent);

    _channel!.stream.listen(
      onMessage,
      onError: onError,
      onDone: onDone,
    );

    return _channel!;
  }

  void sendTypingState(String currentUser, String activeContact, bool isTyping) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      'event': 'publish',
      'channel': 'chat.$activeContact',
      'name': 'TypingStateChanged',
      'data': {
        'sender': currentUser,
        'isTyping': isTyping,
      },
    }));
  }

  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
