import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Opt-in security headers. Not applied globally unless the developer adds it.
class SecurityHeadersMiddleware extends Middleware {
  final bool enableHsts;
  final Map<String, String> extra;

  SecurityHeadersMiddleware({
    this.enableHsts = false,
    this.extra = const {},
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final response = await next(request);
    response.headers.putIfAbsent(
      'X-Content-Type-Options',
      () => 'nosniff',
    );
    response.headers.putIfAbsent(
      'X-Frame-Options',
      () => 'DENY',
    );
    response.headers.putIfAbsent(
      'Referrer-Policy',
      () => 'no-referrer',
    );
    response.headers.putIfAbsent(
      'X-XSS-Protection',
      () => '0',
    );
    if (enableHsts) {
      response.headers.putIfAbsent(
        'Strict-Transport-Security',
        () => 'max-age=31536000; includeSubDomains',
      );
    }
    extra.forEach((key, value) {
      response.headers.putIfAbsent(key, () => value);
    });
    return response;
  }
}
