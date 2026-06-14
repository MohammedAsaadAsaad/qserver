import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../../container/quds_env.dart';

/// A global facade for generating and verifying JWTs
class Auth {
  /// The secret key used to sign tokens. Defaults to a fallback if not set.
  static String get _secret => env<String>(
    'APP_KEY',
    'qserver_fallback_secret_key_change_in_production',
  )!;

  /// Generates a signed JWT for a given user payload.
  static String login(
    Map<String, dynamic> userPayload, {
    Duration expiresIn = const Duration(days: 1),
  }) {
    final jwt = JWT(userPayload);
    return jwt.sign(SecretKey(_secret), expiresIn: expiresIn);
  }

  /// Verifies a token and returns the payload. Returns null if invalid or expired.
  static Map<String, dynamic>? verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secret));
      return jwt.payload as Map<String, dynamic>;
    } catch (e) {
      return null; // Token is invalid, expired, or tampered with
    }
  }
}
