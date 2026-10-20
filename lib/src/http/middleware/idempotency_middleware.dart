import 'dart:convert';

import '../../cache/cache.dart';
import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Replays POST/PUT/PATCH responses when `Idempotency-Key` is present.
///
/// Missing keys pass through unchanged. Not applied globally.
class IdempotencyMiddleware extends Middleware {
  final Duration ttl;
  final String headerName;

  IdempotencyMiddleware({
    this.ttl = const Duration(hours: 24),
    this.headerName = 'Idempotency-Key',
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final method = request.method.toUpperCase();
    if (method != 'POST' && method != 'PUT' && method != 'PATCH') {
      return next(request);
    }

    final key = request.header(headerName)?.trim();
    if (key == null || key.isEmpty) return next(request);

    final cacheKey = 'idem:$method:${request.path}:$key';
    final cached = await Cache.get<String>(cacheKey);
    if (cached != null && cached != 'pending') {
      return _decode(cached);
    }

    if (cached == 'pending') {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final again = await Cache.get<String>(cacheKey);
        if (again != null && again != 'pending') return _decode(again);
      }
    }

    await Cache.put(cacheKey, 'pending', ttl: ttl);
    final response = await next(request);
    if (response.eventStream == null && !response.isUpgraded) {
      await Cache.put(cacheKey, _encode(response), ttl: ttl);
    }
    return response;
  }

  static String _encode(QudsResponse response) {
    return jsonEncode({
      'status': response.statusCode,
      'body': response.body,
      'headers': response.headers,
    });
  }

  static QudsResponse _decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final headers = <String, String>{};
    final rawHeaders = map['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        headers[key.toString()] = value.toString();
      });
    }
    return QudsResponse(
      statusCode: map['status'] as int? ?? 200,
      body: map['body']?.toString() ?? '',
      headers: headers,
    );
  }
}
