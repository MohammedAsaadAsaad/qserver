import 'dart:convert';
import 'dart:io';
import '../http/auth/auth.dart';

typedef ChannelAuthCallback =
    Future<bool> Function(Map<String, dynamic>? user, String channelName);

class BroadcastManager {
  // Maps channel names to a list of connected client sockets
  final Map<String, List<WebSocket>> _channels = {};

  // Maps channel patterns to authorization rules
  final Map<String, ChannelAuthCallback> _authRules = {};

  int get activeConnectionsCount {
    final uniqueSockets = <WebSocket>{};
    _channels.values.forEach((list) => uniqueSockets.addAll(list));
    return uniqueSockets.length;
  }

  /// Registers an authorization rule for a specific channel pattern
  void defineChannel(String name, ChannelAuthCallback check) {
    _authRules[name] = check;
  }

  /// Upgrades an incoming HTTP request and handles the active socket
  Future<void> handleUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) return;

    final socket = await WebSocketTransformer.upgrade(request);
    print('🔌 New WebSocket client connected');

    socket.listen(
      (message) => _handleClientMessage(socket, message),
      onDone: () => _removeSocket(socket),
      onError: (e) => _removeSocket(socket),
    );
  }

  /// Parses messages from the frontend (e.g., subscribing to a room)
  Future<void> _handleClientMessage(WebSocket socket, dynamic message) async {
    try {
      final data = jsonDecode(message);
      final event = data['event'];
      final channel = data['channel'];
      final token = data['token']; // The client sends their JWT token for auth

      if (event == 'subscribe' && channel != null) {
        await _subscribeToChannel(socket, channel, token);
      }
    } catch (e) {
      // Ignore malformed messages
    }
  }

  Future<void> _subscribeToChannel(
    WebSocket socket,
    String channel,
    String? token,
  ) async {
    Map<String, dynamic>? user;
    if (token != null) {
      user = Auth.verify(token);
    }

    // 1. Check if an authorization rule exists for this channel
    bool isAuthorized = true;
    for (var ruleName in _authRules.keys) {
      // Basic prefix matching (e.g., 'chat.*' matches 'chat.1')
      if (channel.startsWith(ruleName.replaceAll('*', ''))) {
        isAuthorized = await _authRules[ruleName]!(user, channel);
        break;
      }
    }

    if (!isAuthorized) {
      socket.add(
        jsonEncode({
          'event': 'subscription_error',
          'channel': channel,
          'message': 'Unauthorized',
        }),
      );
      return;
    }

    // 2. Add socket to the channel list
    if (!_channels.containsKey(channel)) {
      _channels[channel] = [];
    }
    _channels[channel]!.add(socket);

    socket.add(jsonEncode({'event': 'subscribed', 'channel': channel}));
    print('📡 Client subscribed to [$channel]');
  }

  /// Pushes an event payload to all clients connected to a specific channel
  void emit(String channel, String event, Map<String, dynamic> data) {
    if (_channels.containsKey(channel)) {
      final payload = jsonEncode({
        'channel': channel,
        'event': event,
        'data': data,
      });

      for (var socket in _channels[channel]!) {
        socket.add(payload);
      }
    }
  }

  /// Cleans up disconnected sockets to prevent memory leaks
  void _removeSocket(WebSocket socket) {
    _channels.forEach((channel, sockets) {
      sockets.remove(socket);
    });
  }
}
