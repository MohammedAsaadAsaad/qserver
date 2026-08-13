import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import '../../exceptions/exception_handler.dart';
import '../../logging/quds_log.dart';
import 'server_monitor.dart';

class LoggerMiddleware extends Middleware {
  static const _skipPaths = {
    '/quds/stats',
    '/quds/health',
    '/quds/ready',
  };

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final stopwatch = Stopwatch()..start();

    try {
      final response = await next(request);
      _log(request, response, stopwatch);
      return response;
    } catch (error) {
      // Still record the request in the live feed, then let the exception
      // middleware / router turn it into an HTTP response.
      final failed = QudsResponse(
        statusCode: GlobalExceptionHandler.statusOf(error),
      );
      _log(request, failed, stopwatch);
      rethrow;
    }
  }

  void _log(QudsRequest request, QudsResponse response, Stopwatch stopwatch) {
    stopwatch.stop();
    if (_skipPaths.contains(request.path)) return;

    ServerMonitor.log(request, response, stopwatch.elapsedMilliseconds);
    Log.info(
      '${request.method} ${request.pathAndQuery} → '
      '${response.statusCode} (${stopwatch.elapsedMilliseconds}ms) ip=${request.ip}',
    );
  }
}
