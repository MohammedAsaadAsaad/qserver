import 'dart:io';

import 'package:quds_db_interface/quds_db_interface.dart';

import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../logging/quds_log.dart';

/// Applies SQL files from `database/migrations/<id>/up.sql`.
///
/// Distinct from quds_db's Dart-first [MigrationRunner]; this tracks applied
/// ids in a `quds_migrations` table via raw [DatabaseConnection] SQL.
class FileMigrationRunner {
  final DatabaseConnection connection;
  final String migrationsPath;
  final String _lockOwner = 'qserver-$pid';

  FileMigrationRunner(
    this.connection, {
    this.migrationsPath = 'database/migrations',
  });

  /// Convenience using the container-bound connection.
  static FileMigrationRunner fromContainer({
    String migrationsPath = 'database/migrations',
  }) {
    return FileMigrationRunner(
      QudsContainer.resolve<DatabaseConnection>(),
      migrationsPath: migrationsPath,
    );
  }

  Future<void> _ensureTable() async {
    await connection.execute('''
CREATE TABLE IF NOT EXISTS quds_migrations (
  id TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
)
''');
  }

  Future<List<String>> _appliedIds() async {
    final rows = await connection.query(
      'SELECT id FROM quds_migrations ORDER BY id ASC',
    );
    return rows.map((r) => r['id']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
  }

  List<Directory> _migrationDirs() {
    final root = Directory(migrationsPath);
    if (!root.existsSync()) return [];
    final dirs = root
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return dirs;
  }

  String _migrationId(Directory dir) =>
      dir.path.split(Platform.pathSeparator).last;

  /// Applies all pending `up.sql` files in order.
  Future<int> migrate() => _withLock(_migrateUnlocked);

  Future<int> _migrateUnlocked() async {
    await _ensureTable();
    final applied = (await _appliedIds()).toSet();
    var count = 0;

    for (final dir in _migrationDirs()) {
      final id = _migrationId(dir);
      if (applied.contains(id)) continue;

      final up = File('${dir.path}${Platform.pathSeparator}up.sql');
      if (!up.existsSync()) {
        Log.warning('Skipping migration [$id]: missing up.sql');
        continue;
      }

      final sql = await up.readAsString();
      await _runStatements(sql);
      await connection.execute(
        'INSERT INTO quds_migrations (id, applied_at) VALUES (?, ?)',
        [id, DateTime.now().toUtc().toIso8601String()],
      );
      Log.info('Migrated: $id');
      count++;
    }

    if (count == 0) {
      Log.info('No pending migrations.');
    }
    return count;
  }

  /// Rolls back the last applied migration using `down.sql` when present.
  Future<bool> rollback() => _withLock(_rollbackUnlocked);

  Future<bool> _rollbackUnlocked() async {
    await _ensureTable();
    final applied = await _appliedIds();
    if (applied.isEmpty) {
      Log.info('Nothing to roll back.');
      return false;
    }

    final id = applied.last;
    final dir = Directory(
      '$migrationsPath${Platform.pathSeparator}$id',
    );
    final down = File('${dir.path}${Platform.pathSeparator}down.sql');
    if (down.existsSync()) {
      await _runStatements(await down.readAsString());
    } else {
      Log.warning('Rollback [$id]: no down.sql — removing journal entry only');
    }

    await connection.execute(
      'DELETE FROM quds_migrations WHERE id = ?',
      [id],
    );
    Log.info('Rolled back: $id');
    return true;
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final acquired = await _acquireLock();
    if (!acquired) {
      throw StateError(
        'Could not acquire migration lock. Another process may be migrating.',
      );
    }
    try {
      return await action();
    } finally {
      await _releaseLock();
    }
  }

  Future<void> _ensureLockTable() async {
    await connection.execute('''
CREATE TABLE IF NOT EXISTS quds_migration_lock (
  lock_id TEXT PRIMARY KEY,
  owner TEXT NOT NULL,
  locked_at TEXT NOT NULL
)
''');
  }

  Duration get _lockWait => Duration(
        seconds: env<int>('MIGRATE_LOCK_SECONDS', 30) ?? 30,
      );

  Duration get _lockTtl => const Duration(minutes: 10);

  Future<bool> _acquireLock() async {
    await _ensureLockTable();
    final deadline = DateTime.now().add(_lockWait);

    while (true) {
      await _deleteStaleLocks();
      try {
        await connection.execute(
          '''
INSERT INTO quds_migration_lock (lock_id, owner, locked_at)
VALUES (?, ?, ?)
''',
          [
            'default',
            _lockOwner,
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
        return true;
      } catch (_) {
        if (DateTime.now().isAfter(deadline)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  Future<void> _deleteStaleLocks() async {
    final cutoff =
        DateTime.now().toUtc().subtract(_lockTtl).toIso8601String();
    await connection.execute(
      'DELETE FROM quds_migration_lock WHERE locked_at < ?',
      [cutoff],
    );
  }

  Future<void> _releaseLock() async {
    try {
      await connection.execute(
        'DELETE FROM quds_migration_lock WHERE lock_id = ? AND owner = ?',
        ['default', _lockOwner],
      );
    } catch (e) {
      Log.debug('Migration lock release: $e');
    }
  }

  Future<void> _runStatements(String sql) async {
    final parts = _splitSql(sql);
    for (final statement in parts) {
      if (statement.trim().isEmpty) continue;
      await connection.execute(statement);
    }
  }

  /// Splits on `;` outside of simple quotes (good enough for migration files).
  static List<String> _splitSql(String sql) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inSingle = false;
    var inDouble = false;

    for (var i = 0; i < sql.length; i++) {
      final c = sql[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
        buffer.write(c);
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
        buffer.write(c);
      } else if (c == ';' && !inSingle && !inDouble) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }
}
