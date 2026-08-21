import 'dart:async';
import 'dart:convert';

import 'package:redis/redis.dart';

import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'broadcast_manager.dart';

/// Minimal Redis pub/sub bridge for multi-instance broadcasting.
///
/// Enable with `BROADCAST_DRIVER=redis`. Local sockets still receive events
/// via [BroadcastManager.emit]; remote instances receive via Redis.
class RedisBroadcastBridge {
  static const String channelName = 'quds:broadcast';

  static BroadcastManager? _manager;
  static RedisConnection? _pubConn;
  static Command? _pubCommand;
  static bool _listening = false;
  static bool _attached = false;

  /// Whether the bridge is active.
  static bool get isAttached => _attached;

  /// Connects pub/sub and hooks [manager.emit] fan-out.
  static Future<void> attach(BroadcastManager manager) async {
    if (_attached) return;
    _manager = manager;

    final host = env<String>('REDIS_HOST', '127.0.0.1') ?? '127.0.0.1';
    final port = env<int>('REDIS_PORT', 6379) ?? 6379;
    final password = env<String>('REDIS_PASSWORD');

    try {
      final pubConn = RedisConnection();
      _pubConn = pubConn;
      _pubCommand = await pubConn.connect(host, port);
      if (password != null && password.isNotEmpty) {
        await _pubCommand!.send_object(['AUTH', password]);
      }

      manager.remotePublish = _publish;
      _attached = true;
      Log.info('Redis bridge attached $host:$port', component: 'ws');

      // Subscribe on a separate connection (Redis pub/sub requirement).
      unawaited(_listen(host, port, password));
    } catch (e) {
      Log.warning(
        'Redis broadcast requires BROADCAST_DRIVER=redis and a reachable Redis. '
        'Attach failed: $e',
        component: 'ws',
      );
    }
  }

  static Future<void> _publish(
    String channel,
    String event,
    Map<String, dynamic> data,
  ) async {
    final cmd = _pubCommand;
    if (cmd == null) return;
    final payload = jsonEncode({
      'channel': channel,
      'event': event,
      'data': data,
      'origin': pidHint,
    });
    await cmd.send_object(['PUBLISH', channelName, payload]);
  }

  /// Opaque origin tag so local emit does not echo back to the same process.
  static final String pidHint =
      'qserver-${DateTime.now().microsecondsSinceEpoch}';

  static Future<void> _listen(String host, int port, String? password) async {
    if (_listening) return;
    _listening = true;
    try {
      final subConn = RedisConnection();
      final command = await subConn.connect(host, port);
      if (password != null && password.isNotEmpty) {
        await command.send_object(['AUTH', password]);
      }

      final pubsub = PubSub(command);
      pubsub.subscribe([channelName]);

      pubsub.getStream().listen((message) {
        try {
          // Typical shape: ['message', channel, payload]
          if (message is! List || message.length < 3) return;
          if (message[0].toString() != 'message') return;
          final raw = message[2];
          if (raw == null) return;
          final map = jsonDecode(raw.toString()) as Map<String, dynamic>;
          if (map['origin'] == pidHint) return; // skip own publishes
          final ch = map['channel']?.toString();
          final event = map['event']?.toString();
          final data = map['data'];
          if (ch == null || event == null || data is! Map) return;
          _manager?.emitLocal(
            ch,
            event,
            Map<String, dynamic>.from(data),
          );
        } catch (e) {
          Log.debug('Redis broadcast message ignored: $e');
        }
      });
    } catch (e) {
      _listening = false;
      Log.warning('Redis broadcast subscribe failed: $e');
    }
  }

  /// Closes the publisher connection. Subscriber sockets drop with the process.
  static Future<void> detach() async {
    _attached = false;
    _listening = false;
    _manager?.remotePublish = null;
    _manager = null;
    _pubCommand = null;
    final conn = _pubConn;
    _pubConn = null;
    if (conn != null) {
      try {
        await conn.close();
      } catch (e) {
        Log.debug('Redis broadcast detach: $e');
      }
    }
  }

  /// Test helper.
  static void reset() {
    _attached = false;
    _listening = false;
    _manager = null;
    _pubCommand = null;
    _pubConn = null;
  }
}
