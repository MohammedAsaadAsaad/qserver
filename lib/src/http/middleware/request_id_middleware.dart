import 'dart:math';

import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Opt-in request correlation id. Not applied globally unless added by the developer.
class RequestIdMiddleware extends Middleware {
  static const attributeKey = 'requestId';
  static const headerName = 'X-Request-Id';

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final incoming =
        _header(request, headerName) ?? _header(request, 'x-request-id');
    final id = (incoming != null && incoming.trim().isNotEmpty)
        ? incoming.trim()
        : _generateId();

    request.attributes[attributeKey] = id;
    final response = await next(request);
    response.headers[headerName] = id;
    return response;
  }

  String? _header(QudsRequest request, String name) {
    try {
      return request.rawRequest.headers.value(name);
    } catch (_) {
      return null;
    }
  }

  String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
