/// Contract for storage backends (local disk, S3, …).
abstract class StorageDisk {
  /// Writes [bytes] to [path] and returns a location string.
  Future<String> put(String path, List<int> bytes);

  /// Whether [path] exists on this disk.
  Future<bool> exists(String path);

  /// Deletes [path] if present.
  Future<void> delete(String path);

  /// Public URL for [path], when the disk supports it.
  String? url(String path);
}
