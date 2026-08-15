import 'job.dart';

/// A [Job] that can be persisted (e.g. in [DatabaseQueueDriver]).
///
/// Register a `fromMap` factory via [JobRegistry.register] using [jobType].
abstract class SerializableJob extends Job {
  /// Stable type key stored in the queue backend.
  String get jobType;

  /// Serializes job payload for persistence.
  Map<String, dynamic> toMap();
}
