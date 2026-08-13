import 'dart:collection';
import 'job.dart';

/// The contract all queue systems (Memory, Redis, RabbitMQ) must follow
abstract class QueueDriver {
  /// Pushes a new job onto the queue
  Future<void> push(Job job);

  /// Retrieves the next ready job from the queue (FIFO among ready jobs)
  Future<Job?> pop();
}

/// A lightweight, in-memory implementation for single-server setups
class MemoryQueueDriver implements QueueDriver {
  final ListQueue<Job> _jobs = ListQueue<Job>();

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
}
