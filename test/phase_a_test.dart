import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    QudsContainer.clear();
    Auth.clearRevocations();
    ExceptionLog.clear();
    ExceptionLog.logToFile = false;
  });

  group('Phase A security', () {
    test('issueTokens and refresh rotate tokens', () async {
      final store = MemoryTokenStore();
      QudsContainer.singleton<TokenStore>(store);
      final issued = await Auth.issueTokens({'id': 1, 'sub': 'u1'});
      expect(issued['accessToken'], isNotEmpty);
      expect(issued['refreshToken'], isNotEmpty);

      final oldRefresh = issued['refreshToken'] as String;
      final rotated = await Auth.refresh(oldRefresh);
      expect(rotated, isNotNull);
      expect(rotated!['accessToken'], isNotEmpty);

      await Auth.revokeRefresh(oldRefresh);
      final again = await Auth.refresh(oldRefresh);
      expect(again, isNull);
    });

    test('UniqueRule async validator', () async {
      final errors = await ValidationEngine.validateAsync(
        {'email': 'a@b.com'},
        {
          'email': UniqueRule((field, value, data) async => value == 'a@b.com'),
        },
      );
      expect(errors['email'], isNotNull);
    });

    test('Insights routes stay off by default', () {
      final router = QudsRouter();
      InsightsRoutes.register(router);
      expect(
        router.hasRoute(HttpMethod.get, '/quds/insights/exceptions'),
        isFalse,
      );
    });

    test('Insights list requires token when enabled', () async {
      // Simulate env by registering routes manually with middleware
      final router = QudsRouter();
      router.get(
        '/quds/insights/exceptions',
        (request) async {
          return QudsResponse.json({
            'total': ExceptionLog.total,
            'data': ExceptionLog.recent.map((e) => e.toJson()).toList(),
          });
        },
        middleware: [InsightsAuthMiddleware()],
      );

      final client = QudsTestClient(router);
      final denied = await client.get('/quds/insights/exceptions');
      expect(denied.statusCode, 401);

      ExceptionLog.add(
        QudsExceptionRecord.capture(Exception('boom'), StackTrace.current),
      );

      // Without QUDS_INSIGHTS_TOKEN in env, gate fails closed even with header
      final stillDenied = await client.get(
        '/quds/insights/exceptions',
        headers: {'authorization': 'Bearer secret'},
      );
      expect(stillDenied.statusCode, 401);
    });

    test('SecurityHeadersMiddleware sets headers', () async {
      final router = QudsRouter();
      router.use(SecurityHeadersMiddleware());
      router.get('/x', (r) async => QudsResponse.json({'ok': true}));
      final res = await QudsTestClient(router).get('/x');
      expect(res.headers['X-Content-Type-Options'], 'nosniff');
      expect(res.headers['X-Frame-Options'], 'DENY');
    });
  });
}
