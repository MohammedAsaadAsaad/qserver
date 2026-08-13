import 'dart:async';

import '../../exceptions/exception_handler.dart';
import '../../exceptions/exception_log.dart';
import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import 'server_monitor.dart';

/// Called when a request throws. Return a response to handle it, or `null`
/// to fall back to [GlobalExceptionHandler].
typedef QudsExceptionHandler = FutureOr<QudsResponse?> Function(
  Object error,
  StackTrace stackTrace,
  QudsRequest request,
);

/// Catches exceptions in the pipeline, logs them for later review, and
/// turns them into HTTP responses.
///
/// Register it **after** [LoggerMiddleware] so failed requests still appear
/// in the live traffic feed:
///
/// ```dart
/// app.router.use(LoggerMiddleware());
/// app.router.use(ExceptionHandlerMiddleware(
///   handler: (error, stack, request) {
///     if (error is FormatException) {
///       return QudsResponse.error(error.message, status: 400);
///     }
///     return null; // use the default 500/422/403 mapping
///   },
/// ));
/// ```
class ExceptionHandlerMiddleware extends Middleware {
  final QudsExceptionHandler? handler;

  /// When true, validation (422) and authorization (403) failures are also
  /// written to [ExceptionLog]. Unexpected errors are always logged.
  final bool logExpected;

  ExceptionHandlerMiddleware({
    this.handler,
    this.logExpected = false,
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    try {
      return await next(request);
    } catch (error, stackTrace) {
      final expected = GlobalExceptionHandler.isExpected(error);
      if (!expected || logExpected) {
        ExceptionLog.add(
          QudsExceptionRecord.capture(error, stackTrace, request),
        );
        ServerMonitor.refresh();
      }

      if (handler != null) {
        final custom = await handler!(error, stackTrace, request);
        if (custom != null) return custom;
      }

      return GlobalExceptionHandler.toResponse(
        error,
        request: request,
        stackTrace: stackTrace,
      );
    }
  }
}
