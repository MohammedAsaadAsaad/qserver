import '../http/middleware/server_monitor.dart';
import '../http/quds_request.dart';
import '../http/quds_response.dart';
import '../routing/router.dart';
import '../container/quds_env.dart';
import 'exception_log.dart';
import 'http_exceptions.dart';

/// A centralized hub for formatting and returning application errors.
class GlobalExceptionHandler {
  /// True for validation / authorization / operational HTTP failures.
  static bool isExpected(Object error) {
    return error is QudsValidationException ||
        error is QudsAuthorizationException ||
        error is QudsPayloadTooLargeException ||
        error is QudsRequestTimeoutException ||
        error is QudsServiceUnavailableException;
  }

  static int statusOf(Object error) {
    if (error is QudsValidationException) return 422;
    if (error is QudsAuthorizationException) return 403;
    if (error is QudsPayloadTooLargeException) return 413;
    if (error is QudsRequestTimeoutException) return 504;
    if (error is QudsServiceUnavailableException) return 503;
    return 500;
  }

  /// Translates a thrown error into a clean HTTP response, and records
  /// unexpected exceptions for later review.
  static QudsResponse handle(
    Object error, {
    StackTrace? stackTrace,
    QudsRequest? request,
    bool logExpected = false,
  }) {
    if (!isExpected(error) || logExpected) {
      ExceptionLog.add(
        QudsExceptionRecord.capture(
          error,
          stackTrace ?? StackTrace.current,
          request,
        ),
      );
      ServerMonitor.refresh();
    }

    return toResponse(
      error,
      request: request,
      stackTrace: stackTrace,
    );
  }

  /// Maps an error to an HTTP response without writing to [ExceptionLog].
  static QudsResponse toResponse(
    Object error, {
    QudsRequest? request,
    StackTrace? stackTrace,
  }) {
    if (error is QudsValidationException) {
      return QudsResponse.json({
        'message': 'The given data was invalid.',
        'errors': error.errors,
      }, status: 422);
    }

    if (error is QudsAuthorizationException) {
      return QudsResponse.error(error.message, status: 403);
    }

    if (error is QudsPayloadTooLargeException) {
      return QudsResponse.error(error.message, status: 413);
    }

    if (error is QudsRequestTimeoutException) {
      return QudsResponse.error(error.message, status: 504);
    }

    if (error is QudsServiceUnavailableException) {
      return QudsResponse.error(error.message, status: 503);
    }

    final debug = isLocalEnvironment();
    final payload = <String, dynamic>{
      'error': true,
      'message': debug
          ? error.toString()
          : 'Internal Server Error. Please contact the administrator.',
    };

    if (debug) {
      payload['type'] = error.runtimeType.toString();
      if (request != null) {
        payload['method'] = request.method;
        payload['path'] = request.pathAndQuery;
      }
      if (stackTrace != null) {
        payload['trace'] = stackTrace
            .toString()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .take(12)
            .toList();
      }
    }

    return QudsResponse.json(payload, status: 500);
  }
}
