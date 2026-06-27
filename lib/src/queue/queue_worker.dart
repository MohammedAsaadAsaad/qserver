import 'queue_driver.dart';

class QueueWorker {
  final QueueDriver _driver;
  bool _isRunning = false;

  QueueWorker(this._driver);

  /// Starts the infinite background loop
  void start() async {
    _isRunning = true;
    print('👷 Quds Queue Worker started and listening for jobs...');

    while (_isRunning) {
      final job = await _driver.pop();

      if (job != null) {
        try {
          // Execute the job's logic
          await job.handle();
        } catch (e) {
          // In a real production system, you'd implement the retry logic here
          // and move it to a "Failed Jobs" database table if it exceeds maxRetries.
          print('\x1B[31m[JOB FAILED] ${job.runtimeType}: $e\x1B[0m');
        }
      } else {
        // If the queue is empty, wait 1 second before polling again to prevent CPU spiking
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Gracefully shuts down the worker
  void stop() {
    _isRunning = false;
  }
}
