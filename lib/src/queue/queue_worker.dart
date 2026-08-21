import 'dart:async';

import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../http/middleware/server_monitor.dart';
import '../logging/log_spinner.dart';
import '../logging/quds_log.dart';
import 'job.dart';
import 'queue_driver.dart';
import 'queue_runtime.dart';

class QueueWorker {
  /// Optional fixed driver; when null, resolves from [QudsContainer] each poll
  /// so env-based driver swaps after boot still take effect.
  final QueueDriver? _fixedDriver;

  /// How many jobs to run at once. Default `1` (same as before).
  /// Override with [QUEUE_CONCURRENCY] or the constructor.
  final int concurrency;

  bool _isRunning = false;
  int _activeLoops = 0;
  Completer<void>? _stopped;

  QueueWorker([this._fixedDriver, int? concurrency])
      : concurrency = _clampConcurrency(
          concurrency ?? env<int>('QUEUE_CONCURRENCY') ?? 1,
        );

  static int _clampConcurrency(int value) => value.clamp(1, 32);

  QueueDriver get _driver =>
      _fixedDriver ?? QudsContainer.resolve<QueueDriver>();

  bool get isRunning => _isRunning;

  /// Starts the infinite background loop
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _stopped = Completer<void>();
    _activeLoops = concurrency;
    if (concurrency == 1) {
      Log.info('Worker listening', component: 'queue');
    } else {
      Log.info('Workers listening ×$concurrency', component: 'queue');
    }

    for (var i = 0; i < concurrency; i++) {
      unawaited(_loop());
    }
  }

  Future<void> _loop() async {
    try {
      while (_isRunning) {
        final job = await _driver.pop();

        if (job != null) {
          job.attempts += 1;
          final run = QueueRuntime.begin(job);
          ServerMonitor.refresh();
          final useSpinner = concurrency == 1;
          final spinner = useSpinner
              ? LogSpinner.start(
                  job.attempts > 1
                      ? '${job.label} · attempt ${job.attempts}/${job.maxRetries}'
                      : job.label,
                  component: 'queue',
                )
              : null;
          try {
            await job.handle();
            await _ack(job);
            if (spinner != null) {
              spinner.succeed();
            } else {
              Log.info(
                '✓ ${job.label}',
                component: 'queue',
                elapsed: run.elapsed,
              );
            }
          } catch (e) {
            await _handleFailure(job, e, spinner: spinner, elapsed: run.elapsed);
          } finally {
            QueueRuntime.end(run);
            ServerMonitor.refresh();
          }
        } else {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    } finally {
      _activeLoops--;
      if (_activeLoops <= 0) {
        final done = _stopped;
        if (done != null && !done.isCompleted) {
          done.complete();
        }
      }
    }
  }

  Future<void> _handleFailure(
    Job job,
    Object error, {
    LogSpinner? spinner,
    Duration? elapsed,
  }) async {
    if (job.attempts < job.maxRetries) {
      final backoffSeconds = 1 << (job.attempts - 1); // 1, 2, 4, ...
      job.availableAt =
          DateTime.now().add(Duration(seconds: backoffSeconds));
      QueueRuntime.retries++;
      final detail = 'retry in ${backoffSeconds}s '
          '(${job.attempts}/${job.maxRetries}): $error';
      if (spinner != null) {
        spinner.fail(error, detail: detail);
      } else {
        Log.warning(
          '${job.label} — $detail',
          component: 'queue',
          elapsed: elapsed,
        );
      }
      await _release(job, retry: true, error: error);
    } else {
      FailedJobLog.addFromJob(job, error);
      final detail = 'failed after ${job.attempts} attempts: $error';
      if (spinner != null) {
        spinner.fail(error, detail: detail);
      } else {
        Log.error(
          '${job.label} — $detail',
          component: 'queue',
          elapsed: elapsed,
        );
      }
      await _release(job, retry: false, error: error);
    }
  }

  Future<void> _ack(Job job) async {
    final driver = _driver;
    if (driver is QueueAcknowledgement) {
      await (driver as QueueAcknowledgement).ack(job);
    }
  }

  Future<void> _release(
    Job job, {
    required bool retry,
    Object? error,
  }) async {
    final driver = _driver;
    if (driver is QueueAcknowledgement) {
      await (driver as QueueAcknowledgement).release(
        job,
        retry: retry,
        error: error,
      );
      return;
    }
    if (retry) await driver.push(job);
  }

  /// Stops the poll loop and waits for the current iteration to finish.
  Future<void> stop({Duration timeout = const Duration(seconds: 10)}) async {
    _isRunning = false;
    final done = _stopped;
    if (done == null) return;
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      Log.warning('Worker stop timed out', component: 'queue');
    }
  }
}
