import 'package:qserver/qserver.dart';
import 'package:test/test.dart';

class _ProbeJob extends Job {
  int runs = 0;

  @override
  Future<void> handle() async {
    runs++;
  }
}

void main() {
  tearDown(() {
    QudsContainer.clear();
    Auth.clearRevocations();
    JobRegistry.clear();
    Schedule.clear();
    Storage.use(LocalStorageDisk());
    RedisBroadcastBridge.reset();
    InsightsRoutes.authorizer = null;
  });

  group('defaults (0.0.9 BC)', () {
    test('Cache uses MemoryCacheDriver by default', () {
      final app = QudsServerApp();
      expect(app, isNotNull);
      expect(QudsContainer.resolve<CacheDriver>(), isA<MemoryCacheDriver>());
    });

    test('Insights routes are off by default', () {
      final router = QudsRouter();
      InsightsRoutes.register(router);
      expect(router.hasRoute(HttpMethod.get, '/quds/insights/exceptions'), isFalse);
      expect(
        router.hasRoute(HttpMethod.get, '/quds/insights/health-summary'),
        isFalse,
      );
    });

    test('Storage defaults to local disk', () {
      expect(Storage.disk, isA<LocalStorageDisk>());
    });
  });

  group('Queue.cancel', () {
    test('cancels pending memory jobs by id', () async {
      QudsContainer.singleton<QueueDriver>(MemoryQueueDriver());
      final job = _ProbeJob()..id = 'job-1';
      await Queue.push(job);
      expect(await Queue.cancel('job-1'), isTrue);
      expect(await Queue.cancel('missing'), isFalse);
      expect(await QudsContainer.resolve<QueueDriver>().pop(), isNull);
    });
  });

  group('Schedule', () {
    test('every registers and enqueues a recurring wrapper', () async {
      QudsContainer.singleton<QueueDriver>(MemoryQueueDriver());
      final job = _ProbeJob();
      await Schedule.every(const Duration(milliseconds: 1), job);
      expect(Schedule.count, 1);

      await Future.delayed(const Duration(milliseconds: 5));
      final pending = await QudsContainer.resolve<QueueDriver>().pop();
      expect(pending, isNotNull);
      await pending!.handle();
      expect(job.runs, 1);
    });
  });

  group('Local storage', () {
    test('put/exists/delete round-trip', () async {
      Storage.use(LocalStorageDisk(rootPath: 'storage/test_tmp'));
      const path = 'phase_c_probe.txt';
      await Storage.put(path, [1, 2, 3]);
      expect(await Storage.exists(path), isTrue);
      await Storage.delete(path);
      expect(await Storage.exists(path), isFalse);
    });
  });
}
