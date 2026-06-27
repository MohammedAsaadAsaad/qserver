/// The base class for all background jobs
abstract class Job {
  /// The logic that will be executed in the background
  Future<void> handle();

  /// Optional: How many times to retry the job if it fails
  int get maxRetries => 3;
}
