import 'dart:io';

import 'quds_request.dart';
import 'quds_response.dart';

/// Serves files from [rootDirectory]. Used by [QudsRouter.staticFiles].
class StaticFiles {
  static Future<QudsResponse> serve(
    String rootDirectory,
    String relativePath,
  ) async {
    var relative = relativePath.replaceAll('\\', '/');
    if (relative.startsWith('/')) relative = relative.substring(1);
    if (relative.isEmpty) relative = 'index.html';
    if (relative.contains(String.fromCharCode(0)) ||
        relative.split('/').contains('..')) {
      return QudsResponse.error('Forbidden', status: 403);
    }

    final root = Directory(rootDirectory).absolute;
    final file =
        File('${root.path}${Platform.pathSeparator}$relative').absolute;
    final rootPath = root.path.endsWith(Platform.pathSeparator)
        ? root.path
        : '${root.path}${Platform.pathSeparator}';
    if (file.path != root.path && !file.path.startsWith(rootPath)) {
      return QudsResponse.error('Forbidden', status: 403);
    }
    if (!await file.exists()) {
      return QudsResponse.error('Not found', status: 404);
    }

    final bytes = await file.readAsBytes();
    return QudsResponse.bytes(bytes, contentType: mimeType(file.path));
  }

  static Future<QudsResponse> fromRequest(
    QudsRequest request,
    String rootDirectory,
  ) {
    return serve(rootDirectory, request.param('path') ?? '');
  }

  static String mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return 'text/html; charset=utf-8';
    }
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.js')) return 'text/javascript; charset=utf-8';
    if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain; charset=utf-8';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.woff')) return 'font/woff';
    return 'application/octet-stream';
  }
}
