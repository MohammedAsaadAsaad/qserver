import '../../routing/router.dart';
import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import 'cookie_session_middleware.dart';

/// Double-submit CSRF for cookie sessions. Safe methods pass through.
///
/// Must sit behind [CookieSessionMiddleware]. Not global.
class CsrfMiddleware extends Middleware {
  final List<String> safeMethods;

  CsrfMiddleware({
    this.safeMethods = const ['GET', 'HEAD', 'OPTIONS'],
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final session = Session.of(request);
    final token = session['csrf']?.toString();
    if (token == null || token.isEmpty) {
      throw QudsAuthorizationException('CSRF token missing.');
    }

    final method = request.method.toUpperCase();
    if (!safeMethods.contains(method)) {
      final provided = request.header('x-csrf-token') ??
          request.input<String>('_token') ??
          request.query('_token');
      if (provided != token) {
        throw QudsAuthorizationException('CSRF token mismatch.');
      }
    }

    final response = await next(request);
    response.headers.putIfAbsent('X-CSRF-TOKEN', () => token);
    return response;
  }
}
