import 'dart:convert';

import 'package:quds_db_interface/quds_db_interface.dart';

import 'user_store.dart';

/// Postgres/MySQL [UserStore]. Off unless `AUTH_USER_STORE=database`.
///
/// Default remains [MemoryUserStore]. Custom stores already bound on the
/// container are never replaced.
class DatabaseUserStore implements UserStore {
  final DatabaseConnection connection;
  bool _ensured = false;

  DatabaseUserStore(this.connection);

  Future<void> _ensureTable() async {
    if (_ensured) return;
    await connection.execute('''
CREATE TABLE IF NOT EXISTS quds_users (
  id TEXT PRIMARY KEY,
  email TEXT,
  name TEXT,
  password_hash TEXT,
  provider TEXT NOT NULL,
  provider_id TEXT,
  email_verified INTEGER NOT NULL DEFAULT 0,
  extra TEXT,
  created_at TEXT NOT NULL
)
''');
    _ensured = true;
  }

  @override
  Future<AuthUser?> findById(String id) async {
    await _ensureTable();
    final rows = await connection.query(
      'SELECT * FROM quds_users WHERE id = ? LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<AuthUser?> findByEmail(String email) async {
    await _ensureTable();
    final rows = await connection.query(
      'SELECT * FROM quds_users WHERE email = ? LIMIT 1',
      [email.toLowerCase()],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<AuthUser?> findByProvider(String provider, String providerId) async {
    await _ensureTable();
    final rows = await connection.query(
      'SELECT * FROM quds_users WHERE provider = ? AND provider_id = ? LIMIT 1',
      [provider, providerId],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<AuthUser> create(AuthUser user) async {
    await _ensureTable();
    await connection.execute(
      '''
INSERT INTO quds_users
  (id, email, name, password_hash, provider, provider_id, email_verified, extra, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        user.id,
        user.email?.toLowerCase(),
        user.name,
        user.passwordHash,
        user.provider,
        user.providerId,
        user.emailVerified ? 1 : 0,
        jsonEncode(user.extra),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return user;
  }

  @override
  Future<AuthUser> update(AuthUser user) async {
    await _ensureTable();
    await connection.execute(
      '''
UPDATE quds_users
SET email = ?, name = ?, password_hash = ?, provider = ?, provider_id = ?,
    email_verified = ?, extra = ?
WHERE id = ?
''',
      [
        user.email?.toLowerCase(),
        user.name,
        user.passwordHash,
        user.provider,
        user.providerId,
        user.emailVerified ? 1 : 0,
        jsonEncode(user.extra),
        user.id,
      ],
    );
    return user;
  }

  AuthUser _fromRow(Map<String, dynamic> row) {
    Map<String, dynamic> extra = const {};
    final raw = row['extra']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          extra = decoded;
        } else if (decoded is Map) {
          extra = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    final verified = row['email_verified'];
    return AuthUser(
      id: row['id']?.toString() ?? '',
      email: row['email']?.toString(),
      name: row['name']?.toString(),
      passwordHash: row['password_hash']?.toString(),
      provider: row['provider']?.toString() ?? 'email',
      providerId: row['provider_id']?.toString(),
      emailVerified: verified == true ||
          verified == 1 ||
          verified?.toString() == '1' ||
          verified?.toString() == 'true',
      extra: extra,
    );
  }
}
