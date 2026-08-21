import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quds_db_interface/quds_db_interface.dart';
import 'package:redis/redis.dart';

import '../cache/cache_driver.dart';
import '../cache/redis_cache_driver.dart';
import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../logging/quds_log.dart';

/// Result of [ReadinessChecker.inspect].
class ReadinessReport {
  final bool ready;
  final Map<String, dynamic> body;

  const ReadinessReport({required this.ready, required this.body});

  int get statusCode => ready ? 200 : 503;
}

/// Outcome of a custom [HealthProbe].
class HealthCheckResult {
  final String name;
  final bool ok;
  final String? message;

  const HealthCheckResult(this.name, {required this.ok, this.message});

  factory HealthCheckResult.ok(String name) =>
      HealthCheckResult(name, ok: true);

  factory HealthCheckResult.error(String name, [String? message]) =>
      HealthCheckResult(name, ok: false, message: message);
}

typedef HealthProbe = Future<HealthCheckResult> Function();

/// Posts when readiness changes (`HEALTH_WEBHOOK_URL` and/or [onChange]).
class HealthNotifier {
  static bool? _lastReady;

  /// Invoked on a ready → not_ready or not_ready → ready transition.
  static Future<void> Function(ReadinessReport report)? onChange;

  /// Override in tests.
  static http.Client? httpClient;

  static Future<void> maybeNotify(ReadinessReport report) async {
    if (_lastReady == report.ready) return;
    final previous = _lastReady;
    _lastReady = report.ready;
    if (previous == null && report.ready) return;

    try {
      await onChange?.call(report);
    } catch (e) {
      Log.warning('HealthNotifier.onChange failed: $e');
    }

    final url = env<String>('HEALTH_WEBHOOK_URL');
    if (url == null || url.isEmpty) return;

    try {
      final client = httpClient ?? http.Client();
      await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ready': report.ready,
          'status': report.ready ? 'ready' : 'not_ready',
          'body': report.body,
        }),
      );
    } catch (e) {
      Log.warning('Health webhook failed: $e');
    }
  }

  static void reset() {
    _lastReady = null;
    onChange = null;
    httpClient = null;
  }
}

/// Dependency probes for `/quds/ready`.
///
/// Liveness (`/quds/health`) stays a process-alive check. This class pings
/// configured dependencies so orchestrators do not send traffic to a dead DB.
class ReadinessChecker {
  static final List<HealthProbe> _custom = [];

  /// Registers an extra probe included in [inspect] (e.g. SMTP, search).
  static void add(HealthProbe probe) => _custom.add(probe);

  static void clear() => _custom.clear();

  /// Inspects registered dependencies.
  ///
  /// Redis is probed only when `CACHE_DRIVER=redis` or `BROADCAST_DRIVER=redis`
  /// (or a [RedisCacheDriver] is already bound). Apps that never set those
  /// keep the previous payload shape: `database` + `status`.
  static Future<ReadinessReport> inspect() async {
    final body = <String, dynamic>{};
    var ready = true;

    if (!QudsContainer.isRegistered<DatabaseConnection>()) {
      ready = false;
      body['database'] = 'not_configured';
    } else {
      try {
        final connection = QudsContainer.resolve<DatabaseConnection>();
        if (!connection.isOpen) {
          ready = false;
          body['database'] = 'error';
          body['message'] = 'Database connection is closed';
        } else {
          await connection.query('SELECT 1');
          body['database'] = 'ok';
        }
      } catch (e) {
        ready = false;
        body['database'] = 'error';
        body['message'] = e.toString();
      }
    }

    if (_shouldCheckRedis()) {
      try {
        await pingRedis();
        body['redis'] = 'ok';
      } catch (e) {
        ready = false;
        body['redis'] = 'error';
        body.putIfAbsent('message', () => e.toString());
      }
    }

    for (final probe in List<HealthProbe>.from(_custom)) {
      try {
        final result = await probe();
        final name = result.name == 'status' ? 'check_status' : result.name;
        body[name] = result.ok ? 'ok' : 'error';
        if (!result.ok) {
          ready = false;
          if (result.message != null) {
            body.putIfAbsent('message', () => result.message);
          }
        }
      } catch (e) {
        ready = false;
        body['custom'] = 'error';
        body.putIfAbsent('message', () => e.toString());
      }
    }

    body['status'] = ready ? 'ready' : 'not_ready';
    final report = ReadinessReport(ready: ready, body: body);
    await HealthNotifier.maybeNotify(report);
    return report;
  }

  static bool _shouldCheckRedis() {
    final cache =
        (env<String>('CACHE_DRIVER', 'memory') ?? 'memory').toLowerCase();
    final broadcast =
        (env<String>('BROADCAST_DRIVER', 'local') ?? 'local').toLowerCase();
    if (cache == 'redis' || broadcast == 'redis') return true;
    if (QudsContainer.isRegistered<CacheDriver>()) {
      return QudsContainer.resolve<CacheDriver>() is RedisCacheDriver;
    }
    return false;
  }
}

/// Pings Redis using the bound [RedisCacheDriver] when possible, otherwise
/// a short-lived connection from `REDIS_*` env.
Future<void> pingRedis() async {
  if (QudsContainer.isRegistered<CacheDriver>()) {
    final driver = QudsContainer.resolve<CacheDriver>();
    if (driver is RedisCacheDriver) {
      await driver.ping();
      return;
    }
  }

  final host = env<String>('REDIS_HOST', '127.0.0.1') ?? '127.0.0.1';
  final port = env<int>('REDIS_PORT', 6379) ?? 6379;
  final password = env<String>('REDIS_PASSWORD');
  final conn = RedisConnection();
  try {
    final command = await conn.connect(host, port);
    if (password != null && password.isNotEmpty) {
      await command.send_object(['AUTH', password]);
    }
    final reply = await command.send_object(['PING']);
    if (reply.toString().toUpperCase() != 'PONG') {
      throw StateError('Redis PING returned $reply');
    }
  } finally {
    try {
      await conn.close();
    } catch (e) {
      Log.debug('Redis ping connection close: $e');
    }
  }
}
