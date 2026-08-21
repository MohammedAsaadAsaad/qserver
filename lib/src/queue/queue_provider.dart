import '../container/service_provider.dart';
import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'queue_driver.dart';
import 'queue_worker.dart';

class QueueServiceProvider extends ServiceProvider {
  QueueWorker? _worker;

  @override
  void register() {
    // Default memory driver. `QUEUE_DRIVER=database` is applied after boot
    // via `_configureDriversFromEnv` once DatabaseConnection exists.
    if (!QudsContainer.isRegistered<QueueDriver>()) {
      QudsContainer.singleton<QueueDriver>(MemoryQueueDriver());
    }
    final driver = (env<String>('QUEUE_DRIVER', 'memory') ?? 'memory')
        .toLowerCase();
    if (driver == 'memory') {
      Log.debug('Driver memory', component: 'queue');
    }
  }

  @override
  void boot() {
    // Resolve dynamically so env-based driver swaps after boot are picked up.
    final worker = QueueWorker();
    _worker = worker;
    QudsContainer.singleton<QueueWorker>(worker);

    // We do NOT 'await' this. It must run asynchronously in the background
    // alongside the HTTP server.
    worker.start();
  }

  @override
  Future<void> shutdown() async {
    await _worker?.stop();
  }
}
