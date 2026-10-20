import 'dart:convert';
import 'dart:io';

import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

class _TokenFake implements DatabaseConnection {
  final List<Map<String, dynamic>> rows = [];
  bool created = false;

  @override
  bool isOpen = true;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final params = parameters ?? const [];
    final n = sql.replaceAll(RegExp(r'\s+'), ' ');
    if (n.contains('WHERE token_hash =')) {
      return rows.where((r) => r['token_hash'] == params[0]).toList();
    }
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    final params = parameters ?? const [];
    final n = sql.replaceAll(RegExp(r'\s+'), ' ');
    if (n.contains('CREATE TABLE')) {
      created = true;
      return 0;
    }
    if (n.contains('INSERT INTO quds_refresh_tokens')) {
      rows.add({
        'token_hash': params[0],
        'token_id': params[1],
        'payload': params[2],
        'expires_at': params[3],
      });
      return 1;
    }
    if (n.contains('DELETE FROM quds_refresh_tokens WHERE token_hash')) {
      rows.removeWhere((r) => r['token_hash'] == params[0]);
      return 1;
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

class _FlagJob extends Job {
  bool ran = false;

  @override
  Future<void> handle() async {
    ran = true;
  }
}

void main() {
  tearDown(() {
    QudsContainer.clear();
    Auth.clearRevocations();
    Mailer.reset();
    Gate.clear();
    Schedule.clear();
    Storage.use(LocalStorageDisk());
    QudsEnv.set('QUDS_OPENAPI', null);
    QudsEnv.set('QUDS_SIGNED_FILES', null);
    QudsEnv.set('QUDS_METRICS', null);
    QudsEnv.set('MAIL_HOST', null);
    QudsEnv.set('AUTH_TOKEN_STORE', null);
    QudsEnv.set('MAX_RSS_BYTES', null);
    QudsEnv.set('SSL_CERT', null);
    QudsEnv.set('SSL_KEY', null);
  });

  group('compatibility defaults', () {
    test('json map shape is still the raw object', () {
      final res = QudsResponse.json({'hello': 'world'});
      expect(jsonDecode(res.body), {'hello': 'world'});
      expect(res.body.contains('"success"'), isFalse);
    });

    test('openapi and signed files stay off', () {
      final router = QudsRouter();
      OpenApiRoutes.register(router);
      SignedFileRoutes.register(router);
      expect(router.hasRoute(HttpMethod.get, '/quds/openapi.json'), isFalse);
      expect(router.hasRoute(HttpMethod.get, '/quds/files'), isFalse);
    });

    test('smtp hook is not bound without MAIL_HOST', () {
      expect(Mailer.send, isNull);
      SmtpMailer.configureFromEnv();
      expect(Mailer.send, isNull);
    });

    test('smtp hook does not replace an existing Mailer.send', () {
      Mailer.send = (message) async {};
      QudsEnv.set('MAIL_HOST', 'smtp.example.com');
      SmtpMailer.configureFromEnv();
      expect(Mailer.send, isNotNull);
      // still the app-assigned closure, not SmtpMailer.send
      expect(identical(Mailer.send, SmtpMailer.send), isFalse);
    });
  });

  group('pagination and envelope', () {
    test('paginator reads query with a floor and cap', () {
      final request = QudsRequest.synthetic(
        method: 'GET',
        path: '/items',
        queryParameters: {'page': '2', 'per_page': '50'},
      );
      final pager = Paginator.fromRequest(request, total: 95);
      expect(pager.page, 2);
      expect(pager.perPage, 50);
      expect(pager.offset, 50);
      expect(pager.lastPage, 2);
    });

    test('paginated envelope wraps data without changing json()', () {
      final res = QudsResponse.paginated(
        ['a', 'b'],
        total: 20,
        page: 1,
        perPage: 10,
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect(body['data'], ['a', 'b']);
      expect(body['meta']['total'], 20);
      expect(body['meta']['lastPage'], 2);
    });
  });

  group('router helpers', () {
    test('patch and resource register only the given actions', () async {
      final router = QudsRouter();
      router.resource('/tasks', {
        'index': (r) async => QudsResponse.json({'ok': 'index'}),
        'update': (r) async => QudsResponse.json({'id': r.param('id')}),
      });
      expect(router.hasRoute(HttpMethod.get, '/tasks'), isTrue);
      expect(router.hasRoute(HttpMethod.post, '/tasks'), isFalse);
      expect(router.hasRoute(HttpMethod.patch, '/tasks/{id}'), isTrue);
      expect(router.hasRoute(HttpMethod.put, '/tasks/{id}'), isTrue);

      final client = QudsTestClient(router);
      final patched = await client.patch('/tasks/9', body: {});
      expect(jsonDecode(patched.body)['id'], '9');
    });

    test('wildcard static files refuse traversal and serve text', () async {
      final dir = Directory.systemTemp.createTempSync('qserver_static_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      File('${dir.path}/hello.txt').writeAsStringSync('hi');

      final router = QudsRouter();
      router.staticFiles('/assets', dir.path);
      final client = QudsTestClient(router);
      final ok = await client.get('/assets/hello.txt');
      expect(ok.statusCode, 200);
      expect(utf8.decode(ok.rawBody!), 'hi');

      final denied = await client.get('/assets/../hello.txt');
      expect(denied.statusCode, 403);
    });
  });

  group('gzip idempotency sse cookies', () {
    test('gzip applies only when Accept-Encoding includes gzip', () async {
      final router = QudsRouter();
      router.get(
        '/big',
        (r) async => QudsResponse.json({'body': 'x' * 400}),
        middleware: [CompressionMiddleware(minBytes: 32)],
      );
      final client = QudsTestClient(router);
      final plain = await client.get('/big');
      expect(plain.headers['Content-Encoding'], isNull);
      expect(plain.body.contains('body'), isTrue);

      final zipped = await client.get(
        '/big',
        headers: {'accept-encoding': 'gzip'},
      );
      expect(zipped.headers['Content-Encoding'], 'gzip');
      expect(utf8.decode(gzip.decode(zipped.rawBody!)), contains('body'));
    });

    test('idempotency replays POST when the key is present', () async {
      var hits = 0;
      final router = QudsRouter();
      router.use(IdempotencyMiddleware());
      router.post('/pay', (r) async {
        hits++;
        return QudsResponse.json({'n': hits});
      });
      final client = QudsTestClient(router);
      final first = await client.post(
        '/pay',
        body: {},
        headers: {'Idempotency-Key': 'abc'},
      );
      final second = await client.post(
        '/pay',
        body: {},
        headers: {'Idempotency-Key': 'abc'},
      );
      expect(hits, 1);
      expect(first.body, second.body);

      await client.post('/pay', body: {});
      expect(hits, 2);
    });

    test('sse factory encodes events', () {
      final event = SseEvent(data: 'hello\nworld', event: 'ping', id: '1');
      expect(event.encode(), contains('event: ping'));
      expect(event.encode(), contains('data: hello'));
      expect(event.encode(), contains('data: world'));
      final res = QudsResponse.sse(Stream.value(event));
      expect(res.headers['Content-Type'], contains('text/event-stream'));
      expect(res.eventStream, isNotNull);
    });

    test('cookie session plus csrf rejects a bare POST', () async {
      final router = QudsRouter();
      router.use(CookieSessionMiddleware());
      router.use(CsrfMiddleware());
      router.get('/form', (r) async => QudsResponse.json({'ok': true}));
      router.post('/form', (r) async => QudsResponse.json({'saved': true}));
      final client = QudsTestClient(router);

      final get = await client.get('/form');
      expect(get.statusCode, 200);
      expect(get.headers['X-CSRF-TOKEN'], isNotEmpty);
      final setCookie = get.headers['Set-Cookie']!;
      final cookie = setCookie.split(';').first;

      final denied = await client.post('/form', body: {});
      expect(denied.statusCode, 403);

      final token = get.headers['X-CSRF-TOKEN']!;
      final ok = await client.post(
        '/form',
        body: {'_token': token},
        headers: {'cookie': cookie, 'x-csrf-token': token},
      );
      expect(ok.statusCode, 200);
      expect(jsonDecode(ok.body)['saved'], isTrue);
    });
  });

  group('auth extras', () {
    test('role middleware allows matching JWT role', () async {
      final token = Auth.login({'id': 1, 'role': 'admin'});
      final router = QudsRouter();
      router.get(
        '/admin',
        (r) async => QudsResponse.json({'ok': true}),
        middleware: [
          RoleMiddleware(['admin'])
        ],
      );
      final client = QudsTestClient(router);
      final denied = await client.get('/admin');
      expect(denied.statusCode, 403);
      final allowed = await client.get(
        '/admin',
        headers: {'authorization': 'Bearer $token'},
      );
      expect(allowed.statusCode, 200);
    });

    test('gate authorize throws when ability is missing', () {
      expect(
        () => Gate.authorize('edit', {'id': 1}),
        throwsA(isA<QudsAuthorizationException>()),
      );
      Gate.define('edit', (user, arg) => user is Map && user['id'] == 1);
      expect(Gate.allows('edit', {'id': 1}), isTrue);
    });

    test('database token store round-trip', () async {
      final fake = _TokenFake();
      final store = DatabaseTokenStore(fake);
      await store.saveRefreshToken(
        tokenId: 't1',
        tokenHash: 'hash',
        payload: {'sub': 'u1'},
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final found = await store.findRefreshToken('hash');
      expect(found, isNotNull);
      expect(found!['payload']['sub'], 'u1');
      await store.revokeAllForSubject('u1');
      expect(await store.findRefreshToken('hash'), isNull);
    });
  });

  group('uploads storage cron openapi rss', () {
    test('upload rules reject oversized files', () {
      final file = UploadedFile(
        filename: 'a.exe',
        mimeType: 'application/octet-stream',
        bytes: List<int>.filled(10, 1),
      );
      expect(
        () => file.assertAllowed(maxBytes: 4, extensions: ['png']),
        throwsA(isA<QudsUploadException>()),
      );
      file.assertAllowed(maxBytes: 20, mimeTypes: ['application/octet-stream']);
    });

    test('local temporary urls verify and expire', () {
      final url =
          Storage.temporaryUrl('photos/a.png', ttl: const Duration(minutes: 5));
      expect(url, contains('/quds/files?'));
      final uri = Uri.parse(url);
      expect(
        SignedUrl.valid(
          path: uri.queryParameters['path']!,
          expires: uri.queryParameters['expires']!,
          sig: uri.queryParameters['sig']!,
        ),
        isTrue,
      );
      expect(
        SignedUrl.valid(
          path: 'photos/a.png',
          expires: '1',
          sig: uri.queryParameters['sig']!,
        ),
        isFalse,
      );
    });

    test('s3 presign includes signature query keys', () {
      final disk = S3StorageDisk(
        bucket: 'b',
        region: 'us-east-1',
        accessKey: 'AKIA',
        secretKey: 'secret',
      );
      final url = disk.presignGet('x.bin', ttl: const Duration(minutes: 2));
      expect(url, contains('X-Amz-Signature='));
      expect(url, contains('X-Amz-Credential='));
    });

    test('cron parses and matches a weekday midnight', () {
      final cron = CronExpression.parse('0 0 * * 1');
      final monday = DateTime(2026, 10, 19, 0, 0); // Monday
      expect(cron.matches(monday), isTrue);
      expect(cron.matches(DateTime(2026, 10, 20, 0, 0)), isFalse);
      final next = cron.nextAfter(DateTime(2026, 10, 19, 0, 1));
      expect(next.weekday, DateTime.monday);
      expect(next.hour, 0);
      expect(next.minute, 0);
    });

    test('schedule.cron is additive bookkeeping', () async {
      QudsContainer.singleton<QueueDriver>(MemoryQueueDriver());
      await Schedule.cron('0 2 * * *', _FlagJob());
      expect(Schedule.count, 1);
    });

    test('openapi lists registered routes when enabled', () async {
      QudsEnv.set('QUDS_OPENAPI', 'true');
      final router = QudsRouter();
      router.get('/hello', (r) async => QudsResponse.json({'ok': true}));
      OpenApiRoutes.register(router);
      final client = QudsTestClient(router);
      final res = await client.get('/quds/openapi.json');
      expect(res.statusCode, 200);
      final spec = jsonDecode(res.body) as Map<String, dynamic>;
      expect(spec['openapi'], '3.0.3');
      expect(spec['paths']['/hello']['get'], isNotNull);
    });

    test('rss cap returns 503 only when configured', () async {
      final runtime = ServerRuntime(maxRssBytes: 1);
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      runtime.server = server;
      final request = await _oneShot(server, runtime, QudsRouter());
      expect(request, 503);

      final unlimited = ServerRuntime();
      final server2 = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server2.close(force: true));
      unlimited.server = server2;
      final ok = await _oneShot(server2, unlimited, QudsRouter());
      expect(ok, 404);
    });
  });
}

Future<int> _oneShot(
  HttpServer server,
  ServerRuntime runtime,
  QudsRouter router,
) async {
  late int status;
  final done = server.first.then((raw) async {
    await runtime.handle(raw, router);
  });
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/missing'),
    );
    final res = await req.close();
    status = res.statusCode;
    await res.drain<void>();
  } finally {
    client.close(force: true);
  }
  await done;
  return status;
}
