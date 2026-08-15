import 'job.dart';
import 'serializable_job.dart';

/// Maps [SerializableJob.jobType] strings to factory constructors.
class JobRegistry {
  static final Map<String, Job Function(Map<String, dynamic>)> _factories = {};

  /// Registers a factory for [jobType]. Call once at boot for each job class.
  static void register(
    String jobType,
    Job Function(Map<String, dynamic> data) factory,
  ) {
    _factories[jobType] = factory;
  }

  /// Whether [jobType] has a registered factory.
  static bool isRegistered(String jobType) => _factories.containsKey(jobType);

  /// Rebuilds a job from persisted [data], or `null` if unknown.
  static Job? create(String jobType, Map<String, dynamic> data) {
    final factory = _factories[jobType];
    if (factory == null) return null;
    return factory(data);
  }

  /// Clears all registrations (tests).
  static void clear() => _factories.clear();
}
