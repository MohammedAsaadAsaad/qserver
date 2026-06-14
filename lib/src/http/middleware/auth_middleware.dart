import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import '../../routing/router.dart';
import '../auth/auth.dart';

class AuthMiddleware extends Middleware {
  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final authHeader = request.rawRequest.headers.value('authorization');

    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      throw QudsAuthorizationException(
        "Unauthenticated. Please provide a valid Bearer token.",
      );
    }

    final token = authHeader.substring(7); // Remove 'Bearer '
    final payload = Auth.verify(token);

    if (payload == null) {
      throw QudsAuthorizationException(
        "Invalid or expired token. Please log in again.",
      );
    }

    // Securely inject the user payload into the request
    request.attributes['user'] = payload;

    // Pass the request to the controller
    return await next(request);
  }
}
