import 'quds_request.dart';
import 'quds_response.dart';

/// The function signature for passing a request to the next layer in the pipeline
typedef NextMiddleware = Future<QudsResponse> Function(QudsRequest request);

/// The base class for all Quds Server Middleware
abstract class Middleware {
  /// Intercepts the request.
  /// You must call `await next(request)` to continue the pipeline,
  /// or return a `QudsResponse` directly to halt execution.
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next);
}
