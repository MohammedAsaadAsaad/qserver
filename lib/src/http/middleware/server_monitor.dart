import 'dart:collection';
import 'dart:io';
import '../quds_request.dart';
import '../quds_response.dart';
import '../../container/quds_env.dart';
import '../../exceptions/exception_log.dart';

class ServerMonitor {
  static const int _contentWidth = 76;
  static const int _trafficRows = 10;
  static const int _errorRows = 5;

  /// Set to false in tests so the dashboard does not clear the terminal.
  static bool enabled = true;

  static final DateTime _startTime = DateTime.now();
  static int _totalRequests = 0;
  static int _successCount = 0;
  static int _clientErrorCount = 0;
  static int _serverErrorCount = 0;

  // Keep track of the last 10 requests for the live feed
  static final Queue<String> _recentRequests = Queue<String>();

  // Keep track of the last 30 response times for the sparkline chart
  static final Queue<int> _responseTimes = Queue<int>();

  // Unicode block characters for the chart (from lowest to highest)
  static const List<String> _sparklines = [
    ' ',
    '▂',
    '▃',
    '▄',
    '▅',
    '▆',
    '▇',
    '█',
  ];

  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _green = '\x1B[32m';
  static const String _red = '\x1B[31m';
  static const String _yellow = '\x1B[33m';
  static const String _bold = '\x1B[1m';
  static const String _dim = '\x1B[2m';

  /// Logs a new request, updates stats, and redraws the dashboard
  static void log(QudsRequest request, QudsResponse response, int timeMs) {
    _totalRequests++;

    // 1. Update Categorized Stats
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _successCount++;
    } else if (response.statusCode >= 400 && response.statusCode < 500) {
      _clientErrorCount++;
    } else if (response.statusCode >= 500) {
      _serverErrorCount++;
    }

    // 2. Update Sparkline Data
    if (_responseTimes.length >= 30) _responseTimes.removeFirst();
    _responseTimes.add(timeMs);

    // 3. Format the log line: time + status + method + path + duration + ip
    // Plain width: 8+1+5+1+6+1+30+1+7+1+15 = 76
    final timeOfDay = _hhmmss(DateTime.now());
    final color = _getStatusColor(response.statusCode);
    final methodStr = request.method.toUpperCase().padRight(6);
    final pathStr = _fit(request.pathAndQuery, 30);
    final durationColor =
        timeMs >= 1000 ? _red : (timeMs >= 300 ? _yellow : '');
    final timeStr = '${timeMs}ms'.padLeft(7);
    final ipStr = _fit(request.ip, 15);

    final logLine =
        '$_gray$timeOfDay$_reset $color[${response.statusCode}]$_reset $methodStr $pathStr $durationColor$timeStr$_reset $_gray$ipStr$_reset';

    if (_recentRequests.length >= _trafficRows) _recentRequests.removeFirst();
    _recentRequests.add(logLine);

