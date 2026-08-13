import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    QudsContainer.clear();
    Auth.clearRevocations();
  });

  group('QudsTestClient', () {
    test('GET returns JSON from a registered route', () async {
      final router = QudsRouter();
      router.get('/hello', (request) async {
        return QudsResponse.json({'message': 'hi'});
      });

      final client = QudsTestClient(router);
      final response = await client.get('/hello');

      expect(response.statusCode, 200);
      expect(response.body.contains('hi'), isTrue);
    });

    test('POST body reaches the handler', () async {
      final router = QudsRouter();
      router.post('/echo', (request) async {
        return QudsResponse.json({'title': request.input('title')});
      });

      final client = QudsTestClient(router);
      final response = await client.post('/echo', body: {'title': 'Task'});

      expect(response.statusCode, 200);
      expect(response.body.contains('Task'), isTrue);
    });

    test('missing route returns 404', () async {
      final client = QudsTestClient(QudsRouter());
      final response = await client.get('/missing');
      expect(response.statusCode, 404);
    });
  });

  group('Cache', () {
    test('put and get with TTL', () async {
      await Cache.put('k', 'v', ttl: const Duration(seconds: 5));
      expect(await Cache.get<String>('k'), 'v');
      await Cache.forget('k');
      expect(await Cache.get<String>('k'), isNull);
    });
  });

  group('Auth revoke', () {
    test('invalidate rejects verify', () {
      final token = Auth.login({'id': 1});
      expect(Auth.verify(token), isNotNull);
      Auth.invalidate(token);
      expect(Auth.verify(token), isNull);
    });
  });
}
