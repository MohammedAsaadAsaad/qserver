import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    QudsContainer.clear();
    Auth.clearRevocations();
    EmailAuth.reset();
    SocialAuth.reset();
    ReadinessChecker.clear();
    HealthNotifier.reset();
    Storage.use(LocalStorageDisk());
    InsightsRoutes.authorizer = null;
    Mailer.reset();
    FailedJobLog.clear();
    QueueRuntime.reset();
    ExceptionLog.clear();
    ExceptionLog.logToFile = false;
    QudsEnv.set('QUDS_INSIGHTS', null);
    QudsEnv.set('QUDS_INSIGHTS_TOKEN', null);
    QudsEnv.set('HEALTH_WEBHOOK_URL', null);
    QudsEnv.set('GOOGLE_CLIENT_ID', null);
    QudsEnv.set('FILESYSTEM_DISK', null);
  });

  group('EmailAuth', () {
    test('register and login issue JWT pairs', () async {
      QudsContainer.singleton<TokenStore>(MemoryTokenStore());
      QudsContainer.singleton<UserStore>(MemoryUserStore());

      final registered = await EmailAuth.register(
        email: 'Ada@Example.com',
        password: 'secret123',
        name: 'Ada',
      );
      expect(registered['accessToken'], isNotEmpty);
      expect(registered['user']['email'], 'ada@example.com');
      expect(registered['user']['emailVerified'], isFalse);

      final ok = await EmailAuth.login(
        email: 'ada@example.com',
        password: 'secret123',
      );
      expect(ok, isNotNull);
      expect(ok!['accessToken'], isNotEmpty);

      expect(
        await EmailAuth.login(email: 'ada@example.com', password: 'wrongpass'),
        isNull,
      );
    });

    test('rejects short passwords and duplicate emails', () async {
      QudsContainer.singleton<UserStore>(MemoryUserStore());
      await EmailAuth.register(email: 'a@b.com', password: 'secret123');

      expect(
        () => EmailAuth.register(email: 'a@b.com', password: 'secret123'),
        throwsA(isA<QudsValidationException>()),
      );
      expect(
        () => EmailAuth.register(email: 'c@d.com', password: 'short'),
        throwsA(isA<QudsValidationException>()),
      );
    });

    test('verify email and reset password', () async {
      QudsContainer.singleton<TokenStore>(MemoryTokenStore());
      QudsContainer.singleton<UserStore>(MemoryUserStore());

      String? verifyToken;
      String? resetToken;
      EmailAuth.onVerificationToken = (user, token) => verifyToken = token;
      EmailAuth.onResetToken = (user, token) => resetToken = token;

      await EmailAuth.register(email: 'u@x.com', password: 'secret123');
      expect(verifyToken, isNotNull);
      expect(await EmailAuth.verifyEmail(verifyToken!), isTrue);

      final store = QudsContainer.resolve<UserStore>();
      expect((await store.findByEmail('u@x.com'))!.emailVerified, isTrue);

      await EmailAuth.forgotPassword('missing@x.com');
      expect(resetToken, isNull);
      await EmailAuth.forgotPassword('u@x.com');
      expect(resetToken, isNotNull);
      expect(
        await EmailAuth.resetPassword(token: resetToken!, password: 'newpass99'),
        isTrue,
      );
      expect(
        await EmailAuth.login(email: 'u@x.com', password: 'newpass99'),
        isNotNull,
      );
    });

    test('AuthRoutes register/login/refresh', () async {
      QudsContainer.singleton<TokenStore>(MemoryTokenStore());
      QudsContainer.singleton<UserStore>(MemoryUserStore());
      final router = QudsRouter();
      AuthRoutes.register(router);
      final client = QudsTestClient(router);

      final created = await client.post(
        '/auth/register',
        body: {'email': 'r@x.com', 'password': 'secret123'},
      );
      expect(created.statusCode, 201);

      final login = await client.post(
        '/auth/login',
        body: {'email': 'r@x.com', 'password': 'secret123'},
      );
      expect(login.statusCode, 200);
      final body = jsonDecode(login.body) as Map<String, dynamic>;
      final refresh = await client.post(
        '/auth/refresh',
        body: {'refreshToken': body['refreshToken']},
      );
      expect(refresh.statusCode, 200);
    });
  });

  group('SocialAuth', () {
    test('finds or creates a user from an injected verifier', () async {
      QudsContainer.singleton<TokenStore>(MemoryTokenStore());
      QudsContainer.singleton<UserStore>(MemoryUserStore());
      SocialAuth.verifiers['google'] = (token) async {
        expect(token, 'id-token');
        return const SocialIdentity(
          provider: 'google',
          providerId: 'g-1',
          email: 'g@x.com',
          name: 'G',
          emailVerified: true,
        );
      };

      final first = await SocialAuth.loginWithGoogle('id-token');
      expect(first['user']['email'], 'g@x.com');
      expect(first['user']['provider'], 'google');

      final again = await SocialAuth.loginWithGoogle('id-token');
      expect(again['user']['id'], first['user']['id']);
      expect(QudsContainer.resolve<UserStore>(), isA<MemoryUserStore>());
      expect((QudsContainer.resolve<UserStore>() as MemoryUserStore).length, 1);
    });

    test('default Google verifier checks tokeninfo and audience', () async {
      QudsEnv.set('GOOGLE_CLIENT_ID', 'web-client');
      SocialAuth.httpClient = MockClient((request) async {
        expect(request.url.host, 'oauth2.googleapis.com');
        return http.Response(
          jsonEncode({
            'sub': '99',
            'email': 'g@x.com',
            'email_verified': 'true',
            'aud': 'web-client',
            'name': 'G',
          }),
          200,
        );
      });

      final identity = await SocialAuth.defaultGoogleVerifier('tok');
      expect(identity.providerId, '99');
      expect(identity.emailVerified, isTrue);
    });
  });

  group('GcsStorageDisk', () {
    test('put/exists/delete with a bearer token', () async {
      final seen = <String>[];
      final disk = GcsStorageDisk(
        bucket: 'my-bucket',
        accessToken: 'ya29.test',
        publicUrlBase: 'https://cdn.example/files',
        client: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          expect(request.headers['Authorization'], 'Bearer ya29.test');
          if (request.method == 'POST') return http.Response('{}', 200);
          if (request.method == 'GET') return http.Response('{}', 200);
          if (request.method == 'DELETE') return http.Response('', 204);
          return http.Response('nope', 500);
        }),
      );

      expect(disk.url('avatars/a.png'), 'https://cdn.example/files/avatars/a.png');
      expect(await disk.put('avatars/a.png', [1, 2]), contains('avatars/a.png'));
      expect(await disk.exists('avatars/a.png'), isTrue);
      await disk.delete('avatars/a.png');
      expect(seen, containsAll(['POST /upload/storage/v1/b/my-bucket/o']));
    });

    test('configureFromEnv binds gcs', () {
      QudsEnv.set('FILESYSTEM_DISK', 'gcs');
      QudsEnv.set('GCS_BUCKET', 'b');
      Storage.configureFromEnv();
      expect(Storage.disk, isA<GcsStorageDisk>());
    });
  });

  group('custom readiness', () {
    test('includes custom probes and notifies on transition', () async {
      final fake = _ReadyConnection();
      QudsContainer.singleton<DatabaseConnection>(fake);
      ReadinessChecker.add(() async => HealthCheckResult.ok('payments'));

      final reports = <bool>[];
      HealthNotifier.onChange = (report) async => reports.add(report.ready);

      final ok = await ReadinessChecker.inspect();
      expect(ok.ready, isTrue);
      expect(ok.body['payments'], 'ok');
      expect(reports, isEmpty);

      ReadinessChecker.clear();
      ReadinessChecker.add(
        () async => HealthCheckResult.error('payments', 'timeout'),
      );
      final bad = await ReadinessChecker.inspect();
      expect(bad.ready, isFalse);
      expect(bad.body['payments'], 'error');
      expect(reports, [false]);
    });
  });

  group('Insights HTML', () {
    test('serves login HTML without a token and the dashboard with one', () async {
      QudsEnv.set('QUDS_INSIGHTS', 'true');
      QudsEnv.set('QUDS_INSIGHTS_TOKEN', 'secret');
      final router = QudsRouter();
      InsightsRoutes.register(router);
      expect(router.hasRoute(HttpMethod.get, '/quds/insights'), isTrue);

      final client = QudsTestClient(router);
      final denied = await client.get('/quds/insights');
      expect(denied.statusCode, 401);
      expect(denied.body, contains('Admin Insights'));

      final ok = await client.get('/quds/insights', query: {'token': 'secret'});
      expect(ok.statusCode, 200);
      expect(ok.body, contains('Recent exceptions'));

      final jsonDenied = await client.get('/quds/insights/exceptions');
      expect(jsonDenied.statusCode, 401);
      final jsonOk = await client.get(
        '/quds/insights/exceptions',
        query: {'token': 'secret'},
      );
      expect(jsonOk.statusCode, 200);
    });
  });
}

class _ReadyConnection implements DatabaseConnection {
  @override
  bool isOpen = true;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async =>
      [
        {'1': 1},
      ];

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async => 0;

  @override
  Future<T> transaction<T>(Future<T> Function() operation) => operation();

  @override
  Future<void> close() async {}

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
