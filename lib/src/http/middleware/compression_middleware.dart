import 'dart:convert';
import 'dart:io';

import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Gzip for text/json responses when the client sends `Accept-Encoding: gzip`.
///
/// Not global. Existing uncompressed JSON stays uncompressed unless this is
/// added to a route group.
class CompressionMiddleware extends Middleware {
  final int minBytes;

  CompressionMiddleware({this.minBytes = 256});

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final response = await next(request);
    if (response.eventStream != null || response.isUpgraded) return response;
    if (response.headers['Content-Encoding'] != null) return response;

    final accept = (request.header('accept-encoding') ?? '').toLowerCase();
    if (!accept.contains('gzip')) return response;

    final type = (response.headers['Content-Type'] ?? '').toLowerCase();
    if (!_compressible(type)) return response;

    final bytes = response.rawBody ?? utf8.encode(response.body);
    if (bytes.length < minBytes) return response;

    response.rawBody = gzip.encode(bytes);
    response.headers['Content-Encoding'] = 'gzip';
    response.headers['Vary'] = 'Accept-Encoding';
    return response;
  }

  static bool _compressible(String type) {
    if (type.isEmpty) return false;
    return type.contains('json') ||
        type.contains('text/') ||
        type.contains('javascript') ||
        type.contains('xml') ||
        type.contains('svg');
  }
}
