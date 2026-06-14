import '../container/service_provider.dart';
import '../container/quds_container.dart';
import 'queue_driver.dart';
import 'queue_worker.dart';

class QueueServiceProvider extends ServiceProvider {
  @override
  void register() {
    // Bind the memory driver as a singleton.
    // Later, you can check env('QUEUE_CONNECTION') to swap this to Redis.
    QudsContainer.singleton<QueueDriver>(MemoryQueueDriver());
  }

  @override
  void boot() {
    final driver = QudsContainer.resolve<QueueDriver>();

    // Instantiate and start the background worker
    final worker = QueueWorker(driver);

    // We do NOT 'await' this. It must run asynchronously in the background
    // alongside the HTTP server.
    worker.start();
  }
}
