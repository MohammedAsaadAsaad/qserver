import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

void main() {
  group('Route Matching and compilation Tests', () {
    test('Static path matching', () {
      final route = Route(HttpMethod.get, '/tasks', (req) async => QudsResponse.json({}));
      expect(route.matches(HttpMethod.get, '/tasks'), isTrue);
      expect(route.matches(HttpMethod.post, '/tasks'), isFalse);
      expect(route.matches(HttpMethod.get, '/task'), isFalse);
    });

    test('Dynamic path parameter matching', () {
      final route = Route(HttpMethod.get, '/tasks/{id}/comments/{commentId}', (req) async => QudsResponse.json({}));
      expect(route.matches(HttpMethod.get, '/tasks/12/comments/45'), isTrue);
      expect(route.matches(HttpMethod.get, '/tasks/12/comments'), isFalse);
    });

    test('Extract parameter values', () {
      final route = Route(HttpMethod.get, '/tasks/{id}/comments/{commentId}', (req) async => QudsResponse.json({}));
      final params = route.extractParams('/tasks/12/comments/45');
      expect(params, isNotEmpty);
      expect(params['id'], '12');
      expect(params['commentId'], '45');
    });
  });

  group('QudsRouter Registration and Grouping Tests', () {
    late QudsRouter router;

    setUp(() {
      router = QudsRouter();
    });

    test('Register HTTP method routes', () {
      router.get('/tasks', (req) async => QudsResponse.json({}));
      router.post('/tasks', (req) async => QudsResponse.json({}));

      expect(router.hasRoute(HttpMethod.get, '/tasks'), isTrue);
      expect(router.hasRoute(HttpMethod.post, '/tasks'), isTrue);
      expect(router.hasRoute(HttpMethod.put, '/tasks'), isFalse);
    });

    test('Group routes with common prefix', () {
      router.group(
        prefix: '/api/v1',
        callback: (r) {
          r.get('/users', (req) async => QudsResponse.json({}));
          r.post('/users', (req) async => QudsResponse.json({}));
        },
      );

      expect(router.hasRoute(HttpMethod.get, '/api/v1/users'), isTrue);
      expect(router.hasRoute(HttpMethod.post, '/api/v1/users'), isTrue);
      expect(router.hasRoute(HttpMethod.get, '/users'), isFalse);
    });

    test('Nested route groups prefixes', () {
      router.group(
        prefix: '/api',
        callback: (r) {
          r.group(
            prefix: '/v1',
            callback: (nr) {
              nr.get('/tasks', (req) async => QudsResponse.json({}));
            },
          );
        },
      );

      expect(router.hasRoute(HttpMethod.get, '/api/v1/tasks'), isTrue);
      expect(router.hasRoute(HttpMethod.get, '/tasks'), isFalse);
    });
  });
}
