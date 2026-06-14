import '../storage/storage.dart';

class UploadedFile {
  final String filename;
  final String mimeType;
  final List<int> bytes;
  final int size; // Size in bytes

  UploadedFile({
    required this.filename,
    required this.mimeType,
    required this.bytes,
  }) : size = bytes.length;

  /// Automatically generates a unique timestamped name and saves the file
  Future<String> store(String directory) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = '${timestamp}_${filename.replaceAll(' ', '_')}';

    final path = '$directory/$safeName';
    await Storage.put(path, bytes);

    return path;
  }
}
