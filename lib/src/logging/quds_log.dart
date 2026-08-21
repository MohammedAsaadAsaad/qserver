import 'dart:collection';
import 'dart:io';

import '../container/quds_env.dart';
import 'log_spinner.dart';

enum LogLevel { debug, info, warning, error }

/// Structured console logger with optional slow-query reporting.
class Log {
  static LogLevel minLevel = LogLevel.info;
  static Duration slowQueryThreshold = const Duration(milliseconds: 500);
  static void Function(String label, Duration elapsed)? onSlowQuery;

  /// `true` / `false` forces ANSI color. `null` follows the TTY.
  static bool? color;

  /// Override destination (tests). Defaults to [stdout].
  static void Function(String line)? writer;

  /// When this returns true, the line is not written to [writer] / stdout.
  /// Used by [ServerMonitor] so the live panel can own the terminal.
  static bool Function(String line, Duration? elapsed)? intercept;

  /// Force the file sink on/off. `null` follows [QUDS_LOG_FILE] / monitor.
  static bool? fileSink;

  /// Default file when the sink is on and [QUDS_LOG_FILE] is not a path.
  static String filePath = 'storage/logs/app.log';

  /// Called around a write so [LogSpinner] can lift/restore its line.
  static void Function()? beforeWrite;
  static void Function()? afterWrite;

  static const int maxRecent = 40;
  static final Queue<String> recent = Queue<String>();

  static bool _bootstrapped = false;

  static const String _reset = '\x1B[0m';
  static const String _dim = '\x1B[2m';
  static const String _bold = '\x1B[1m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _yellow = '\x1B[33m';
  static const String _red = '\x1B[31m';

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

  static bool get _useColor {
    if (color != null) return color!;
    try {
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } catch (_) {
      return false;
    }
  }

  static void debug(String message, {String? component, Duration? elapsed}) =>
      _write(LogLevel.debug, message, component: component, elapsed: elapsed);
  static void info(String message, {String? component, Duration? elapsed}) =>
      _write(LogLevel.info, message, component: component, elapsed: elapsed);
  static void warning(String message, {String? component, Duration? elapsed}) =>
      _write(LogLevel.warning, message, component: component, elapsed: elapsed);
  static void error(String message, {String? component, Duration? elapsed}) =>
      _write(LogLevel.error, message, component: component, elapsed: elapsed);

  /// Startup / pre-listen step. Same as [info] with `component: boot`.
  static void boot(String message) =>
      _write(LogLevel.info, message, component: 'boot');

  /// Starts a preloader for [label]. Call [LogSpinner.succeed] / [fail] when done.
  static LogSpinner spinner(String label, {String component = 'queue'}) {
    return LogSpinner.start(label, component: component);
  }

  /// Runs [action] under a preloader and logs ✓ / ✗ when it finishes.
  static Future<T> withSpinner<T>(
    String label,
    Future<T> Function() action, {
    String component = 'queue',
  }) async {
    final spin = LogSpinner.start(label, component: component);
    try {
      final result = await action();
      spin.succeed();
      return result;
    } catch (e) {
      spin.fail(e);
      rethrow;
    }
  }

  /// Runs [action], logging start and a timed result on the [component] channel.
  static Future<T> step<T>(
    String label,
    Future<T> Function() action, {
    String component = 'boot',
  }) async {
    info(label, component: component);
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      info('$label · ${sw.elapsedMilliseconds}ms', component: component);
      return result;
    } catch (e) {
      error('$label failed · ${sw.elapsedMilliseconds}ms: $e',
          component: component);
      rethrow;
    }
  }

  /// Records a timed query/operation and warns when slower than [slowQueryThreshold].
  static void recordQuery(String label, Duration elapsed) {
    if (elapsed >= slowQueryThreshold) {
      onSlowQuery?.call(label, elapsed);
      warning('Slow query (${elapsed.inMilliseconds}ms): $label',
          component: 'db');
    } else {
      debug('Query (${elapsed.inMilliseconds}ms): $label', component: 'db');
    }
  }

  static String formatElapsed(Duration elapsed) {
    if (elapsed.inMilliseconds < 1000) return '${elapsed.inMilliseconds}ms';
    return '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  static String format(
    LogLevel level,
    String message, {
    String? component,
    DateTime? time,
    bool? colored,
    Duration? elapsed,
  }) {
    final useColor = colored ?? _useColor;
    final ts = _timestamp(time ?? DateTime.now());
    final tag = _levelTag(level);
    final scope = (component ?? 'app').padRight(8);
    final dur = elapsed == null ? '' : '  ${formatElapsed(elapsed)}';
    if (!useColor) {
      return '$ts  $tag  $scope  $message$dur';
    }
    return '$_gray$ts$_reset  ${_levelColor(level)}$_bold$tag$_reset  '
        '$_dim$scope$_reset  $message$dur';
  }

  static void _write(
    LogLevel level,
    String message, {
    String? component,
    Duration? elapsed,
  }) {
    _ensureBootstrapped();
    if (level.index < minLevel.index) return;

    final line = format(level, message, component: component);
    recent.add(elapsed == null ? line : format(level, message, component: component, elapsed: elapsed));
    while (recent.length > maxRecent) {
      recent.removeFirst();
    }

    beforeWrite?.call();
    try {
      _appendFile(
        format(
          level,
          message,
          component: component,
          colored: false,
          elapsed: elapsed,
        ),
      );
      if (intercept != null && intercept!(line, elapsed)) return;
      (writer ?? stdout.writeln)(
        elapsed == null
            ? line
            : format(level, message, component: component, elapsed: elapsed),
      );
    } finally {
      afterWrite?.call();
    }
  }

  static bool get _fileSinkEnabled {
    if (fileSink == false) return false;
    if (fileSink == true) return true;
    final raw = env<String>('QUDS_LOG_FILE');
    if (raw == null || raw.isEmpty) return intercept != null;
    final lower = raw.toLowerCase();
    return lower != 'false' && lower != '0';
  }

  static String _resolvedFilePath() {
    final raw = env<String>('QUDS_LOG_FILE');
    if (raw != null &&
        raw.isNotEmpty &&
        raw.toLowerCase() != 'true' &&
        raw != '1' &&
        raw.toLowerCase() != 'false' &&
        raw != '0') {
      return raw;
    }
    return filePath;
  }

  static void _appendFile(String line) {
    if (!_fileSinkEnabled) return;
    try {
      final file = File(_resolvedFilePath());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  static String _timestamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${three(time.millisecond)}';
  }

  static String _levelTag(LogLevel level) {
    return switch (level) {
      LogLevel.debug => 'DEBUG',
      LogLevel.info => 'INFO ',
      LogLevel.warning => 'WARN ',
      LogLevel.error => 'ERROR',
    };
  }

  static String _levelColor(LogLevel level) {
    return switch (level) {
      LogLevel.debug => _gray,
      LogLevel.info => _cyan,
      LogLevel.warning => _yellow,
      LogLevel.error => _red,
    };
  }

  static void reset() {
    LogSpinner.active?.stop();
    LogSpinner.enabled = null;
    minLevel = LogLevel.info;
    color = null;
    writer = null;
    intercept = null;
    fileSink = null;
    beforeWrite = null;
    afterWrite = null;
    recent.clear();
    _bootstrapped = false;
    onSlowQuery = null;
  }
}