    // 4. Redraw the UI
    _drawDashboard();
  }

  /// Redraws the dashboard without adding a request (used after exceptions).
  static void refresh() {
    _drawDashboard();
  }

  /// Calculates uptime as a formatted string
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

  /// Generates the visual bar chart based on recent response times
  static String _generateChart() {
    if (_responseTimes.isEmpty) return 'No data yet.';

    // Find the maximum time to scale the chart dynamically
    final maxTime = _responseTimes.reduce(
      (curr, next) => curr > next ? curr : next,
    );
    if (maxTime == 0) return _sparklines.first * _responseTimes.length;

    String chart = '';
    for (var time in _responseTimes) {
      // Scale the time to an index between 0 and 7
      int index = ((time / maxTime) * (_sparklines.length - 1)).round();

      // Color code the chart: Green for fast, Yellow for medium, Red for slow spikes
      if (index < 3) {
        chart += '$_green${_sparklines[index]}$_reset';
      } else if (index < 6) {
        chart += '$_yellow${_sparklines[index]}$_reset';
      } else {
        chart += '$_red${_sparklines[index]}$_reset';
      }
    }
    return chart;
  }

  /// Helper to print a line formatted precisely to match the console monitor box.
  static void _printLine(String content) {
    print('│ ${_padToWidth(content, _contentWidth)} │');
  }

  static String _padToWidth(String content, int width) {
    final plain = stripAnsi(content);
    if (plain.length == width) return content;
    if (plain.length < width) {
      return '$content${' ' * (width - plain.length)}';
    }
    return '${plain.substring(0, width - 3)}...';
  }

  /// Helper to strip ANSI escape sequences to calculate exact display length of terminal strings
  static String stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  static String _border(String left, String fill, String right) {
    return '$_cyan$left${fill * (_contentWidth + 2)}$right$_reset';
  }

  /// Clears the terminal and draws the entire UI
  static void _drawDashboard() {
    if (!enabled) return;

    // Escape codes: \x1B[2J clears screen, \x1B[H moves cursor to top-left, \x1B[?25l hides cursor
    stdout.write('\x1B[2J\x1B[3J\x1B[H\x1B[?25l');

    final topBorder = _border('┌', '─', '┐');
    final midBorder = _border('├', '─', '┤');
    final botBorder = _border('└', '─', '┘');

    print(topBorder);

    // Title & Uptime line
    final appName = env<String>('APP_NAME') ?? 'Quds Server';
    final titleText = '$_bold$appName Monitor$_reset';
    final uptimeText = _getUptime();

    final plainTitle = stripAnsi(titleText);
    final spacesCount =
        (_contentWidth - (plainTitle.length + uptimeText.length)).clamp(
      0,
      _contentWidth,
    );
    _printLine('$titleText${' ' * spacesCount}$uptimeText');

    print(midBorder);

    // Statistics line
    _printLine('${_bold}Statistics:$_reset');

    final totalStr = _totalRequests.toString();
    final successStr = _successCount.toString();
    final clientErrStr = _clientErrorCount.toString();
    final serverErrStr = _serverErrorCount.toString();
    final exceptionStr = ExceptionLog.total.toString();
    final exColor = ExceptionLog.total > 0 ? _red : _gray;

    final statsPlain =
        'Total: $totalStr | 2xx: $successStr | 4xx: $clientErrStr | 5xx: $serverErrStr | Ex: $exceptionStr';
    final statsSpaces = (_contentWidth - statsPlain.length).clamp(
      0,
      _contentWidth,
    );
    final statsColored =
        'Total: $totalStr | ${_green}2xx: $successStr$_reset | ${_yellow}4xx: $clientErrStr$_reset | ${_red}5xx: $serverErrStr$_reset | ${exColor}Ex: $exceptionStr$_reset';
    _printLine('$statsColored${' ' * statsSpaces}');

    print(midBorder);

    // Response time trend header
    final maxTime = _responseTimes.isNotEmpty
        ? _responseTimes.reduce((a, b) => a > b ? a : b)
        : 0;
    _printLine('${_bold}Response Time Trend (Max: ${maxTime}ms)$_reset');

    // Chart row
    final chartString = _generateChart();
    final chartLength = _responseTimes.isEmpty
        ? stripAnsi(chartString).length
        : _responseTimes.length;
    final chartSpaces = (_contentWidth - chartLength).clamp(0, _contentWidth);
    _printLine('$chartString${' ' * chartSpaces}');

    print(midBorder);

    // Live Traffic header
    _printLine('${_bold}Live Traffic (Last $_trafficRows):$_reset');
    _printLine(
      '$_dim${_fit('Time', 8)} ${_fit('Code', 5)} ${_fit('Method', 6)} ${_fit('Path', 30)} ${_fit('Took', 7)} ${_fit('Client', 15)}$_reset',
    );

    for (var log in _recentRequests) {
      _printLine(log);
    }

    for (int i = _recentRequests.length; i < _trafficRows; i++) {
      _printLine('');
    }

    print(midBorder);

    _printLine('${_bold}Recent Exceptions (Last $_errorRows):$_reset');
    final errors = ExceptionLog.recent;
    final start = errors.length > _errorRows ? errors.length - _errorRows : 0;
    final visible = errors.sublist(start);

    if (visible.isEmpty) {
      _printLine(
          '${_dim}None. Unexpected errors are saved to ${ExceptionLog.filePath}$_reset');
      for (int i = 1; i < _errorRows; i++) {
        _printLine('');
      }
    } else {
      for (final record in visible) {
        final time = _hhmmss(record.time);
        final method = record.method.padRight(6);
        final path = _fit(record.path, 22);
        final remaining = _contentWidth - (8 + 1 + 6 + 1 + 22 + 1);
        final summary = _fit(record.summary, remaining);
        _printLine('$_red$time$_reset $method $path $summary');
      }
      for (int i = visible.length; i < _errorRows; i++) {
        _printLine('');
      }
    }

    print(botBorder);
  }

  static String _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return _green;
    if (statusCode >= 300 && statusCode < 400) return _yellow;
    if (statusCode >= 400 && statusCode < 500) return '\x1B[35m'; // Magenta
    return _red;
  }

  /// Restores terminal state when shutting down
  static void cleanup() {
    stdout.write('\x1B[?25h'); // Show cursor again
  }
}
