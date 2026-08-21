import 'dart:collection';

import '../container/quds_container.dart';
import 'job.dart';
import 'queue_driver.dart';

class RunningJob {
  final String key;
  final String label;
  final Stopwatch stopwatch = Stopwatch()..start();

  RunningJob({required this.key, required this.label});

  Duration get elapsed => stopwatch.elapsed;
}

/// Process-local view of the worker: running jobs plus last-known driver counts.
class QueueRuntime {
  static final List<RunningJob> _running = [];
  static int retries = 0;

  static List<RunningJob> get running => List<RunningJob>.unmodifiable(_running);

  static RunningJob begin(Job job) {
    final item = RunningJob(
      key: job.id ?? identityHashCode(job).toString(),
      label: job.attempts > 1
          ? '${job.label} · attempt ${job.attempts}/${job.maxRetries}'
          : job.label,
    );
    _running.add(item);
    return item;
  }

  static void end(RunningJob item) {
    _running.remove(item);
  }

  static QueueSnapshot snapshot() {
    QueueSnapshot? fromDriver;
    try {
      if (QudsContainer.isRegistered<QueueDriver>()) {
        final driver = QudsContainer.resolve<QueueDriver>();
        if (driver is QueueInspect) {
          fromDriver = (driver as QueueInspect).inspect();
        }
      }
    } catch (_) {}

    return QueueSnapshot(
      waiting: fromDriver?.waiting ?? 0,
      delayed: fromDriver?.delayed ?? 0,
      reserved: fromDriver?.reserved ?? 0,
      failed: FailedJobLog.total,
      running: _running.length,
      retries: retries,
    );
  }

  static void reset() {
    _running.clear();
    retries = 0;
  }
}

class FailedJobRecord {
  final String id;
  final DateTime time;
  final String label;
  final String jobType;
  final int attempts;
  final String error;

  FailedJobRecord({
    required this.id,
    required this.time,
    required this.label,
    required this.jobType,
    required this.attempts,
    required this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time.toUtc().toIso8601String(),
      'label': label,
      'jobType': jobType,
      'attempts': attempts,
      'error': error,
    };
  }
}

/// In-memory dead-letter list (all drivers). Database rows stay in `quds_failed_jobs`.
class FailedJobLog {
  static final Queue<FailedJobRecord> _records = Queue<FailedJobRecord>();
  static int _total = 0;
  static int maxInMemory = 50;

  static int get total => _total;

  static List<FailedJobRecord> get recent =>
      List<FailedJobRecord>.unmodifiable(_records);

  static void add(FailedJobRecord record) {
    _total++;
    _records.addLast(record);
    while (_records.length > maxInMemory) {
      _records.removeFirst();
    }
  }

  static void addFromJob(Job job, Object error) {
    add(
      FailedJobRecord(
        id: job.id ?? 'job_${DateTime.now().microsecondsSinceEpoch}',
        time: DateTime.now(),
        label: job.label,
        jobType: job.runtimeType.toString(),
        attempts: job.attempts,
        error: error.toString(),
      ),
    );
  }

  static void clear() {
    _records.clear();
    _total = 0;
  }
}
