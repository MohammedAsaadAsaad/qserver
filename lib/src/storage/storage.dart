import 'dart:io';

/// A global facade for managing file storage
class Storage {
  /// The root directory where local files are stored
  static String rootPath = 'storage/app/public';

  /// Saves a file to the disk
  static Future<String> put(String path, List<int> bytes) async {
    final file = File('$rootPath/$path');

    // Ensure the directory exists before saving
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Checks if a file exists
  static Future<bool> exists(String path) async {
    return await File('$rootPath/$path').exists();
  }

  /// Deletes a file from the disk
  static Future<void> delete(String path) async {
    final file = File('$rootPath/$path');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
