import '../queue/job.dart';
import '../queue/queue.dart';

/// Interval-based job scheduling (opt-in; not started automatically).
///
/// Recurrence is implemented by re-queuing a wrapper job after each [handle].
class Schedule {
  static final List<_ScheduledEntry> _entries = [];

  /// Registers [job] to run every [interval] via the active [Queue] driver.
  ///
  /// The first run is scheduled after [interval] (not immediately).
  static Future<void> every(Duration interval, Job job) async {
    final wrapper = _RecurringJob(inner: job, interval: interval);
    _entries.add(_ScheduledEntry(interval, job));
    await Queue.later(wrapper, interval);
  }

  /// Number of schedules registered in this process (tests / diagnostics).
  static int get count => _entries.length;

  /// Clears in-process schedule bookkeeping (does not drain the queue).
  static void clear() => _entries.clear();
}

class _ScheduledEntry {
  final Duration interval;
  final Job job;
  _ScheduledEntry(this.interval, this.job);
}

class _RecurringJob extends Job {
  final Job inner;
  final Duration interval;

  _RecurringJob({required this.inner, required this.interval});

  @override
  int get maxRetries => inner.maxRetries;

  @override
  Future<void> handle() async {
    await inner.handle();
    // Re-queue for the next interval after a successful run.
    await Queue.later(
      _RecurringJob(inner: inner, interval: interval),
      interval,
    );
  }
}
