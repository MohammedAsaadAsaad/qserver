import 'dart:collection';
import 'job.dart';

/// The contract all queue systems (Memory, Redis, RabbitMQ) must follow
abstract class QueueDriver {
  /// Pushes a new job onto the queue
  Future<void> push(Job job);

  /// Retrieves the next job from the queue (FIFO)
  Future<Job?> pop();
}

/// A lightweight, in-memory implementation for single-server setups
class MemoryQueueDriver implements QueueDriver {
  final Queue<Job> _jobs = Queue<Job>();

  @override
  Future<void> push(Job job) async {
    _jobs.add(job);
  }

  @override
  Future<Job?> pop() async {
    if (_jobs.isEmpty) return null;
    return _jobs.removeFirst();
  }
}
