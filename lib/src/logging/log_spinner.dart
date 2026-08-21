import 'dart:async';
import 'dart:io';

import 'quds_log.dart';

/// In-place preloader for long work (queue jobs, migrations, …).
///
/// On a TTY it rewrites one line (`⠋ JobName`). When the live monitor owns
/// the terminal, ticks go to [onTick] instead so the panel does not flicker.
/// Piped/CI output only gets the final success/fail line.
class LogSpinner {
  static const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  /// `true` / `false` forces the animation. `null` follows the TTY.
  static bool? enabled;

  /// Notified each frame with label and duration, or both `null` when idle.
  static void Function(String? text, String? duration)? onTick;

  static LogSpinner? active;

  final String label;
  final String component;
  final Stopwatch _sw = Stopwatch()..start();
  Timer? _timer;
  int _i = 0;
  bool _done = false;
  int _width = 0;

  LogSpinner._(this.label, this.component);

  static LogSpinner start(String label, {String component = 'queue'}) {
    active?.stop();
    final spinner = LogSpinner._(label, component);
    active = spinner;
    spinner._begin();
    return spinner;
  }

  bool get _inline {
    if (Log.writer != null) return false;
    if (Log.intercept != null) return false;
    if (enabled == false) return false;
    if (enabled == true) return true;
    try {
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } catch (_) {
      return false;
    }
  }

  bool get _animate => !_done && (_inline || onTick != null);

  void _begin() {
    Log.beforeWrite = lift;
    Log.afterWrite = drop;
    if (_animate) {
      _paint();
      _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (_done) return;
        _i = (_i + 1) % frames.length;
        _paint();
      });
    }
  }

  void lift() {
    if (_done || !_inline) return;
    stdout.write('\r\x1B[2K');
  }

  void drop() {
    if (_done || !_inline) return;
    _paint();
  }

  void _paint() {
    final text = '${frames[_i]} $label';
    onTick?.call(text, _elapsed(_sw.elapsed));
    if (!_inline) return;
    final line = Log.format(
      LogLevel.info,
      text,
      component: component,
    );
    final padded = line.padRight(_width);
    if (padded.length > _width) _width = padded.length;
    stdout.write('\x1B[?25l\r$padded');
  }

  void succeed([String? detail]) {
    _finish(ok: true, message: detail ?? label);
  }

  void fail(Object error, {String? detail}) {
    _finish(
      ok: false,
      message: detail == null ? '$label — $error' : '$label — $detail',
    );
  }

  /// Stops the animation without writing a result line.
  void stop() => _finish(ok: true, message: null);

  void _finish({required bool ok, String? message}) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    _timer = null;
    lift();
    if (active == this) {
      active = null;
      Log.beforeWrite = null;
      Log.afterWrite = null;
    }
    onTick?.call(null, null);
    if (_inline) {
      stdout.write('\x1B[?25h');
    }
    if (message == null) return;
    final mark = _mark(ok);
    if (ok) {
      Log.info('$mark $message', component: component, elapsed: _sw.elapsed);
    } else {
      Log.error('$mark $message', component: component, elapsed: _sw.elapsed);
    }
  }

  String _mark(bool ok) {
    final fancy = enabled == true || _inline || Log.intercept != null;
    if (fancy) return ok ? '✓' : '✗';
    return ok ? '+' : 'x';
  }

  static String _elapsed(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
}
