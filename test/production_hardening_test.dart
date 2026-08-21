import 'dart:io';

import 'package:qserver/qserver.dart';
import 'package:qserver/src/http/request_parser.dart';
import 'package:test/test.dart';

class _OkJob extends SerializableJob {
  _OkJob([this.payload = const {}]);

  final Map<String, dynamic> payload;

  @override
  String get jobType => 'ok_job';

  @override
  Map<String, dynamic> toMap() => payload;

  @override
  Future<void> handle() async {}
}

class _BoomJob extends SerializableJob {
  @override
  String get jobType => 'boom_job';

  @override
  int get maxRetries => 1;

  @override
  Map<String, dynamic> toMap() => {};

  @override
  Future<void> handle() async {
    throw StateError('boom');
  }
}

class _FakeConnection implements DatabaseConnection {
  final Map<String, List<Map<String, dynamic>>> tables = {
    'quds_jobs': [],
    'quds_failed_jobs': [],
    'quds_migrations': [],
    'quds_migration_lock': [],
  };

  @override
  bool isOpen = true;
  Object? queryError;
  int selectOneCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    if (queryError != null) throw queryError!;
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.toUpperCase().startsWith('SELECT 1')) {
      selectOneCalls++;
      return [
        {'1': 1},
      ];
    }

    final params = parameters ?? const [];
    if (normalized.contains('FROM quds_jobs') &&
        normalized.contains('SELECT id, job_type')) {
      final now = DateTime.now().toUtc();
      final jobs = tables['quds_jobs']!;
      final ready = jobs.where((row) {
        final reserved = row['reserved_at']?.toString();
        if (reserved != null) {
          final reservedAt = DateTime.tryParse(reserved);
          if (reservedAt != null &&
              now.difference(reservedAt) < const Duration(minutes: 10)) {
            return false;
          }
        }
        final available = row['available_at']?.toString();
        if (available != null) {
          final at = DateTime.tryParse(available);
          if (at != null && at.isAfter(now)) return false;
        }
        return true;
      }).toList();
      return ready.take(1).map((e) => Map<String, dynamic>.from(e)).toList();
    }

    if (normalized.contains('FROM quds_jobs') &&
        normalized.contains('reserved_at =')) {
      final id = params[0];
      final reservedAt = params[1];
      return tables['quds_jobs']!
          .where((r) => r['id'] == id && r['reserved_at'] == reservedAt)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (normalized.contains('FROM quds_jobs') &&
        normalized.contains('reserved_at IS NULL')) {
      final id = params.isEmpty ? null : params[0];
      return tables['quds_jobs']!
          .where((r) => r['id'] == id && r['reserved_at'] == null)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (normalized.contains('FROM quds_migrations')) {
      return tables['quds_migrations']!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    final params = parameters ?? const [];

    if (normalized.startsWith('CREATE TABLE')) return 0;

    if (normalized.startsWith('INSERT INTO quds_jobs')) {
      tables['quds_jobs']!.add({
        'id': params[0],
        'job_type': params[1],
        'payload': params[2],
        'attempts': params[3],
        'available_at': params[4],
        'created_at': params[5],
        'reserved_at': null,
      });
      return 1;
    }

    if (normalized.startsWith('UPDATE quds_jobs') &&
        normalized.contains('SET reserved_at')) {
      final reservedAt = params[0];
      final id = params[1];
      final row = tables['quds_jobs']!.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r!['id'] == id && r['reserved_at'] == null,
            orElse: () => null,
          );
      if (row == null) return 0;
      row['reserved_at'] = reservedAt;
      return 1;
    }

    if (normalized.startsWith('UPDATE quds_jobs') &&
        normalized.contains('SET reserved_at = NULL')) {
      final id = params[2];
      for (final row in tables['quds_jobs']!) {
        if (row['id'] == id) {
          row['reserved_at'] = null;
          row['attempts'] = params[0];
          row['available_at'] = params[1];
          return 1;
        }
      }
      return 0;
    }

    if (normalized.startsWith('DELETE FROM quds_jobs')) {
      final id = params[0];
      final before = tables['quds_jobs']!.length;
      tables['quds_jobs']!.removeWhere((r) => r['id'] == id);
      return before - tables['quds_jobs']!.length;
    }

    if (normalized.startsWith('INSERT INTO quds_failed_jobs')) {
      tables['quds_failed_jobs']!.add({
        'id': params[0],
        'job_type': params[1],
        'payload': params[2],
        'attempts': params[3],
        'error': params[4],
        'failed_at': params[5],
      });
      return 1;
    }

    if (normalized.startsWith('DELETE FROM quds_failed_jobs')) {
      final id = params[0];
      tables['quds_failed_jobs']!.removeWhere((r) => r['id'] == id);
      return 1;
    }

    if (normalized.startsWith('INSERT INTO quds_migration_lock')) {
      if (tables['quds_migration_lock']!.isNotEmpty) {
        throw StateError('duplicate lock');
      }
      tables['quds_migration_lock']!.add({
        'lock_id': params[0],
        'owner': params[1],
        'locked_at': params[2],
      });
      return 1;
    }

    if (normalized.startsWith('DELETE FROM quds_migration_lock')) {
      tables['quds_migration_lock']!.clear();
      return 1;
    }

    if (normalized.startsWith('INSERT INTO quds_migrations')) {
      tables['quds_migrations']!.add({
        'id': params[0],
        'applied_at': params[1],
      });
      return 1;
    }

    if (normalized.startsWith('DELETE FROM quds_migrations')) {
      final id = params[0];
      tables['quds_migrations']!.removeWhere((r) => r['id'] == id);
      return 1;
    }

    return 0;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() operation) => operation();

  @override
  Future<void> close() async => isOpen = false;

  @override
  Future<int?> insert(String tableName, Map<String, dynamic> values) {
    throw UnimplementedError();
  }

  @override
  Future<int> update(
    String tableName,
    Map<String, dynamic> values,
    String where, [
    List<dynamic>? parameters,
  ]) {
    throw UnimplementedError();
  }

  @override
  Future<int> delete(
    String tableName,
    String where, [
    List<dynamic>? parameters,
  ]) {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    ServerMonitor.enabled = false;
    ExceptionLog.logToFile = false;
    ExceptionLog.clear();
  });

  tearDown(() {
    QudsContainer.clear();
    JobRegistry.clear();
    ExceptionLog.clear();
    ReadinessChecker.clear();
    HealthNotifier.reset();
    ServerMonitor.enabled = true;
    ExceptionLog.logToFile = true;
  });

  group('operational HTTP exceptions', () {
    test('payload too large maps to 413 and is expected', () {
      final error = QudsPayloadTooLargeException(maxBytes: 10);
      expect(GlobalExceptionHandler.statusOf(error), 413);
      expect(GlobalExceptionHandler.isExpected(error), isTrue);
      expect(GlobalExceptionHandler.toResponse(error).statusCode, 413);
    });

    test('timeout maps to 504', () {
      final error = QudsRequestTimeoutException(const Duration(seconds: 2));
      expect(GlobalExceptionHandler.toResponse(error).statusCode, 504);
    });

    test('rejectIfTooLarge is a no-op when maxBytes is 0', () {
      RequestParser.rejectIfTooLarge(999999, 0);
    });

    test('rejectIfTooLarge throws when content-length exceeds max', () {
      expect(
        () => RequestParser.rejectIfTooLarge(11, 10),
        throwsA(isA<QudsPayloadTooLargeException>()),
      );
    });
  });

  group('ReadinessChecker', () {
    test('not_configured when no database is bound (same as 0.0.10)', () async {
      final report = await ReadinessChecker.inspect();
      expect(report.ready, isFalse);
      expect(report.statusCode, 503);
      expect(report.body['database'], 'not_configured');
      expect(report.body['status'], 'not_ready');
      expect(report.body.containsKey('redis'), isFalse);
    });

    test('pings the database when a connection is bound', () async {
      final fake = _FakeConnection();
      QudsContainer.singleton<DatabaseConnection>(fake);
      final report = await ReadinessChecker.inspect();
      expect(report.ready, isTrue);
      expect(report.body['database'], 'ok');
      expect(report.body['status'], 'ready');
      expect(fake.selectOneCalls, 1);
    });

    test('returns 503 when the database ping fails', () async {
      final fake = _FakeConnection()..queryError = StateError('down');
      QudsContainer.singleton<DatabaseConnection>(fake);
      final report = await ReadinessChecker.inspect();
      expect(report.ready, isFalse);
      expect(report.statusCode, 503);
      expect(report.body['database'], 'error');
    });

    test('returns 503 when the connection is closed', () async {
      final fake = _FakeConnection()..isOpen = false;
      QudsContainer.singleton<DatabaseConnection>(fake);
      final report = await ReadinessChecker.inspect();
      expect(report.ready, isFalse);
      expect(report.body['database'], 'error');
    });
  });

  group('ServerRuntime defaults', () {
    test('unlimited concurrency by default', () {
      final runtime = ServerRuntime();
      expect(runtime.maxConcurrentRequests, 0);
      expect(runtime.isAtCapacity, isFalse);
      expect(runtime.requestTimeout, isNull);
      expect(runtime.maxBodyBytes, 0);
    });

    test('capacity is detected when a limit is set', () {
      final runtime = ServerRuntime(maxConcurrentRequests: 1);
      expect(runtime.isAtCapacity, isFalse);
    });
  });

  group('Database queue reserve/ack', () {
    test('pop keeps the row until ack', () async {
      JobRegistry.register('ok_job', (data) => _OkJob(data));
      final fake = _FakeConnection();
      final driver = DatabaseQueueDriver(
        fake,
        reserveTimeout: const Duration(minutes: 15),
      );
      final job = _OkJob({'n': 1})..id = 'job-1';
      await driver.push(job);

      final popped = await driver.pop();
      expect(popped, isNotNull);
      expect(popped!.id, 'job-1');
      expect(fake.tables['quds_jobs'], hasLength(1));
      expect(fake.tables['quds_jobs']!.first['reserved_at'], isNotNull);

      await driver.ack(popped);
      expect(fake.tables['quds_jobs'], isEmpty);
    });

    test('final failure moves the row to failed_jobs', () async {
      JobRegistry.register('boom_job', (_) => _BoomJob());
      final fake = _FakeConnection();
      final driver = DatabaseQueueDriver(fake);
      final job = _BoomJob()..id = 'job-fail';
      await driver.push(job);
      final popped = await driver.pop();
      expect(popped, isNotNull);
      await driver.release(popped!, retry: false, error: 'boom');
      expect(fake.tables['quds_jobs'], isEmpty);
      expect(fake.tables['quds_failed_jobs'], hasLength(1));
    });
  });

  group('QueueWorker ack', () {
    test('acks a successful memory job (no-op) and stops', () async {
      final driver = MemoryQueueDriver();
      QudsContainer.singleton<QueueDriver>(driver);
      final worker = QueueWorker(driver);
      final job = _OkJob();
      await driver.push(job);
      worker.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await worker.stop(timeout: const Duration(seconds: 2));
      expect(worker.isRunning, isFalse);
      expect(await driver.pop(), isNull);
    });
  });

  group('FileMigrationRunner lock', () {
    test('acquires and releases the lock around migrate', () async {
      final fake = _FakeConnection();
      final root = Directory.systemTemp.createTempSync('qserver_mig_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final dir = Directory('${root.path}/_prod_lock_probe')
        ..createSync(recursive: true);
      File('${dir.path}/up.sql').writeAsStringSync('SELECT 1;');

      final runner = FileMigrationRunner(
        fake,
        migrationsPath: root.path,
      );
      final count = await runner.migrate();
      expect(count, 1);
      expect(fake.tables['quds_migration_lock'], isEmpty);
      expect(
        fake.tables['quds_migrations']!.any((r) => r['id'] == '_prod_lock_probe'),
        isTrue,
      );
    });
  });

  group('QudsServerApp.close', () {
    test('serve returns after close and health stays ok while running', () async {
      final app = QudsServerApp();
      app.router.get('/ping', (request) async {
        return QudsResponse.json({'pong': true});
      });

      final serving = app.serve(
        defaultHost: '127.0.0.1',
        defaultPort: 0,
        listenForSignals: false,
      );

      HttpServer? server;
      for (var i = 0; i < 50 && server == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        server = app.runtime.server;
      }
      expect(server, isNotNull);

      final client = HttpClient();
      addTearDown(client.close);
      final health = await client.get('127.0.0.1', server!.port, '/quds/health');
      final healthRes = await health.close();
      expect(healthRes.statusCode, 200);

      await app.close();
      await serving;
      expect(app.runtime.server, isNull);
    });
  });
}
