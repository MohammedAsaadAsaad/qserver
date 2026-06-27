import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'uploaded_file.dart';
import 'enums.dart';

class RequestParser {
  /// Consumes the request stream and parses it into dynamic data
  static Future<Map<String, dynamic>> parseBody(HttpRequest request) async {
    final mimeTypeStr = request.headers.contentType?.mimeType;
    final mediaType = MediaType.fromString(mimeTypeStr);

    if (mediaType == null) return {};

    switch (mediaType) {
      case MediaType.json:
        final content = await utf8.decoder.bind(request).join();
        if (content.trim().isEmpty) return {};
        final decoded = jsonDecode(content);
        return decoded is Map<String, dynamic> ? decoded : {'data': decoded};

      case MediaType.formUrlEncoded:
        final content = await utf8.decoder.bind(request).join();
        return Uri.splitQueryString(content);

      case MediaType.multipartFormData:
        return await _parseMultipart(request);

      case MediaType.textPlain:
        final content = await utf8.decoder.bind(request).join();
        return {'text': content};
    }
  }

  /// Extracts files and form fields safely from a multipart boundary stream
  static Future<Map<String, dynamic>> _parseMultipart(
    HttpRequest request,
  ) async {
    final Map<String, dynamic> parsedData = {};

    // Extract the boundary string from the header
    final boundary = request.headers.contentType!.parameters['boundary'];
    if (boundary == null) return parsedData;

    final transformer = MimeMultipartTransformer(boundary);
    final parts = request.cast<List<int>>().transform(transformer);

    await for (final part in parts) {
      final disposition = part.headers['content-disposition'];
      if (disposition == null) continue;

      // Extract the field name
      final nameMatch = RegExp(r'name="([^"]+)"').firstMatch(disposition);
      final fieldName = nameMatch?.group(1);
      if (fieldName == null) continue;

      // Extract the filename (if it's a file upload)
      final filenameMatch = RegExp(
        r'filename="([^"]+)"',
      ).firstMatch(disposition);
      final filename = filenameMatch?.group(1);

      if (filename != null) {
        // It's a File
        final bytes = await part.fold<List<int>>([], (b, d) => b..addAll(d));
        final mimeType =
            part.headers['content-type'] ?? 'application/octet-stream';

        parsedData[fieldName] = UploadedFile(
          filename: filename,
          mimeType: mimeType,
          bytes: bytes,
        );
      } else {
        // It's a standard text field
        final content = await utf8.decoder.bind(part).join();
        parsedData[fieldName] = content;
      }
    }

    return parsedData;
  }
}
