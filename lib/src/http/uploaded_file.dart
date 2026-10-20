import '../exceptions/http_exceptions.dart';
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

  /// Opt-in size / MIME / extension checks. [store] still has no rules.
  void assertAllowed({
    int? maxBytes,
    List<String>? mimeTypes,
    List<String>? extensions,
  }) {
    if (maxBytes != null && size > maxBytes) {
      throw QudsUploadException(
        'The file may not be greater than $maxBytes bytes.',
      );
    }
    if (mimeTypes != null && mimeTypes.isNotEmpty) {
      final allowed = mimeTypes.map((m) => m.toLowerCase()).toSet();
      if (!allowed.contains(mimeType.toLowerCase())) {
        throw QudsUploadException(
          'The file type $mimeType is not allowed.',
        );
      }
    }
    if (extensions != null && extensions.isNotEmpty) {
      final name = filename.toLowerCase();
      final ok = extensions.any((ext) {
        final needle =
            ext.startsWith('.') ? ext.toLowerCase() : '.$ext'.toLowerCase();
        return name.endsWith(needle);
      });
      if (!ok) {
        throw QudsUploadException('The file extension is not allowed.');
      }
    }
  }

  Future<String> storeIfAllowed(
    String directory, {
    int? maxBytes,
    List<String>? mimeTypes,
    List<String>? extensions,
  }) {
    assertAllowed(
      maxBytes: maxBytes,
      mimeTypes: mimeTypes,
      extensions: extensions,
    );
    return store(directory);
  }
}
