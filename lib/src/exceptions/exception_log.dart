import 'dart:collection';
import 'dart:io';

import '../http/quds_request.dart';

/// A captured application exception, ready to review later.
class QudsExceptionRecord {
  final String id;
  final DateTime time;
  final String method;
  final String path;
  final String ip;
  final String errorType;
  final String message;
  final String stackTrace;

  /// Per-exception `.txt` detail file (when [ExceptionLog.logToFile] is on).
  final String? detailFilePath;

  QudsExceptionRecord({
    required this.id,
    required this.time,
    required this.method,
    required this.path,
    required this.ip,
    required this.errorType,
    required this.message,
    required this.stackTrace,
    this.detailFilePath,
  });

  factory QudsExceptionRecord.capture(
    Object error,
    StackTrace stackTrace, [
    QudsRequest? request,
  ]) {
    return QudsExceptionRecord(
      id: 'ex_${DateTime.now().microsecondsSinceEpoch}',
      time: DateTime.now(),
      method: request?.method.toUpperCase() ?? '-',
      path: request?.pathAndQuery ?? '-',
      ip: request?.ip ?? '-',
      errorType: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stackTrace.toString(),
    );
  }

  /// One-line summary used in the terminal monitor.
  String get summary {
    final msg = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    return '$errorType: $msg';
  }

  Map<String, dynamic> toJson({bool includeStack = true}) {
    return {
      'id': id,
      'time': time.toUtc().toIso8601String(),
      'method': method,
      'path': path,
      'ip': ip,
      'errorType': errorType,
      'message': message,
      if (includeStack) 'stackTrace': stackTrace,
    };
  }
}

/// In-memory + file store for unhandled exceptions.
class ExceptionLog {
  static final Queue<QudsExceptionRecord> _records =
      Queue<QudsExceptionRecord>();
  static int _total = 0;

  /// How many exceptions to keep in memory for the live monitor.
  static int maxInMemory = 50;

  /// When true, each record is appended to [filePath].
  static bool logToFile = true;

  /// Default log file (Laravel-style). Override in tests or production.
  static String filePath = 'storage/logs/exceptions.log';

  /// Directory for one `.txt` file per exception (clickable in the monitor).
  static String detailDirectory = 'storage/logs/exceptions';

  static int get total => _total;

  static List<QudsExceptionRecord> get recent =>
      List<QudsExceptionRecord>.unmodifiable(_records);

  static void add(QudsExceptionRecord record) {
    _total++;
    String? detailPath;
    if (logToFile) {
      _appendToFile(record);
      detailPath = _writeDetailFile(record);
    }
    _records.addLast(
      detailPath == null
          ? record
          : QudsExceptionRecord(
              id: record.id,
              time: record.time,
              method: record.method,
              path: record.path,
              ip: record.ip,
              errorType: record.errorType,
              message: record.message,
              stackTrace: record.stackTrace,
              detailFilePath: detailPath,
            ),
    );
    while (_records.length > maxInMemory) {
      _records.removeFirst();
    }
  }

  static void clear() {
    _records.clear();
    _total = 0;
  }

  static String? _writeDetailFile(QudsExceptionRecord record) {
    try {
      final dir = Directory(detailDirectory);
      dir.createSync(recursive: true);
      final path =
          '${dir.path}${Platform.pathSeparator}${record.id}.txt';
      final file = File(path);
      final stamp = _formatStamp(record.time);
      final buffer = StringBuffer()
        ..writeln('[$stamp] ${record.method} ${record.path} from ${record.ip}')
        ..writeln(record.summary)
        ..writeln()
        ..writeln(record.stackTrace);
      file.writeAsStringSync(buffer.toString());
      return path;
    } catch (_) {
      return null;
    }
  }

  static void _appendToFile(QudsExceptionRecord record) {
    try {
      final file = File(filePath);
      file.parent.createSync(recursive: true);

      final stamp = _formatStamp(record.time);
      final buffer = StringBuffer()
        ..writeln(
          '[$stamp] ${record.method} ${record.path} from ${record.ip}',
        )
        ..writeln(record.summary)
        ..writeln(record.stackTrace)
        ..writeln('${'-' * 80}\n');

      file.writeAsStringSync(buffer.toString(), mode: FileMode.append);
    } catch (_) {
      // Logging must never crash the request.
    }
  }

  static String _formatStamp(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final mi = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }
}
