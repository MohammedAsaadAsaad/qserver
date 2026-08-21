/// The base class for all background jobs
abstract class Job {
  /// Optional stable id (required for [Queue.cancel] with the database driver).
  String? id;

  /// Shown on the queue preloader. Defaults to the runtime type name.
  String get label => runtimeType.toString();

  /// The logic that will be executed in the background
  Future<void> handle();

  /// How many times to retry the job if it fails
  int get maxRetries => 3;

  /// How many times this job has already been attempted
  int attempts = 0;

  /// When the job becomes eligible to run (`null` = immediately)
  DateTime? availableAt;
}
