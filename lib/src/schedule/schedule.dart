import '../queue/job.dart';
import '../queue/queue.dart';
import 'cron.dart';

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

  /// Registers [job] using a 5-field cron expression. Additive; [every] is
  /// unchanged. The first run is the next matching minute.
  static Future<void> cron(String expression, Job job) async {
    final parsed = CronExpression.parse(expression);
    final delay = parsed.delayUntilNext();
    _entries.add(_ScheduledEntry(delay, job));
    await Queue.later(_CronJob(inner: job, expression: parsed.source), delay);
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

class _CronJob extends Job {
  final Job inner;
  final String expression;

  _CronJob({required this.inner, required this.expression});

  @override
  int get maxRetries => inner.maxRetries;

  @override
  Future<void> handle() async {
    await inner.handle();
    final delay = CronExpression.parse(expression).delayUntilNext();
    await Queue.later(
      _CronJob(inner: inner, expression: expression),
      delay,
    );
  }
}
