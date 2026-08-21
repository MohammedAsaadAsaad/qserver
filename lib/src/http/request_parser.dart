import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import '../exceptions/http_exceptions.dart';
import 'uploaded_file.dart';
import 'enums.dart';

class RequestParser {
  /// Throws when [contentLength] is known and exceeds [maxBytes].
  ///
  /// [maxBytes] `<= 0` disables the check (0.0.10 default).
  static void rejectIfTooLarge(int contentLength, int maxBytes) {
    if (maxBytes <= 0) return;
    if (contentLength >= 0 && contentLength > maxBytes) {
      throw QudsPayloadTooLargeException(
        contentLength: contentLength,
        maxBytes: maxBytes,
      );
    }
  }

  /// Consumes the request stream and parses it into dynamic data
  static Future<Map<String, dynamic>> parseBody(
    HttpRequest request, {
    int maxBytes = 0,
  }) async {
    rejectIfTooLarge(request.headers.contentLength, maxBytes);

    final mimeTypeStr = request.headers.contentType?.mimeType;
    final mediaType = MediaType.fromString(mimeTypeStr);

    if (mediaType == null) return {};

    switch (mediaType) {
      case MediaType.json:
        final content = await _readUtf8(request, maxBytes);
        if (content.trim().isEmpty) return {};
        final decoded = jsonDecode(content);
        return decoded is Map<String, dynamic> ? decoded : {'data': decoded};

      case MediaType.formUrlEncoded:
        final content = await _readUtf8(request, maxBytes);
        return Uri.splitQueryString(content);

      case MediaType.multipartFormData:
        return await _parseMultipart(request, maxBytes: maxBytes);

      case MediaType.textPlain:
        final content = await _readUtf8(request, maxBytes);
        return {'text': content};
    }
  }

  static Future<String> _readUtf8(HttpRequest request, int maxBytes) async {
    if (maxBytes <= 0) {
      return utf8.decoder.bind(request).join();
    }

    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
      if (chunks.length > maxBytes) {
        throw QudsPayloadTooLargeException(
          contentLength: chunks.length,
          maxBytes: maxBytes,
        );
      }
    }
    return utf8.decode(chunks);
  }

  /// Extracts files and form fields safely from a multipart boundary stream
  static Future<Map<String, dynamic>> _parseMultipart(
    HttpRequest request, {
    int maxBytes = 0,
  }) async {
    final Map<String, dynamic> parsedData = {};

    // Extract the boundary string from the header
    final boundary = request.headers.contentType!.parameters['boundary'];
    if (boundary == null) return parsedData;

    final transformer = MimeMultipartTransformer(boundary);
    final parts = request.cast<List<int>>().transform(transformer);
    var total = 0;

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
        final bytes = <int>[];
        await for (final chunk in part) {
          bytes.addAll(chunk);
          total += chunk.length;
          if (maxBytes > 0 && total > maxBytes) {
            throw QudsPayloadTooLargeException(
              contentLength: total,
              maxBytes: maxBytes,
            );
          }
        }
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
        total += content.length;
        if (maxBytes > 0 && total > maxBytes) {
          throw QudsPayloadTooLargeException(
            contentLength: total,
            maxBytes: maxBytes,
          );
        }
        parsedData[fieldName] = content;
      }
    }

    return parsedData;
  }
}
