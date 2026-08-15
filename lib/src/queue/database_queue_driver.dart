import 'dart:convert';

import 'package:quds_db_interface/quds_db_interface.dart';

import '../logging/quds_log.dart';
import 'job.dart';
import 'job_registry.dart';
import 'queue_driver.dart';
import 'serializable_job.dart';

/// Persists [SerializableJob]s in a `quds_jobs` table.
class DatabaseQueueDriver implements QueueDriver {
  final DatabaseConnection connection;
  bool _ensured = false;

  DatabaseQueueDriver(this.connection);

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
  }

  @override
  Future<Job?> pop() async {
    await _ensureTable();
    final now = DateTime.now().toUtc().toIso8601String();

    final rows = await connection.query(
      '''
SELECT id, job_type, payload, attempts, available_at
FROM quds_jobs
WHERE reserved_at IS NULL
  AND (available_at IS NULL OR available_at <= ?)
ORDER BY created_at ASC
LIMIT 1
''',
      [now],
    );

    if (rows.isEmpty) return null;

    final row = rows.first;
    final id = row['id']?.toString() ?? '';
    final jobType = row['job_type']?.toString() ?? '';
    final payloadRaw = row['payload']?.toString() ?? '{}';
    final attempts = int.tryParse(row['attempts']?.toString() ?? '') ?? 0;

    await connection.execute(
      'UPDATE quds_jobs SET reserved_at = ? WHERE id = ?',
      [now, id],
    );

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
        'Unknown job type [$jobType] for id=$id — deleting orphan row',
      );
      await connection.execute('DELETE FROM quds_jobs WHERE id = ?', [id]);
      return null;
    }

    job.id = id;
    job.attempts = attempts;
    if (row['available_at'] != null) {
      job.availableAt = DateTime.tryParse(row['available_at'].toString());
    }

    // After successful handle the worker does not call back; delete on pop
    // ownership transfer — worker retries via push which re-inserts.
    // Soft-delete after pop so retries can re-push; mark completed by delete
    // once we know handle succeeded. Defer delete until after handle via
    // wrapping — simplest: delete reserved row now; retry push inserts again.
    await connection.execute('DELETE FROM quds_jobs WHERE id = ?', [id]);

    return job;
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
    return true;
  }
}
