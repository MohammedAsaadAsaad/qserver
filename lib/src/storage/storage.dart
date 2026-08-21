import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'gcs_storage_disk.dart';
import 'local_storage_disk.dart';
import 's3_storage_disk.dart';
import 'storage_disk.dart';

/// A global facade for managing file storage.
///
/// Default disk is local (`FILESYSTEM_DISK=local`) with the same paths as 0.0.9.
class Storage {
  static StorageDisk _disk = LocalStorageDisk();

  /// The root directory used by the local disk (kept for BC).
  static String get rootPath {
    final d = _disk;
    if (d is LocalStorageDisk) return d.rootPath;
    return 'storage/app/public';
  }

  static set rootPath(String value) {
    if (_disk is LocalStorageDisk) {
      _disk = LocalStorageDisk(rootPath: value);
    }
  }

  /// Active disk implementation.
  static StorageDisk get disk => _disk;

  /// Replaces the active disk (tests / custom bindings).
  static void use(StorageDisk disk) => _disk = disk;

  /// Applies `FILESYSTEM_DISK` after env load. Defaults keep local behavior.
  static void configureFromEnv([String? diskName]) {
    final name =
        (diskName ?? env<String>('FILESYSTEM_DISK', 'local') ?? 'local')
            .toLowerCase();
    switch (name) {
      case 's3':
        _disk = S3StorageDisk();
        Log.info('Disk s3', component: 'storage');
        break;
      case 'gcs':
        _disk = GcsStorageDisk();
        Log.info('Disk gcs', component: 'storage');
        break;
      default:
        final currentRoot = _disk is LocalStorageDisk
            ? (_disk as LocalStorageDisk).rootPath
            : 'storage/app/public';
        _disk = LocalStorageDisk(rootPath: currentRoot);
        Log.debug('Disk local', component: 'storage');
    }
  }

  /// Saves a file to the active disk
  static Future<String> put(String path, List<int> bytes) =>
      _disk.put(path, bytes);

  /// Checks if a file exists
  static Future<bool> exists(String path) => _disk.exists(path);

  /// Deletes a file from the disk
  static Future<void> delete(String path) => _disk.delete(path);

  /// Public URL when supported (S3 via `S3_PUBLIC_URL`); otherwise `null`.
  static String? url(String path) => _disk.url(path);
}
