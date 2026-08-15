import 'dart:convert';

import 'package:redis/redis.dart';

import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'cache_driver.dart';

/// Redis-backed [CacheDriver]. Used when `CACHE_DRIVER=redis`.
///
/// Connection is established lazily on the first cache operation.
class RedisCacheDriver implements CacheDriver {
  final String host;
  final int port;
  final String? password;
  final String keyPrefix;

  Command? _command;
  Future<Command>? _connecting;

  RedisCacheDriver({
    String? host,
    int? port,
    String? password,
    String? keyPrefix,
  })  : host = host ?? env<String>('REDIS_HOST', '127.0.0.1') ?? '127.0.0.1',
        port = port ?? env<int>('REDIS_PORT', 6379) ?? 6379,
        password = password ?? env<String>('REDIS_PASSWORD'),
        keyPrefix =
            keyPrefix ?? env<String>('REDIS_PREFIX', 'quds:') ?? 'quds:';

  String _key(String key) => '$keyPrefix$key';

  Future<Command> _cmd() async {
    if (_command != null) return _command!;
    if (_connecting != null) return _connecting!;

    _connecting = () async {
      final conn = RedisConnection();
      final command = await conn.connect(host, port);
      final pass = password;
      if (pass != null && pass.isNotEmpty) {
        await command.send_object(['AUTH', pass]);
      }
      _command = command;
      Log.debug('Redis cache connected to $host:$port');
      return command;
    }();

    try {
      return await _connecting!;
    } catch (e) {
      _connecting = null;
      rethrow;
    }
  }

  @override
  Future<dynamic> get(String key) async {
    final cmd = await _cmd();
    final raw = await cmd.send_object(['GET', _key(key)]);
    if (raw == null) return null;
    try {
      return jsonDecode(raw as String);
    } catch (_) {
      return raw;
    }
  }

  @override
  Future<void> put(String key, dynamic value, {Duration? ttl}) async {
    final cmd = await _cmd();
    final encoded = jsonEncode(value);
    final redisKey = _key(key);
    if (ttl != null && ttl.inSeconds > 0) {
      await cmd.send_object([
        'SET',
        redisKey,
        encoded,
        'EX',
        ttl.inSeconds.toString(),
      ]);
    } else {
      await cmd.send_object(['SET', redisKey, encoded]);
    }
  }

  @override
  Future<void> forget(String key) async {
    final cmd = await _cmd();
    await cmd.send_object(['DEL', _key(key)]);
  }

  @override
  Future<void> flush() async {
    final cmd = await _cmd();
    // Only delete keys with our prefix to avoid wiping the whole Redis DB.
    var cursor = '0';
    do {
      final result = await cmd.send_object([
        'SCAN',
        cursor,
        'MATCH',
        '$keyPrefix*',
        'COUNT',
        '100',
      ]);
      if (result is! List || result.length < 2) break;
      cursor = result[0].toString();
      final keys = result[1];
      if (keys is List && keys.isNotEmpty) {
        await cmd.send_object(['DEL', ...keys]);
      }
    } while (cursor != '0');
  }
}
