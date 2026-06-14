import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import 'server_monitor.dart'; // Import the new monitor

class LoggerMiddleware extends Middleware {
  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final stopwatch = Stopwatch()..start();

    // Pass the request down the pipeline
    final response = await next(request);

    stopwatch.stop();
    final time = stopwatch.elapsedMilliseconds;

    // Send the data to the visual dashboard instead of a standard print, excluding stats polling
    if (request.path != '/quds/stats') {
      ServerMonitor.log(request, response, time);
    }

    return response;
  }
}
