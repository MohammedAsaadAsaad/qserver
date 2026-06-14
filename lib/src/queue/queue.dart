import '../container/quds_container.dart';
import 'queue_driver.dart';
import 'job.dart';

/// A global facade for dispatching background jobs
class Queue {
  /// Pushes a job to the active queue driver
  static Future<void> push(Job job) async {
    final driver = QudsContainer.resolve<QueueDriver>();
    await driver.push(job);
  }
}
