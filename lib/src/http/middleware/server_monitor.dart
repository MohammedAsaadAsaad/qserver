import 'dart:collection';
import 'dart:io';
import '../quds_request.dart';
import '../quds_response.dart';
import '../../container/quds_env.dart';

class ServerMonitor {
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

    // 3. Format the log line components precisely to fit within content width (58)
    final color = _getStatusColor(response.statusCode);
    final reset = '\x1B[0m';
    final methodStr = request.method.padRight(6);
    
    var pathStr = request.path;
    if (pathStr.length > 37) {
      pathStr = pathStr.substring(0, 34) + '...';
    } else {
      pathStr = pathStr.padRight(37);
    }
    
    final timeStr = '${timeMs}ms'.padLeft(7); // e.g. "  120ms" or "    0ms"

    // Total plain length: 5 (status) + 1 (space) + 6 (method) + 1 (space) + 37 (path) + 1 (space) + 7 (time) = 58 characters
    final logLine =
        '$color[${response.statusCode}]$reset $methodStr $pathStr $timeStr';

    if (_recentRequests.length >= 10) _recentRequests.removeFirst();
    _recentRequests.add(logLine);

    // 4. Redraw the UI
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
        chart += '\x1B[32m${_sparklines[index]}\x1B[0m'; // Green
      } else if (index < 6) {
        chart += '\x1B[33m${_sparklines[index]}\x1B[0m'; // Yellow
      } else {
        chart += '\x1B[31m${_sparklines[index]}\x1B[0m'; // Red
      }
    }
    return chart;
  }

  /// Helper to print a line formatted precisely to match the console monitor box width of 60.
  /// Generates exactly: "│ " + content (padded to 58 display characters) + " │"
  static void _printLine(String content) {
    final plain = stripAnsi(content);
    final len = plain.length;
    if (len < 58) {
      print('│ $content${' ' * (58 - len)} │');
    } else if (len > 58) {
      print('│ ${content.substring(0, 55)}... │');
    } else {
      print('│ $content │');
    }
  }

  /// Helper to strip ANSI escape sequences to calculate exact display length of terminal strings
  static String stripAnsi(String input) {
    return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  /// Clears the terminal and draws the entire UI
  static void _drawDashboard() {
    // Escape codes: \x1B[2J clears screen, \x1B[H moves cursor to top-left, \x1B[?25l hides cursor
    stdout.write('\x1B[2J\x1B[3J\x1B[H\x1B[?25l');

    final cyan = '\x1B[36m';
    final green = '\x1B[32m';
    final red = '\x1B[31m';
    final yellow = '\x1B[33m';
    final reset = '\x1B[0m';
    final bold = '\x1B[1m';

    // Borders (width 62 total):
    final topBorder = '$cyan┌────────────────────────────────────────────────────────────┐$reset';
    final midBorder = '$cyan├────────────────────────────────────────────────────────────┤$reset';
    final botBorder = '$cyan└────────────────────────────────────────────────────────────┘$reset';

    print(topBorder);

    // Title & Uptime line (content length 58)
    final appName = env<String>('APP_NAME') ?? 'Quds Server';
    final titleText = '$bold$appName Monitor$reset';
    final uptimeText = _getUptime();
    
    final plainTitle = stripAnsi(titleText);
    final plainUptime = uptimeText;
    final spacesCount = (58 - (plainTitle.length + plainUptime.length)).clamp(0, 58);
    _printLine('$titleText${' ' * spacesCount}$uptimeText');

    print(midBorder);

    // Statistics line
    _printLine('${bold}Statistics:$reset');

    final totalStr = _totalRequests.toString();
    final successStr = _successCount.toString();
    final clientErrStr = _clientErrorCount.toString();
    final serverErrStr = _serverErrorCount.toString();
    
    // Layout: "Total: 123  | 2xx: 123  | 4xx: 123  | 5xx: 123"
    // Plain text layout for length calculation:
    final statsPlain = 'Total: $totalStr | 2xx: $successStr | 4xx: $clientErrStr | 5xx: $serverErrStr';
    final statsSpaces = (58 - statsPlain.length).clamp(0, 58);
    final statsColored = 'Total: $totalStr | ${green}2xx: $successStr$reset | ${yellow}4xx: $clientErrStr$reset | ${red}5xx: $serverErrStr$reset';
    _printLine('$statsColored${' ' * statsSpaces}');

    print(midBorder);

    // Response time trend header
    final maxTime = _responseTimes.isNotEmpty ? _responseTimes.reduce((a, b) => a > b ? a : b) : 0;
    _printLine('${bold}Response Time Trend (Max: ${maxTime}ms)$reset');

    // Chart row
    final chartString = _generateChart();
    final chartLength = _responseTimes.length;
    final chartSpaces = (58 - chartLength).clamp(0, 58);
    _printLine('$chartString${' ' * chartSpaces}');

    print(midBorder);

    // Live Traffic header
    _printLine('${bold}Live Traffic (Last 10):$reset');

    // Print recent requests
    for (var log in _recentRequests) {
      _printLine(log);
    }

    // Fill empty space if we haven't hit 10 requests yet
    for (int i = _recentRequests.length; i < 10; i++) {
      _printLine('');
    }

    print(botBorder);
  }

  static String _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return '\x1B[32m'; // Green
    if (statusCode >= 300 && statusCode < 400) return '\x1B[33m'; // Yellow
    if (statusCode >= 400 && statusCode < 500) return '\x1B[35m'; // Magenta
    return '\x1B[31m'; // Red
  }

  /// Restores terminal state when shutting down
  static void cleanup() {
    stdout.write('\x1B[?25h'); // Show cursor again
  }
}
