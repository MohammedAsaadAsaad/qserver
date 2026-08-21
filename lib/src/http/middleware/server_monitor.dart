import 'dart:async';
import 'dart:collection';
import 'dart:io';
import '../quds_request.dart';
import '../quds_response.dart';
import '../../broadcasting/broadcast_manager.dart';
import '../../container/quds_container.dart';
import '../../container/quds_env.dart';
import '../../exceptions/exception_log.dart';
import '../../logging/log_spinner.dart';
import '../../logging/quds_log.dart';
import '../../queue/queue_runtime.dart';

class ServerMonitor {
  static const int _defaultWidth = 76;
  static const int _eventRing = 200;
  static const int _trafficRows = 8;
  static const int _errorRows = 3;
  static const int _defaultEventRows = 14;
  static const int _maxJobRows = 4;

  /// Set to false in tests so the dashboard does not take over the terminal.
  static bool enabled = true;

  static final DateTime _startTime = DateTime.now();
  static int _totalRequests = 0;
  static int _successCount = 0;
  static int _clientErrorCount = 0;
  static int _serverErrorCount = 0;

  static final Queue<String> _recentRequests = Queue<String>();
  static final Queue<int> _responseTimes = Queue<int>();
  static final Queue<_EventRow> _events = Queue<_EventRow>();
  static final Queue<DateTime> _requestAt = Queue<DateTime>();

  static String? jobIndicator;
  static String? jobDuration;
  static String? listenHint;

  static bool _live = false;
  static bool _altScreen = false;
  static bool _drawPending = false;
  static bool _noTtyHinted = false;

  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _green = '\x1B[32m';
  static const String _red = '\x1B[31m';
  static const String _yellow = '\x1B[33m';
  static const String _bold = '\x1B[1m';
  static const String _dim = '\x1B[2m';

  static int get totalRequests => _totalRequests;
  static int get successCount => _successCount;
  static int get clientErrorCount => _clientErrorCount;
  static int get serverErrorCount => _serverErrorCount;

  static int get _contentWidth {
    try {
      if (stdout.hasTerminal) {
        return (stdout.terminalColumns - 4).clamp(60, 140);
      }
    } catch (_) {}
    return _defaultWidth;
  }

  static int get _eventRows {
    try {
      if (stdout.hasTerminal) {
        return (stdout.terminalLines - 34).clamp(8, 36);
      }
    } catch (_) {}
    return _defaultEventRows;
  }

  static bool get isLive => _live;

  /// True when the in-place panel is actually writing to the terminal.
  static bool get isDrawing => enabled && _live && _shouldDrawTui();

  /// Live frame is on by default. Set `QUDS_MONITOR=false` to keep line logs.
  static bool get monitorEnabled => env<bool>('QUDS_MONITOR', true) ?? true;

  static bool _hasTty() {
    try {
      return stdout.hasTerminal;
    } catch (_) {
      return false;
    }
  }

  static bool _shouldDrawTui() {
    if (!monitorEnabled) return false;
    // The box needs a real TTY (not VS Code Debug Console / CI pipes).
    return _hasTty();
  }

  static void _hintIfNoTty() {
    if (_noTtyHinted || !enabled || !monitorEnabled || _hasTty()) return;
    if (!isLocalEnvironment()) return;
    _noTtyHinted = true;
    Log.info(
      'Live monitor is on (default). This process has no TTY so logs stay '
      'as lines. Run from a terminal or set launch.json '
      '"console": "integratedTerminal". QUDS_MONITOR=false turns the frame off.',
      component: 'boot',
    );
  }

  /// Opens the framed logger as soon as the terminal can host it.
  ///
  /// Call at the start of boot so logs never print outside the box.
  static void attach() {
    if (_live) return;
    if (!enabled || !_shouldDrawTui()) {
      _hintIfNoTty();
      return;
    }

    _live = true;
    _events.clear();
    for (final line in Log.recent) {
      _pushEvent(line);
    }
    Log.intercept = capture;
    LogSpinner.onTick = (text, duration) {
      jobIndicator = text;
      jobDuration = duration;
      _scheduleDraw();
    };

    stdout.write('\x1B[?1049h\x1B[?25l\x1B[H');
    _altScreen = true;
    _drawDashboard();
  }

