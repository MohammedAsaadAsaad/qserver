import 'dart:io';

import '../broadcasting/broadcast_manager.dart';
import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../exceptions/exception_log.dart';
import '../http/enums.dart';
import '../http/middleware/server_monitor.dart';
import '../http/quds_request.dart';
import '../http/quds_response.dart';
import '../queue/queue_runtime.dart';
import '../routing/router.dart';

/// Opt-in Prometheus text at `GET /quds/metrics`. Off unless `QUDS_METRICS=true`.
class MetricsRoutes {
  static void register(QudsRouter router) {
    final enabled = env<bool>('QUDS_METRICS', false) ?? false;
    if (!enabled) return;
    if (router.hasRoute(HttpMethod.get, '/quds/metrics')) return;

    router.get('/quds/metrics', (request) async {
      if (!_authorized(request)) {
        return QudsResponse.error('Unauthorized', status: 401);
      }
      return QudsResponse(
        body: _exposition(),
        headers: {
          'Content-Type': 'text/plain; version=0.0.4; charset=utf-8',
        },
      );
    });
  }

  static bool _authorized(QudsRequest request) {
    final expected = env<String>('QUDS_METRICS_TOKEN');
    if (expected == null || expected.isEmpty) return true;
    final header = request.header('authorization');
    String? provided;
    if (header != null && header.toLowerCase().startsWith('bearer ')) {
      provided = header.substring(7).trim();
    }
    provided ??= request.query('token');
    return provided == expected;
  }

  static String _exposition() {
    final q = QueueRuntime.snapshot();
    var ws = 0;
    try {
      if (QudsContainer.isRegistered<BroadcastManager>()) {
        ws = QudsContainer.resolve<BroadcastManager>().activeConnectionsCount;
      }
    } catch (_) {}

    final buf = StringBuffer()
      ..writeln('# HELP quds_http_requests_total HTTP requests by class.')
      ..writeln('# TYPE quds_http_requests_total counter')
      ..writeln(
        'quds_http_requests_total{code="2xx"} ${ServerMonitor.successCount}',
      )
      ..writeln(
        'quds_http_requests_total{code="4xx"} ${ServerMonitor.clientErrorCount}',
      )
      ..writeln(
        'quds_http_requests_total{code="5xx"} ${ServerMonitor.serverErrorCount}',
      )
      ..writeln('# HELP quds_http_requests_all_total All HTTP requests.')
      ..writeln('# TYPE quds_http_requests_all_total counter')
      ..writeln('quds_http_requests_all_total ${ServerMonitor.totalRequests}')
      ..writeln('# HELP quds_exceptions_total Captured application exceptions.')
      ..writeln('# TYPE quds_exceptions_total counter')
      ..writeln('quds_exceptions_total ${ExceptionLog.total}')
      ..writeln('# HELP quds_queue_waiting Jobs ready to run.')
      ..writeln('# TYPE quds_queue_waiting gauge')
      ..writeln('quds_queue_waiting ${q.waiting}')
      ..writeln('# HELP quds_queue_running Jobs in a worker.')
      ..writeln('# TYPE quds_queue_running gauge')
      ..writeln('quds_queue_running ${q.running}')
      ..writeln('# HELP quds_queue_failed_total Dead-lettered jobs.')
      ..writeln('# TYPE quds_queue_failed_total counter')
      ..writeln('quds_queue_failed_total ${q.failed}')
      ..writeln('# HELP quds_queue_retries_total Retry releases.')
      ..writeln('# TYPE quds_queue_retries_total counter')
      ..writeln('quds_queue_retries_total ${q.retries}')
      ..writeln('# HELP quds_ws_connections Open WebSocket connections.')
      ..writeln('# TYPE quds_ws_connections gauge')
      ..writeln('quds_ws_connections $ws')
      ..writeln('# HELP quds_process_rss_bytes Resident set size.')
      ..writeln('# TYPE quds_process_rss_bytes gauge')
      ..writeln('quds_process_rss_bytes ${ProcessInfo.currentRss}');
    return buf.toString();
  }
}
