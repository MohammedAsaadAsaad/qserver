import 'dart:io';

import 'storage_disk.dart';

/// Local filesystem disk (default). Paths match legacy [Storage] behavior.
class LocalStorageDisk implements StorageDisk {
  final String rootPath;

  LocalStorageDisk({this.rootPath = 'storage/app/public'});

  @override
  Future<String> put(String path, List<int> bytes) async {
    final file = File('$rootPath/$path');
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<bool> exists(String path) async {
    return File('$rootPath/$path').exists();
  }

  @override
  Future<void> delete(String path) async {
    final file = File('$rootPath/$path');
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  String? url(String path) => null;
}
