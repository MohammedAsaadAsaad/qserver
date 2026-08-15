import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../../container/quds_container.dart';
import '../../container/quds_env.dart';

/// Persists refresh-token metadata (hashed).
abstract class TokenStore {
  Future<void> saveRefreshToken({
    required String tokenId,
    required String tokenHash,
    required Map<String, dynamic> payload,
    required DateTime expiresAt,
  });

  Future<Map<String, dynamic>?> findRefreshToken(String tokenHash);

  Future<void> revokeRefreshToken(String tokenHash);

  Future<void> revokeAllForSubject(String subject);
}

/// In-process token store (default — same process lifetime as 0.0.9 revoke set).
class MemoryTokenStore implements TokenStore {
  final Map<String, _StoredRefresh> _byHash = {};

  @override
  Future<void> saveRefreshToken({
    required String tokenId,
    required String tokenHash,
    required Map<String, dynamic> payload,
    required DateTime expiresAt,
  }) async {
    _byHash[tokenHash] = _StoredRefresh(
      tokenId: tokenId,
      payload: Map<String, dynamic>.from(payload),
      expiresAt: expiresAt,
    );
  }

  @override
  Future<Map<String, dynamic>?> findRefreshToken(String tokenHash) async {
    final row = _byHash[tokenHash];
    if (row == null) return null;
    if (DateTime.now().isAfter(row.expiresAt)) {
      _byHash.remove(tokenHash);
      return null;
    }
    return {
      'tokenId': row.tokenId,
      'payload': row.payload,
      'expiresAt': row.expiresAt.toIso8601String(),
    };
  }

  @override
  Future<void> revokeRefreshToken(String tokenHash) async {
    _byHash.remove(tokenHash);
  }

  @override
  Future<void> revokeAllForSubject(String subject) async {
    _byHash.removeWhere((_, v) => v.payload['sub']?.toString() == subject);
  }
}

class _StoredRefresh {
  final String tokenId;
  final Map<String, dynamic> payload;
  final DateTime expiresAt;

  _StoredRefresh({
    required this.tokenId,
    required this.payload,
    required this.expiresAt,
  });
}

typedef AuthRevokeListener = void Function(String token);

/// A global facade for generating and verifying JWTs
class Auth {
  static final Set<String> _revokedTokens = {};
  static final List<AuthRevokeListener> _revokeListeners = [];

  static String get _secret => env<String>(
        'APP_KEY',
        'qserver_fallback_secret_key_change_in_production',
      )!;

  static TokenStore _tokenStore() {
    if (!QudsContainer.isRegistered<TokenStore>()) {
      QudsContainer.singleton<TokenStore>(MemoryTokenStore());
    }
    return QudsContainer.resolve<TokenStore>();
  }

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

  /// Issues a short-lived access token plus a refresh token (new API; [login] unchanged).
  static Future<Map<String, dynamic>> issueTokens(
    Map<String, dynamic> userPayload, {
    Duration accessExpiresIn = const Duration(minutes: 15),
    Duration refreshExpiresIn = const Duration(days: 30),
  }) async {
    final accessToken = login(userPayload, expiresIn: accessExpiresIn);
    final tokenId = _randomId();
    final refreshPayload = {
      ...userPayload,
      'type': 'refresh',
      'jti': tokenId,
    };
    final refreshToken = JWT(refreshPayload).sign(
      SecretKey(_secret),
      expiresIn: refreshExpiresIn,
    );
    final hash = _hashToken(refreshToken);
    await _tokenStore().saveRefreshToken(
      tokenId: tokenId,
      tokenHash: hash,
      payload: userPayload,
      expiresAt: DateTime.now().add(refreshExpiresIn),
    );
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresIn': accessExpiresIn.inSeconds,
      'tokenType': 'Bearer',
    };
  }

  /// Rotates tokens using a previously issued refresh token.
  static Future<Map<String, dynamic>?> refresh(String refreshToken) async {
    final hash = _hashToken(refreshToken);
    final stored = await _tokenStore().findRefreshToken(hash);
    if (stored == null) return null;

    final payload = verify(refreshToken);
    if (payload == null || payload['type'] != 'refresh') return null;

    await _tokenStore().revokeRefreshToken(hash);
    final userPayload = Map<String, dynamic>.from(
      stored['payload'] as Map<String, dynamic>,
    );
    return issueTokens(userPayload);
  }

  /// Revokes a refresh token so it cannot be reused.
  static Future<void> revokeRefresh(String refreshToken) async {
    await _tokenStore().revokeRefreshToken(_hashToken(refreshToken));
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

  static bool isRevoked(String token) => _revokedTokens.contains(token);

  static void onRevoke(AuthRevokeListener listener) {
    _revokeListeners.add(listener);
  }

  static void clearRevocations() {
    _revokedTokens.clear();
  }

  static String _hashToken(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  static String _randomId() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