  /// Alias kept for existing callers.
  static void goLive() => attach();

  /// Releases the terminal so shutdown logs can append normally.
  static void endLive() {
    if (!_live && !_altScreen) return;
    _live = false;
    Log.intercept = null;
    LogSpinner.onTick = null;
    jobIndicator = null;
    jobDuration = null;
    if (_altScreen) {
      stdout.write('\x1B[?25h\x1B[?1049l');
      _altScreen = false;
    } else {
      cleanup();
    }
    _noTtyHinted = false;
  }

  /// When the panel is drawing, keep the line inside the log pane.
  static bool capture(String line, [Duration? elapsed]) {
    if (!isDrawing) return false;
    _pushEvent(line, elapsed);
    _scheduleDraw();
    return true;
  }

  static void _pushEvent(String line, [Duration? elapsed]) {
    if (_events.length >= _eventRing) _events.removeFirst();
    final parsed = _splitDuration(line);
    final duration = elapsed != null
        ? Log.formatElapsed(elapsed)
        : parsed.duration;
    _events.add(_EventRow(parsed.text, duration));
  }

  static void _scheduleDraw() {
    if (_drawPending || !isDrawing) return;
    _drawPending = true;
    scheduleMicrotask(() {
      _drawPending = false;
      _drawDashboard();
    });
  }

  /// Logs a new request, updates stats, and redraws the dashboard
  static void log(QudsRequest request, QudsResponse response, int timeMs) {
    _totalRequests++;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _successCount++;
    } else if (response.statusCode >= 400 && response.statusCode < 500) {
      _clientErrorCount++;
    } else if (response.statusCode >= 500) {
      _serverErrorCount++;
    }

    if (_responseTimes.length >= 30) _responseTimes.removeFirst();
    _responseTimes.add(timeMs);
    final now = DateTime.now();
    _requestAt.add(now);
    while (_requestAt.isNotEmpty &&
        now.difference(_requestAt.first) > const Duration(seconds: 5)) {
      _requestAt.removeFirst();
    }

    final timeOfDay = _hhmmss(now);
    final color = _getStatusColor(response.statusCode);
    final methodStr = request.method.toUpperCase().padRight(6);
    final pathStr = _fit(request.pathAndQuery, 26);
    final durationColor =
        timeMs >= 1000 ? _red : (timeMs >= 300 ? _yellow : '');
    final timeStr = '${timeMs}ms'.padLeft(8);
    final ipStr = _fit(request.ip, 14);

    final logLine =
        '$_gray$timeOfDay$_reset $color[${response.statusCode}]$_reset $methodStr $pathStr $_gray$ipStr$_reset $durationColor$timeStr$_reset';

    if (_recentRequests.length >= _trafficRows) _recentRequests.removeFirst();
    _recentRequests.add(logLine);

