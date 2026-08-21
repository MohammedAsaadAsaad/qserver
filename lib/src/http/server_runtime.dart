import 'dart:async';
import 'dart:io';

import '../exceptions/http_exceptions.dart';
import '../logging/quds_log.dart';
import '../routing/router.dart';
import 'middleware/server_monitor.dart';
import 'quds_response.dart';

/// Tracks in-flight HTTP work and optional backpressure limits.
///
/// Defaults (`0` / `null`) keep unlimited 0.0.10 behavior.
class ServerRuntime {
  int maxConcurrentRequests;
  Duration? requestTimeout;
  int maxBodyBytes;
  Duration shutdownTimeout;

  HttpServer? server;
  bool accepting = true;

  int _active = 0;
  final Set<Future<void>> _inFlight = {};

  ServerRuntime({
    this.maxConcurrentRequests = 0,
    this.requestTimeout,
    this.maxBodyBytes = 0,
    this.shutdownTimeout = const Duration(seconds: 15),
  });

  int get activeRequests => _active;

  bool get isAtCapacity =>
      maxConcurrentRequests > 0 && _active >= maxConcurrentRequests;

  /// Dispatches [raw] and records it as in-flight so [shutdown] can drain.
  Future<void> handle(HttpRequest raw, QudsRouter router) {
    final task = _handle(raw, router);
    _inFlight.add(task);
    return task.whenComplete(() => _inFlight.remove(task));
  }

  Future<void> _handle(HttpRequest raw, QudsRouter router) async {
    if (!accepting) {
      await _sendError(
        raw,
        QudsServiceUnavailableException('Server is shutting down'),
      );
      return;
    }

    if (isAtCapacity) {
      await _sendError(
        raw,
        QudsServiceUnavailableException('Server is busy'),
      );
      return;
    }

    _active++;
    try {
      await router.dispatch(
        raw,
        maxBodyBytes: maxBodyBytes,
        timeout: requestTimeout,
      );
    } finally {
      _active--;
    }
  }

  Future<void> _sendError(
    HttpRequest raw,
    QudsServiceUnavailableException error,
  ) async {
    try {
      await QudsResponse.error(error.message, status: 503).send(raw.response);
    } catch (_) {}
  }

  /// Stops accepting, waits for in-flight handlers, then closes the socket.
  Future<void> shutdown() async {
    accepting = false;
    try {
      await Future.wait(_inFlight.toList()).timeout(shutdownTimeout);
    } on TimeoutException {
      Log.warning(
        'Shutdown timed out with ${_inFlight.length} request(s) still in flight',
      );
    }

    final bound = server;
    server = null;
    if (bound != null) {
      try {
        await bound.close(force: true);
      } catch (e) {
        Log.debug('HttpServer.close: $e');
      }
    }

    ServerMonitor.cleanup();
  }
}
