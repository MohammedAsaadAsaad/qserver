import '../container/quds_env.dart';

enum LogLevel { debug, info, warning, error }

/// Structured console logger with optional slow-query reporting.
class Log {
  static LogLevel minLevel = LogLevel.info;
  static Duration slowQueryThreshold = const Duration(milliseconds: 500);
  static void Function(String label, Duration elapsed)? onSlowQuery;

  static bool _bootstrapped = false;

  static void _ensureBootstrapped() {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final raw = (env<String>('LOG_LEVEL', 'info') ?? 'info').toLowerCase();
    minLevel = switch (raw) {
      'debug' => LogLevel.debug,
      'warning' || 'warn' => LogLevel.warning,
      'error' => LogLevel.error,
      _ => LogLevel.info,
    };
  }

  static void debug(String message) => _write(LogLevel.debug, message);
  static void info(String message) => _write(LogLevel.info, message);
  static void warning(String message) => _write(LogLevel.warning, message);
  static void error(String message) => _write(LogLevel.error, message);

  /// Records a timed query/operation and warns when slower than [slowQueryThreshold].
  static void recordQuery(String label, Duration elapsed) {
    if (elapsed >= slowQueryThreshold) {
      onSlowQuery?.call(label, elapsed);
      warning('Slow query (${elapsed.inMilliseconds}ms): $label');
    } else {
      debug('Query (${elapsed.inMilliseconds}ms): $label');
    }
  }

  static void _write(LogLevel level, String message) {
    _ensureBootstrapped();
    if (level.index < minLevel.index) return;

    final ts = DateTime.now().toIso8601String();
    final tag = level.name.toUpperCase().padRight(7);
    print('[$ts] $tag $message');
  }
}
