import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../../container/quds_env.dart';

typedef AuthRevokeListener = void Function(String token);

/// A global facade for generating and verifying JWTs
class Auth {
  static final Set<String> _revokedTokens = {};
  static final List<AuthRevokeListener> _revokeListeners = [];

  /// The secret key used to sign tokens. Defaults to a fallback if not set.
  static String get _secret => env<String>(
        'APP_KEY',
        'qserver_fallback_secret_key_change_in_production',
      )!;

  /// Generates a signed JWT for a given user payload.
  /// Pass [expiresIn] as `null` for a token that never expires.
  static String login(
    Map<String, dynamic> userPayload, {
    Duration? expiresIn = const Duration(days: 1),
  }) {
    final jwt = JWT(userPayload);
    if (expiresIn == null) {
      return jwt.sign(SecretKey(_secret));
    }
    return jwt.sign(SecretKey(_secret), expiresIn: expiresIn);
  }

  /// Verifies a token and returns the payload. Returns null if invalid,
  /// expired, or revoked.
  static Map<String, dynamic>? verify(String token) {
    if (_revokedTokens.contains(token)) return null;
    try {
      final jwt = JWT.verify(token, SecretKey(_secret));
      return jwt.payload as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Marks [token] as invalid and notifies listeners (e.g. WebSocket manager).
  static void invalidate(String token) {
    _revokedTokens.add(token);
    for (final listener in List<AuthRevokeListener>.from(_revokeListeners)) {
      listener(token);
    }
  }

  /// Whether [token] was previously invalidated in this process.
  static bool isRevoked(String token) => _revokedTokens.contains(token);

  /// Register a listener invoked when [invalidate] is called.
  static void onRevoke(AuthRevokeListener listener) {
    _revokeListeners.add(listener);
  }

  /// Clears in-memory revoke state (useful in tests).
  static void clearRevocations() {
    _revokedTokens.clear();
  }
}
