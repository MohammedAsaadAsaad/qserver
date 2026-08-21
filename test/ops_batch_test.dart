import 'dart:io';

import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

class _SlowJob extends Job {
  _SlowJob(this.delay, this.name);
  final Duration delay;
  final String name;

  @override
  String get label => name;

  @override
  Future<void> handle() => Future<void>.delayed(delay);
}

class _FailOnce extends Job {
  @override
  int get maxRetries => 1;

  @override
  String get label => 'FailOnce';

  @override
  Future<void> handle() async {
    throw StateError('nope');
  }
}

class _UserFake implements DatabaseConnection {
  final List<Map<String, dynamic>> users = [];

  @override
  bool isOpen = true;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final params = parameters ?? const [];
    final n = sql.replaceAll(RegExp(r'\s+'), ' ');
    if (n.contains('WHERE id =')) {
      return users.where((u) => u['id'] == params[0]).toList();
    }
    if (n.contains('WHERE email =')) {
      return users.where((u) => u['email'] == params[0]).toList();
    }
    if (n.contains('WHERE provider =')) {
      return users
          .where((u) => u['provider'] == params[0] && u['provider_id'] == params[1])
          .toList();
    }
    return [];
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    final params = parameters ?? const [];
    final n = sql.replaceAll(RegExp(r'\s+'), ' ');
    if (n.startsWith('CREATE TABLE')) return 0;
    if (n.startsWith('INSERT INTO quds_users')) {
      users.add({
        'id': params[0],
        'email': params[1],
        'name': params[2],
        'password_hash': params[3],
        'provider': params[4],
        'provider_id': params[5],
        'email_verified': params[6],
        'extra': params[7],
      });
      return 1;
    }
    if (n.startsWith('UPDATE quds_users')) {
      final id = params[7];
      for (final row in users) {
        if (row['id'] == id) {
          row['email'] = params[0];
          row['name'] = params[1];
          row['password_hash'] = params[2];
          row['provider'] = params[3];
          row['provider_id'] = params[4];
          row['email_verified'] = params[5];
          row['extra'] = params[6];
          return 1;
        }
      }
      return 0;
    }
    return 0;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() operation) => operation();

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(() {
    Log.reset();
    QudsContainer.clear();
    Mailer.reset();
    EmailAuth.reset();
    FailedJobLog.clear();
    QueueRuntime.reset();
    ServerMonitor.enabled = true;
    ServerMonitor.endLive();
    QudsEnv.set('QUDS_METRICS', null);
    QudsEnv.set('QUDS_METRICS_TOKEN', null);
    QudsEnv.set('QUDS_INSIGHTS', null);
    QudsEnv.set('QUDS_INSIGHTS_TOKEN', null);
    QudsEnv.set('QUDS_LOG_FILE', null);
    QudsEnv.set('QUEUE_CONCURRENCY', null);
    QudsEnv.set('AUTH_USER_STORE', null);
  });

  test('MemoryQueueDriver inspects waiting and delayed jobs', () async {
    final driver = MemoryQueueDriver();
    await driver.push(_SlowJob(Duration.zero, 'now'));
    final delayed = _SlowJob(Duration.zero, 'later');
    delayed.availableAt = DateTime.now().add(const Duration(hours: 1));
    await driver.push(delayed);
    final snap = driver.inspect();
    expect(snap.waiting, 1);
    expect(snap.delayed, 1);
  });

  test('default worker concurrency is 1', () {
    QudsEnv.set('QUEUE_CONCURRENCY', null);
    expect(QueueWorker(MemoryQueueDriver()).concurrency, 1);
  });

  test('QUEUE_CONCURRENCY=2 runs two jobs in parallel', () async {
    final driver = MemoryQueueDriver();
    QudsContainer.singleton<QueueDriver>(driver);
    await driver.push(_SlowJob(const Duration(milliseconds: 80), 'a'));
    await driver.push(_SlowJob(const Duration(milliseconds: 80), 'b'));

    final worker = QueueWorker(driver, 2);
    expect(worker.concurrency, 2);
    final sw = Stopwatch()..start();
    worker.start();
    var empty = false;
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (driver.inspect().pending == 0 && QueueRuntime.running.isEmpty) {
        empty = true;
        break;
      }
    }
    final elapsed = sw.elapsedMilliseconds;
    await worker.stop(timeout: const Duration(seconds: 2));
    expect(empty, isTrue);
    expect(elapsed, lessThan(250));
  });

  test('dead-letter jobs land in FailedJobLog', () async {
    final driver = MemoryQueueDriver();
    QudsContainer.singleton<QueueDriver>(driver);
    await driver.push(_FailOnce());
    final worker = QueueWorker(driver);
    worker.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await worker.stop(timeout: const Duration(seconds: 2));
    expect(FailedJobLog.total, 1);
    expect(FailedJobLog.recent.single.label, 'FailOnce');
  });

  test('Mailer.send fires when token callbacks are unset', () async {
    QudsContainer.singleton<TokenStore>(MemoryTokenStore());
    QudsContainer.singleton<UserStore>(MemoryUserStore());
    MailMessage? seen;
    Mailer.send = (message) async => seen = message;

    await EmailAuth.register(email: 'm@x.com', password: 'secret123');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen, isNotNull);
    expect(seen!.purpose, 'verify_email');
    expect(seen!.to, 'm@x.com');
    expect(seen!.token, isNotEmpty);
  });

  test('onVerificationToken still works without Mailer', () async {
    QudsContainer.singleton<TokenStore>(MemoryTokenStore());
    QudsContainer.singleton<UserStore>(MemoryUserStore());
    String? token;
    EmailAuth.onVerificationToken = (user, t) => token = t;
    await EmailAuth.register(email: 'c@x.com', password: 'secret123');
    expect(token, isNotNull);
    expect(await EmailAuth.verifyEmail(token!), isTrue);
  });

  test('DatabaseUserStore persists and updates a user', () async {
    final fake = _UserFake();
    final store = DatabaseUserStore(fake);
    final created = await store.create(
      const AuthUser(
        id: 'u1',
        email: 'A@X.com',
        name: 'Ada',
        provider: 'email',
      ),
    );
    expect(created.email, 'A@X.com');
    final found = await store.findByEmail('a@x.com');
    expect(found, isNotNull);
    expect(found!.name, 'Ada');

    await store.update(found.copyWith(emailVerified: true, name: 'Ada L'));
    final again = await store.findById('u1');
    expect(again!.emailVerified, isTrue);
    expect(again.name, 'Ada L');
  });

  test('metrics route is off by default and on when QUDS_METRICS=true', () async {
    final off = QudsRouter();
    MetricsRoutes.register(off);
    expect(off.hasRoute(HttpMethod.get, '/quds/metrics'), isFalse);

    QudsEnv.set('QUDS_METRICS', 'true');
    final on = QudsRouter();
    MetricsRoutes.register(on);
    expect(on.hasRoute(HttpMethod.get, '/quds/metrics'), isTrue);

    final client = QudsTestClient(on);
    final res = await client.get('/quds/metrics');
    expect(res.statusCode, 200);
    expect(res.body, contains('quds_http_requests_all_total'));
    expect(res.body, contains('quds_queue_waiting'));
  });

  test('insights failed-jobs is registered only when insights is on', () async {
    final off = QudsRouter();
    InsightsRoutes.register(off);
    expect(off.hasRoute(HttpMethod.get, '/quds/insights/failed-jobs'), isFalse);

    QudsEnv.set('QUDS_INSIGHTS', 'true');
    QudsEnv.set('QUDS_INSIGHTS_TOKEN', 't');
    final on = QudsRouter();
    InsightsRoutes.register(on);
    final client = QudsTestClient(on);
    final res = await client.get(
      '/quds/insights/failed-jobs',
      query: {'token': 't'},
    );
    expect(res.statusCode, 200);
    expect(res.body, contains('"total":0'));
  });

  test('log file sink stays off unless enabled', () {
    final dir = Directory.systemTemp.createTempSync('qserver_log_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    Log.filePath = '${dir.path}/app.log';
    Log.color = false;
    Log.writer = (_) {};
    Log.info('not on disk');
    expect(File(Log.filePath).existsSync(), isFalse);

    Log.fileSink = true;
    Log.info('on disk');
    expect(File(Log.filePath).readAsStringSync(), contains('on disk'));
  });

  test('hot restart does not supervise under package:test', () async {
    expect(HotRestart.inTest, isTrue);
    expect(await HotRestart.maybeSupervise(), isFalse);
    expect(HotRestart.shouldWatchPath('lib/main.dart'), isTrue);
    expect(HotRestart.shouldWatchPath('.env'), isTrue);
    expect(HotRestart.shouldWatchPath('lib/.dart_tool/foo.dart'), isFalse);
  });

  test('AUTH_USER_STORE=database does not replace a custom UserStore', () async {
    final custom = _CustomStore();
    QudsContainer.singleton<UserStore>(custom);
    QudsContainer.singleton<DatabaseConnection>(_UserFake());
    QudsEnv.set('AUTH_USER_STORE', 'database');

    final app = QudsServerApp();
    await app.registerProviders([]);
    expect(identical(QudsContainer.resolve<UserStore>(), custom), isTrue);
  });
}

class _CustomStore implements UserStore {
  @override
  Future<AuthUser?> findById(String id) async => null;

  @override
  Future<AuthUser?> findByEmail(String email) async => null;

  @override
  Future<AuthUser?> findByProvider(String provider, String providerId) async =>
      null;

  @override
  Future<AuthUser> create(AuthUser user) async => user;

  @override
  Future<AuthUser> update(AuthUser user) async => user;
}
