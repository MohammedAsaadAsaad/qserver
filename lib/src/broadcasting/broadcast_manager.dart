import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../container/quds_env.dart';
import '../http/auth/auth.dart';
import '../http/quds_response.dart';
import '../logging/quds_log.dart';

typedef ChannelAuthCallback =
    Future<bool> Function(Map<String, dynamic>? user, String channelName);

class _SocketState {
  DateTime lastActivity;
  String? token;

  _SocketState() : lastActivity = DateTime.now();
}

class BroadcastManager {
  // Maps channel names to a list of connected client sockets
  final Map<String, List<WebSocket>> _channels = {};

  // Maps channel patterns to authorization rules
  final Map<String, ChannelAuthCallback> _authRules = {};

  final Map<WebSocket, _SocketState> _socketState = {};

  Timer? _maintenanceTimer;
  bool _listeningForRevokes = false;

  int get activeConnectionsCount => _socketState.length;

  BroadcastManager() {
    _ensureMaintenance();
    _ensureRevokeListener();
  }

  void _ensureRevokeListener() {
    if (_listeningForRevokes) return;
    _listeningForRevokes = true;
    Auth.onRevoke(_closeSocketsForToken);
  }

  void _ensureMaintenance() {
    _maintenanceTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      _tickMaintenance();
    });
  }

  int get _pingIntervalSeconds =>
      env<int>('WS_PING_INTERVAL_SECONDS', 30) ?? 30;

  int get _idleTimeoutSeconds =>
      env<int>('WS_IDLE_TIMEOUT_SECONDS', 90) ?? 90;

  void _tickMaintenance() {
    final now = DateTime.now();
    final pingEvery = _pingIntervalSeconds;
    final idleAfter = _idleTimeoutSeconds;
    final toClose = <WebSocket>[];

    _socketState.forEach((socket, state) {
      final idle = now.difference(state.lastActivity);

      if (idleAfter > 0 && idle.inSeconds >= idleAfter) {
        toClose.add(socket);
        return;
      }

      if (pingEvery > 0 && idle.inSeconds >= pingEvery) {
        try {
          socket.add(jsonEncode({'event': 'ping'}));
        } catch (_) {
          toClose.add(socket);
        }
      }
    });

    for (final socket in toClose) {
      Log.debug('Closing idle WebSocket connection');
      _forceClose(socket);
    }
  }

  void _closeSocketsForToken(String token) {
    final victims = <WebSocket>[];
    _socketState.forEach((socket, state) {
      if (state.token == token) victims.add(socket);
    });
    for (final socket in victims) {
      try {
        socket.add(
          jsonEncode({
            'event': 'auth_revoked',
            'message': 'Token has been invalidated.',
          }),
        );
      } catch (_) {}
      _forceClose(socket);
    }
  }

  void _forceClose(WebSocket socket) {
    _removeSocket(socket);
    try {
      socket.close();
    } catch (_) {}
  }

  /// Registers an authorization rule for a specific channel pattern
  void defineChannel(String name, ChannelAuthCallback check) {
    _authRules[name] = check;
  }

  /// Upgrades an incoming HTTP request and handles the active socket
  Future<void> handleUpgrade(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) return;

    final socket = await WebSocketTransformer.upgrade(request);
    _socketState[socket] = _SocketState();
    Log.debug('New WebSocket client connected');

    socket.listen(
      (message) => _handleClientMessage(socket, message),
      onDone: () => _removeSocket(socket),
      onError: (e) => _removeSocket(socket),
    );
  }

  /// Parses messages from the frontend (e.g., subscribing to a room)
  Future<void> _handleClientMessage(WebSocket socket, dynamic message) async {
    final state = _socketState[socket];
    if (state == null) return;
    state.lastActivity = DateTime.now();

    try {
      final data = jsonDecode(message);
      final event = data['event'];
      final channel = data['channel'];
      final token = data['token'];

      if (event == 'pong') {
        return;
      }

      if (event == 'subscribe' && channel != null) {
        await _subscribeToChannel(socket, channel, token);
      } else if (event == 'publish' && channel != null) {
        socket.add(
          jsonEncode({
            'event': 'publish_error',
            'channel': channel,
            'message': 'Client publish is not allowed.',
          }),
        );
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
      _socketState[socket]?.token = token;
    }

    bool isAuthorized = true;
    for (var ruleName in _authRules.keys) {
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

    if (!_channels.containsKey(channel)) {
      _channels[channel] = [];
    }
    if (!_channels[channel]!.contains(socket)) {
      _channels[channel]!.add(socket);
    }

    socket.add(jsonEncode({'event': 'subscribed', 'channel': channel}));
    Log.debug('Client subscribed to [$channel]');
  }

  /// Optional hook for Redis (or other) remote fan-out. Set by [RedisBroadcastBridge].
  Future<void> Function(String channel, String event, Map<String, dynamic> data)?
      remotePublish;

  /// Pushes an event payload to all clients connected to a specific channel
  void emit(String channel, String event, Map<String, dynamic> data) {
    emitLocal(channel, event, data);
    final publish = remotePublish;
    if (publish != null) {
      unawaited(publish(channel, event, data));
    }
  }

  /// Delivers to local sockets only (used when receiving from Redis).
  void emitLocal(String channel, String event, Map<String, dynamic> data) {
    if (!_channels.containsKey(channel)) return;

    final payload = qudsJsonEncode({
      'channel': channel,
      'event': event,
      'data': data,
    });

    for (var socket in List<WebSocket>.from(_channels[channel]!)) {
      try {
        socket.add(payload);
      } catch (_) {
        _removeSocket(socket);
      }
    }
  }

  /// Cleans up disconnected sockets to prevent memory leaks
  void _removeSocket(WebSocket socket) {
    _socketState.remove(socket);
    _channels.forEach((channel, sockets) {
      sockets.remove(socket);
    });
  }
}
