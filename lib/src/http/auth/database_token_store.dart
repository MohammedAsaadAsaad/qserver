import 'dart:convert';

import 'package:quds_db_interface/quds_db_interface.dart';

import 'auth.dart';

/// Postgres/MySQL [TokenStore]. Off unless `AUTH_TOKEN_STORE=database`.
///
/// Default remains [MemoryTokenStore]. Custom stores already bound on the
/// container are never replaced.
class DatabaseTokenStore implements TokenStore {
  final DatabaseConnection connection;
  bool _ensured = false;

  DatabaseTokenStore(this.connection);

  Future<void> _ensureTable() async {
    if (_ensured) return;
    await connection.execute('''
CREATE TABLE IF NOT EXISTS quds_refresh_tokens (
  token_hash TEXT PRIMARY KEY,
  token_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  expires_at TEXT NOT NULL
)
''');
    _ensured = true;
  }

  @override
  Future<void> saveRefreshToken({
    required String tokenId,
    required String tokenHash,
    required Map<String, dynamic> payload,
    required DateTime expiresAt,
  }) async {
    await _ensureTable();
    await connection.execute(
      '''
INSERT INTO quds_refresh_tokens (token_hash, token_id, payload, expires_at)
VALUES (?, ?, ?, ?)
''',
      [
        tokenHash,
        tokenId,
        jsonEncode(payload),
        expiresAt.toUtc().toIso8601String(),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>?> findRefreshToken(String tokenHash) async {
    await _ensureTable();
    final rows = await connection.query(
      'SELECT * FROM quds_refresh_tokens WHERE token_hash = ? LIMIT 1',
      [tokenHash],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final expiresRaw = row['expires_at']?.toString();
    final expiresAt = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
    if (expiresAt != null && DateTime.now().isAfter(expiresAt.toLocal())) {
      await revokeRefreshToken(tokenHash);
      return null;
    }
    Map<String, dynamic> payload = const {};
    final raw = row['payload']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        } else if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return {
      'tokenId': row['token_id']?.toString() ?? '',
      'payload': payload,
      'expiresAt': expiresRaw,
    };
  }

  @override
  Future<void> revokeRefreshToken(String tokenHash) async {
    await _ensureTable();
    await connection.execute(
      'DELETE FROM quds_refresh_tokens WHERE token_hash = ?',
      [tokenHash],
    );
  }

  @override
  Future<void> revokeAllForSubject(String subject) async {
    await _ensureTable();
    final rows = await connection.query(
      'SELECT token_hash, payload FROM quds_refresh_tokens',
    );
    for (final row in rows) {
      Map<String, dynamic> payload = const {};
      final raw = row['payload']?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            payload = decoded;
          } else if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
      if (payload['sub']?.toString() == subject) {
        await revokeRefreshToken(row['token_hash']?.toString() ?? '');
      }
    }
  }
}
