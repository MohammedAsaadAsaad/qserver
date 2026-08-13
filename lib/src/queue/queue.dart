import '../container/quds_container.dart';
import 'queue_driver.dart';
import 'job.dart';

/// A global facade for dispatching background jobs
class Queue {
  /// Pushes a job to the active queue driver for immediate execution
  static Future<void> push(Job job) async {
    final driver = QudsContainer.resolve<QueueDriver>();
    await driver.push(job);
  }

  /// Schedules [job] to run after [delay]
  static Future<void> later(Job job, Duration delay) async {
    job.availableAt = DateTime.now().add(delay);
    await push(job);
  }

  /// Schedules [job] to run at an absolute [time]
  static Future<void> at(Job job, DateTime time) async {
    job.availableAt = time;
    await push(job);
  }
}
