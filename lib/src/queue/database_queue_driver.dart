import 'dart:convert';

import 'package:quds_db_interface/quds_db_interface.dart';

import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'job.dart';
import 'job_registry.dart';
import 'queue_driver.dart';
import 'serializable_job.dart';

/// Persists [SerializableJob]s in a `quds_jobs` table.
///
/// Jobs stay reserved until [ack] (success) or [release] (retry / fail).
/// A crash mid-handle no longer deletes the row.
class DatabaseQueueDriver implements QueueDriver, QueueAcknowledgement, QueueInspect {
  final DatabaseConnection connection;
  final Duration reserveTimeout;
  bool _ensured = false;
  int _waiting = 0;
  int _reserved = 0;
  int _failed = 0;

  DatabaseQueueDriver(
    this.connection, {
    Duration? reserveTimeout,
  }) : reserveTimeout = reserveTimeout ??
            Duration(
              seconds: env<int>('QUEUE_RESERVE_TIMEOUT_SECONDS', 900) ?? 900,
            );

  Future<void> _ensureTable() async {
    if (_ensured) return;
    await connection.execute('''
CREATE TABLE IF NOT EXISTS quds_jobs (
  id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  available_at TEXT,
  created_at TEXT NOT NULL,
  reserved_at TEXT
)
''');
    await connection.execute('''
CREATE TABLE IF NOT EXISTS quds_failed_jobs (
  id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  error TEXT,
  failed_at TEXT NOT NULL
)
''');
    _ensured = true;
  }

  @override
  Future<void> push(Job job) async {
    await _ensureTable();
    if (job is! SerializableJob) {
      throw ArgumentError(
        'DatabaseQueueDriver only accepts SerializableJob instances. '
        'Got ${job.runtimeType}.',
      );
    }

    final id = job.id ??
        '${DateTime.now().microsecondsSinceEpoch}_${job.jobType}';
    job.id = id;

    await connection.execute('DELETE FROM quds_jobs WHERE id = ?', [id]);
    await connection.execute(
      '''
INSERT INTO quds_jobs (id, job_type, payload, attempts, available_at, created_at, reserved_at)
VALUES (?, ?, ?, ?, ?, ?, NULL)
''',
      [
        id,
        job.jobType,
        jsonEncode(job.toMap()),
        job.attempts,
        job.availableAt?.toUtc().toIso8601String(),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    _waiting++;
  }

  @override
  QueueSnapshot inspect() {
    return QueueSnapshot(
      waiting: _waiting,
      reserved: _reserved,
      failed: _failed,
    );
  }

  @override
  Future<Job?> pop() => _pop(retryOnRace: true);

  Future<Job?> _pop({required bool retryOnRace}) async {
    await _ensureTable();
    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    final staleIso = reserveTimeout.inSeconds > 0
        ? now.subtract(reserveTimeout).toIso8601String()
        : null;

    final reservedClause = staleIso == null
        ? 'reserved_at IS NULL'
        : '(reserved_at IS NULL OR reserved_at <= ?)';

    final params = <dynamic>[
      if (staleIso != null) staleIso,
      nowIso,
    ];

    final rows = await connection.query(
      '''
SELECT id, job_type, payload, attempts, available_at
FROM quds_jobs
WHERE $reservedClause
  AND (available_at IS NULL OR available_at <= ?)
ORDER BY created_at ASC
LIMIT 1
''',
      params,
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final id = row['id']?.toString() ?? '';
    final jobType = row['job_type']?.toString() ?? '';
    final payloadRaw = row['payload']?.toString() ?? '{}';
    final attempts = int.tryParse(row['attempts']?.toString() ?? '') ?? 0;

    final updated = await connection.execute(
      '''
UPDATE quds_jobs
SET reserved_at = ?
WHERE id = ? AND ($reservedClause)
''',
      [
        nowIso,
        id,
        if (staleIso != null) staleIso,
      ],
    );

    if (updated == 0) {
      final mine = await connection.query(
        'SELECT id FROM quds_jobs WHERE id = ? AND reserved_at = ?',
        [id, nowIso],
      );
      if (mine.isEmpty) {
        return retryOnRace ? _pop(retryOnRace: false) : null;
      }
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(payloadRaw);
      payload = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      payload = {};
    }

    final job = JobRegistry.create(jobType, payload);
    if (job == null) {
      Log.error(
        'Unknown job type [$jobType] for id=$id — moving to failed jobs',
      );
      await _failRow(id, jobType, payloadRaw, attempts, 'Unknown job type');
      if (_waiting > 0) _waiting--;
      return null;
    }

    job.id = id;
    job.attempts = attempts;
    if (row['available_at'] != null) {
      job.availableAt = DateTime.tryParse(row['available_at'].toString());
    }

    if (_waiting > 0) _waiting--;
    _reserved++;
    return job;
  }

  @override
  Future<void> ack(Job job) async {
    final id = job.id;
    if (id == null) return;
    await _ensureTable();
    await connection.execute('DELETE FROM quds_jobs WHERE id = ?', [id]);
    if (_reserved > 0) _reserved--;
  }

  @override
  Future<void> release(
    Job job, {
    required bool retry,
    Object? error,
  }) async {
    await _ensureTable();
    final id = job.id;
    if (id == null) return;

    if (retry) {
      await connection.execute(
        '''
UPDATE quds_jobs
SET reserved_at = NULL, attempts = ?, available_at = ?
WHERE id = ?
''',
        [
          job.attempts,
          job.availableAt?.toUtc().toIso8601String(),
          id,
        ],
      );
      if (_reserved > 0) _reserved--;
      _waiting++;
      return;
    }

    final jobType = job is SerializableJob ? job.jobType : job.runtimeType.toString();
    final payload = job is SerializableJob ? jsonEncode(job.toMap()) : '{}';
    await _failRow(id, jobType, payload, job.attempts, error?.toString());
  }

  Future<void> _failRow(
    String id,
    String jobType,
    String payload,
    int attempts,
    String? error,
  ) async {
    await connection.execute('DELETE FROM quds_failed_jobs WHERE id = ?', [id]);
    await connection.execute(
      '''
INSERT INTO quds_failed_jobs (id, job_type, payload, attempts, error, failed_at)
VALUES (?, ?, ?, ?, ?, ?)
''',
      [
        id,
        jobType,
        payload,
        attempts,
        error,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    await connection.execute('DELETE FROM quds_jobs WHERE id = ?', [id]);
    if (_reserved > 0) _reserved--;
    _failed++;
  }

  @override
  Future<bool> cancel(String id) async {
    await _ensureTable();
    final rows = await connection.query(
      'SELECT id FROM quds_jobs WHERE id = ? AND reserved_at IS NULL',
      [id],
    );
    if (rows.isEmpty) return false;
    await connection.execute('DELETE FROM quds_jobs WHERE id = ?', [id]);
    if (_waiting > 0) _waiting--;
    return true;
  }
}
