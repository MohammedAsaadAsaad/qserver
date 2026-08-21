import 'package:qserver/qserver.dart';
import '../jobs/export_report_job.dart';

class DemoController {
  Future<QudsResponse> me(QudsRequest request) async {
    return QudsResponse.json({
      'message': 'Authenticated',
      'user': request.user(),
    });
  }

  Future<QudsResponse> export(QudsRequest request) async {
    final name = request.input<String>('name') ?? 'weekly';
    await Queue.push(ExportReportJob(name: name));
    return QudsResponse.json({
      'message': 'Export queued — watch the terminal preloader',
      'job': 'Export report ($name)',
    }, status: 202);
  }

  Future<QudsResponse> cacheProbe(QudsRequest request) async {
    const key = 'demo:hits';
    final current = await Cache.get<int>(key) ?? 0;
    final next = current + 1;
    await Cache.put(key, next, ttl: const Duration(minutes: 5));
    return QudsResponse.json({
      'message': 'Cache increment',
      'hits': next,
    });
  }
}
