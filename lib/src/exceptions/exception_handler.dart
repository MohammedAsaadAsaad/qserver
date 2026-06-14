import '../http/quds_request.dart';
import '../http/quds_response.dart';
import '../routing/router.dart'; // To access validation/auth exceptions

/// A centralized hub for formatting and returning application errors
class GlobalExceptionHandler {
  /// Translates a Dart Exception into a clean HTTP Response
  static QudsResponse handle(Exception error, QudsRequest? request) {
    // 1. Handle Validation Errors (422)
    if (error is QudsValidationException) {
      return QudsResponse.json({
        'message': 'The given data was invalid.',
        'errors': error.errors,
      }, status: 422);
    }

    // 2. Handle Authorization Errors (403)
    if (error is QudsAuthorizationException) {
      return QudsResponse.error(error.message, status: 403);
    }

    // 3. Handle Generic/Unhandled Server Crashes (500)
    // In a real app, we check if APP_DEBUG is true to show the stack trace
    print('\x1B[31m[CRITICAL ERROR] ${error.toString()}\x1B[0m');

    return QudsResponse.error(
      "Internal Server Error. Please contact the administrator.",
      status: 500,
    );
  }
}