    _scheduleDraw();
  }

  /// Redraws the dashboard without adding a request (used after exceptions).
  static void refresh() {
    _scheduleDraw();
  }

  static String _getUptime() {
    final diff = DateTime.now().difference(_startTime);
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _hhmmss(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _fit(String value, int width) {
    if (value.length > width) {
      if (width <= 3) return value.substring(0, width);
      return '${value.substring(0, width - 3)}...';
    }
    return value.padRight(width);
  }

  static List<(String, String)> _jobRows() {
    final live = QueueRuntime.running;
    if (live.isEmpty) {
      if (jobIndicator == null) return const [];
      return [(jobIndicator!, jobDuration ?? '')];
    }
    if (live.length == 1 && jobIndicator != null) {
      return [(jobIndicator!, jobDuration ?? Log.formatElapsed(live.first.elapsed))];
    }
    return live
        .take(_maxJobRows)
        .map((j) => (j.label, Log.formatElapsed(j.elapsed)))
        .toList();
  }

  static List<_EventRow> _visibleEvents() {
    final filter =
        (env<String>('QUDS_MONITOR_LOG', 'all') ?? 'all').toLowerCase();
    Iterable<_EventRow> items = _events;
    if (filter == 'error' || filter == 'errors') {
      items = items.where((e) {
        final t = e.text;
        return t.contains('ERROR') || t.contains('WARN');
      });
    } else if (filter != 'all') {
      items = items.where((e) => e.text.toLowerCase().contains(filter));
    }
    final list = items.toList();
    if (list.length <= _eventRows) return list;
    return list.sublist(list.length - _eventRows);
  }

  static String _withDuration(String text, String duration) {
    const durWidth = 8;
    final bodyWidth = _contentWidth - durWidth - 1;
    final dur = duration.isEmpty ? ' ' * durWidth : duration.padLeft(durWidth);
    return '${_padToWidth(text, bodyWidth)} $dur';
  }

  static ({String text, String duration}) _splitDuration(String raw) {
    final plain = stripAnsi(raw);
    final match = RegExp(
      r'(?:·\s*)?(\d+(?:\.\d+)?(?:ms|s)|\(\d+ms\))\s*$',
    ).firstMatch(plain);
    if (match == null) return (text: raw, duration: '');
    var dur = match.group(1)!;
    if (dur.startsWith('(') && dur.endsWith(')')) {
      dur = dur.substring(1, dur.length - 1);
    }
    final cut = match.start;
    final text = raw.length == plain.length
        ? raw.substring(0, cut).trimRight()
        : plain.substring(0, cut).trimRight();
    return (text: text, duration: dur);
  }

  static String _pressureRow() {
    final load = (_requestAt.length / 20).clamp(0.0, 1.0);
    final avgMs = _responseTimes.isEmpty
        ? 0.0
        : _responseTimes.reduce((a, b) => a + b) / _responseTimes.length;
    final lat = (avgMs / 800).clamp(0.0, 1.0);
    final faults = _clientErrorCount + _serverErrorCount + ExceptionLog.total;
    final err = _totalRequests == 0
        ? 0.0
        : (faults / _totalRequests).clamp(0.0, 1.0);
    final rss = ProcessInfo.currentRss / (512 * 1024 * 1024);
    final mem = rss.clamp(0.0, 1.0);
    final q = QueueRuntime.snapshot();
    final qLoad = ((q.waiting + q.running) / 20).clamp(0.0, 1.0);
    final ws = (_wsCount() / 50).clamp(0.0, 1.0);
    return '${_bar('LOAD', load)}  ${_bar('LAT', lat)}  ${_bar('ERR', err)}  '
        '${_bar('MEM', mem)}  ${_bar('Q', qLoad)}  ${_bar('WS', ws)}';
  }

  static int _wsCount() {
    try {
      if (QudsContainer.isRegistered<BroadcastManager>()) {
        return QudsContainer.resolve<BroadcastManager>().activeConnectionsCount;
      }
    } catch (_) {}
    return 0;
  }

  static String _bar(String label, double ratio) {
    const width = 6;
    final filled = (ratio * width).round().clamp(0, width);
    final color = ratio >= 0.8 ? _red : (ratio >= 0.5 ? _yellow : _green);
    final blocks = '$color${'█' * filled}$_dim${'░' * (width - filled)}$_reset';
    return '$_dim$label$_reset $blocks';
  }

  static void _line(StringBuffer out, String content) {
    out.writeln('│ ${_padToWidth(content, _contentWidth)} │');
  }

  static String _padToWidth(String content, int width) {
    final plain = stripAnsi(content);
    if (plain.length == width) return content;
    if (plain.length < width) {
      return '$content${' ' * (width - plain.length)}';
    }
    return '${plain.substring(0, width - 3)}...';
  }

  static String stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  static String _border(String left, String fill, String right) {
    return '$_cyan$left${fill * (_contentWidth + 2)}$right$_reset';
  }

  /// Overwrites the panel in place. Does not clear scrollback (alt screen).
  static void _drawDashboard() {
    if (!isDrawing) return;

    final out = StringBuffer();
    out.write('\x1B[H\x1B[?25l');

    final topBorder = _border('┌', '─', '┐');
    final midBorder = _border('├', '─', '┤');
    final botBorder = _border('└', '─', '┘');

    out.writeln(topBorder);

    final appName = env<String>('APP_NAME') ?? 'Quds Server';
    final appEnv = env<String>('APP_ENV', 'local') ?? 'local';
    final titleText = '$_bold$appName$_reset';
    final right = '$_dim$appEnv$_reset  ${_getUptime()}';
    final spaces = (_contentWidth -
            stripAnsi(titleText).length -
            stripAnsi(right).length)
        .clamp(0, _contentWidth);
    _line(out, '$titleText${' ' * spaces}$right');
    _line(out, _pressureRow());

    final bind = listenHint ?? 'starting…';
    _line(out, '$_dim$bind$_reset');

    out.writeln(midBorder);

    final totalStr = _totalRequests.toString();
    final successStr = _successCount.toString();
    final clientErrStr = _clientErrorCount.toString();
    final serverErrStr = _serverErrorCount.toString();
    final exceptionStr = ExceptionLog.total.toString();
    final exColor = ExceptionLog.total > 0 ? _red : _gray;
    final stats =
        '${_dim}req$_reset $totalStr  ${_green}2xx$_reset $successStr  '
        '${_yellow}4xx$_reset $clientErrStr  ${_red}5xx$_reset $serverErrStr  '
        '${exColor}ex$_reset $exceptionStr';
    _line(out, stats);

    final q = QueueRuntime.snapshot();
    _line(
      out,
      '${_dim}wait$_reset ${q.waiting}  ${_cyan}run$_reset ${q.running}  '
      '${_dim}delay$_reset ${q.delayed}  ${_yellow}retry$_reset ${q.retries}  '
      '${q.failed > 0 ? _red : _dim}dead$_reset ${q.failed}',
    );
    final jobs = _jobRows();
    if (jobs.isEmpty) {
      _line(out, _withDuration('${_bold}job$_reset   ${_dim}idle$_reset', ''));
    } else {
      for (final job in jobs) {
        _line(
          out,
          _withDuration('${_bold}job$_reset   $_cyan${job.$1}$_reset', job.$2),
        );
      }
    }

    out.writeln(midBorder);
    _line(out, '${_bold}Traffic$_reset');
    _line(
      out,
      '$_dim${_fit('Time', 8)} ${_fit('Code', 5)} ${_fit('Method', 6)} ${_fit('Path', 26)} ${_fit('Client', 14)} ${_fit('Dur', 8)}$_reset',
    );

    for (var log in _recentRequests) {
      _line(out, log);
    }
    for (int i = _recentRequests.length; i < _trafficRows; i++) {
      _line(out, '');
    }

    out.writeln(midBorder);
    _line(out, '${_bold}Exceptions$_reset');
    final errors = ExceptionLog.recent;
    final start = errors.length > _errorRows ? errors.length - _errorRows : 0;
    final visible = errors.sublist(start);

    if (visible.isEmpty) {
      _line(out, '${_dim}None$_reset');
      for (int i = 1; i < _errorRows; i++) {
        _line(out, '');
      }
    } else {
      for (final record in visible) {
        final time = _hhmmss(record.time);
        final method = record.method.padRight(6);
        final path = _fit(record.path, 22);
        final remaining = _contentWidth - (8 + 1 + 6 + 1 + 22 + 1);
        final summary = _fit(record.summary, remaining);
        _line(out, '$_red$time$_reset $method $path $summary');
      }
      for (int i = visible.length; i < _errorRows; i++) {
        _line(out, '');
      }
    }

    out.writeln(midBorder);
    _line(out, _withDuration('${_bold}Log$_reset', '${_dim}Dur$_reset'));
    final logRows = _visibleEvents();
    if (logRows.isEmpty) {
      _line(out, _withDuration('${_dim}Waiting for boot…$_reset', ''));
      for (int i = 1; i < _eventRows; i++) {
        _line(out, '');
      }
    } else {
      for (final event in logRows) {
        _line(out, _withDuration(event.text, event.duration));
      }
      for (int i = logRows.length; i < _eventRows; i++) {
        _line(out, '');
      }
    }

    out.writeln(botBorder);
    out.write('\x1B[J');
    stdout.write(out.toString());
  }

  static String _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return _green;
    if (statusCode >= 300 && statusCode < 400) return _yellow;
    if (statusCode >= 400 && statusCode < 500) return '\x1B[35m';
    return _red;
  }

  /// Restores terminal state when shutting down
  static void cleanup() {
    stdout.write('\x1B[?25h');
  }
}

class _EventRow {
  final String text;
  final String duration;

  _EventRow(this.text, this.duration);
}
