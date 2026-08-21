import 'dart:collection';
import 'job.dart';

/// Point-in-time queue counts. Optional — see [QueueInspect].
class QueueSnapshot {
  final int waiting;
  final int delayed;
  final int reserved;
  final int failed;
  final int running;
  final int retries;

  const QueueSnapshot({
    this.waiting = 0,
    this.delayed = 0,
    this.reserved = 0,
    this.failed = 0,
    this.running = 0,
    this.retries = 0,
  });

  int get pending => waiting + delayed;
}

/// Optional inspect hook. Not on [QueueDriver], so existing drivers keep compiling.
abstract class QueueInspect {
  QueueSnapshot inspect();
}

/// The contract all queue systems (Memory, Redis, RabbitMQ) must follow
abstract class QueueDriver {
  /// Pushes a new job onto the queue
  Future<void> push(Job job);

  /// Retrieves the next ready job from the queue (FIFO among ready jobs)
  Future<Job?> pop();

  /// Cancels a pending job by [id]. Returns `false` when unsupported or missing.
  Future<bool> cancel(String id) async => false;
}

/// Optional persistence hooks. Implemented by [DatabaseQueueDriver].
///
/// Not part of [QueueDriver] so existing `implements QueueDriver` classes
/// keep compiling. The worker detects this type and falls back to [QueueDriver.push].
abstract class QueueAcknowledgement {
  Future<void> ack(Job job);

  Future<void> release(
    Job job, {
    required bool retry,
    Object? error,
  });
}

/// A lightweight, in-memory implementation for single-server setups
class MemoryQueueDriver implements QueueDriver, QueueInspect {
  final ListQueue<Job> _jobs = ListQueue<Job>();

  @override
  QueueSnapshot inspect() {
    final now = DateTime.now();
    var waiting = 0;
    var delayed = 0;
    for (final job in _jobs) {
      final at = job.availableAt;
      if (at != null && at.isAfter(now)) {
        delayed++;
      } else {
        waiting++;
      }
    }
    return QueueSnapshot(waiting: waiting, delayed: delayed);
  }

  @override
  Future<void> push(Job job) async {
    _jobs.addLast(job);
  }

  @override
  Future<Job?> pop() async {
    if (_jobs.isEmpty) return null;

    final now = DateTime.now();
    final deferred = <Job>[];

    while (_jobs.isNotEmpty) {
      final job = _jobs.removeFirst();
      final availableAt = job.availableAt;
      if (availableAt == null || !availableAt.isAfter(now)) {
        // Re-queue jobs that were not yet ready
        for (final d in deferred) {
          _jobs.addLast(d);
        }
        return job;
      }
      deferred.add(job);
    }

    // Nothing ready — put deferred jobs back
    for (final d in deferred) {
      _jobs.addLast(d);
    }
    return null;
  }

  @override
  Future<bool> cancel(String id) async {
    final before = _jobs.length;
    _jobs.removeWhere((j) => j.id == id);
    return _jobs.length < before;
  }
}
