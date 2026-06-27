import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

class CorsMiddleware extends Middleware {
  final List<String> allowedOrigins;
  final List<String> allowedMethods;
  final List<String> allowedHeaders;

  CorsMiddleware({
    this.allowedOrigins = const ['*'], // Default to all
    this.allowedMethods = const [
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'OPTIONS',
    ],
    this.allowedHeaders = const [
      'Origin',
      'Content-Type',
      'Accept',
      'Authorization',
    ],
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    // 1. Intercept pre-flight OPTIONS requests from the browser
    if (request.method.toUpperCase() == 'OPTIONS') {
      return QudsResponse(
        statusCode: 204, // No Content
        headers: _buildCorsHeaders(),
      );
    }

    // 2. Pass the request down the chain
    final response = await next(request);

    // 3. Attach CORS headers to the final response before sending it back
    _buildCorsHeaders().forEach((key, value) {
      response.headers[key] = value;
    });

    return response;
  }

  Map<String, String> _buildCorsHeaders() {
    return {
      'Access-Control-Allow-Origin': allowedOrigins.join(', '),
      'Access-Control-Allow-Methods': allowedMethods.join(', '),
      'Access-Control-Allow-Headers': allowedHeaders.join(', '),
      'Access-Control-Allow-Credentials': 'true',
    };
  }
}
