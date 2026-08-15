import '../container/quds_container.dart';
import '../logging/quds_log.dart';
import 'job.dart';
import 'queue_driver.dart';

class QueueWorker {
  /// Optional fixed driver; when null, resolves from [QudsContainer] each poll
  /// so env-based driver swaps after boot still take effect.
  final QueueDriver? _fixedDriver;
  bool _isRunning = false;

  QueueWorker([this._fixedDriver]);

  QueueDriver get _driver =>
      _fixedDriver ?? QudsContainer.resolve<QueueDriver>();

  /// Starts the infinite background loop
  void start() async {
    _isRunning = true;
    Log.info('Quds Queue Worker started and listening for jobs...');

    while (_isRunning) {
      final job = await _driver.pop();

      if (job != null) {
        try {
          job.attempts += 1;
          await job.handle();
        } catch (e) {
          await _handleFailure(job, e);
        }
      } else {
        // If the queue is empty, wait briefly before polling again
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _handleFailure(Job job, Object error) async {
    if (job.attempts < job.maxRetries) {
      final backoffSeconds = 1 << (job.attempts - 1); // 1, 2, 4, ...
      job.availableAt =
          DateTime.now().add(Duration(seconds: backoffSeconds));
      Log.warning(
        'Job ${job.runtimeType} failed (attempt ${job.attempts}/${job.maxRetries}): $error — retry in ${backoffSeconds}s',
      );
      await _driver.push(job);
    } else {
      Log.error(
        '[JOB FAILED] ${job.runtimeType} after ${job.attempts} attempts: $error',
      );
    }
  }

  /// Gracefully shuts down the worker
  void stop() {
    _isRunning = false;
  }
}
