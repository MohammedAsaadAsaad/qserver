import 'package:qserver/qserver.dart';
import 'controllers/demo_controller.dart';
import 'controllers/task_controller.dart';
import 'jobs/export_report_job.dart';
import 'jobs/heartbeat_job.dart';
import 'jobs/process_task_job.dart';

void main() async {
  final app = QudsServerApp();

  await app.registerProviders([
    DatabaseServiceProvider(),
    QueueServiceProvider(),
    BroadcastServiceProvider(),
    ScheduleServiceProvider(),
  ]);

  app.router.use(RequestIdMiddleware());
  app.router.use(SecurityHeadersMiddleware());
  app.router.use(CorsMiddleware());
  app.router.use(LoggerMiddleware());
  app.router.use(ExceptionHandlerMiddleware());

  Broadcast.channel('public.tasks', (user, channel) async => true);

  ReadinessChecker.add(() async => HealthCheckResult.ok('demo'));
  HealthNotifier.onChange = (report) async {
    Log.warning(
      'Readiness changed → ${report.body['status']}',
      component: 'boot',
    );
  };

  EmailAuth.onVerificationToken = (user, token) {
    Log.info(
      'Verification token for ${user.email}: $token',
      component: 'auth',
    );
  };

  AuthRoutes.register(app.router);

  final tasks = TaskController();
  final demo = DemoController();

  app.showWelcomePage = true;
  app.welcomeHeading = 'Quds Task Manager';
  app.welcomeSubheading =
      'Demo API: JWT auth, background jobs with a terminal preloader, '
      'WebSockets, cache, and Insights.';
  app.welcomeCards = [
    DashboardCard(
      title: 'Try it',
      content:
          'POST /auth/register · POST /api/v1/tasks · POST /api/v1/demo/export · '
          'GET /api/v1/me (Bearer) · GET /quds/insights?token=demo-insights',
    ),
    DashboardCard(
      title: 'Watch the terminal',
      content:
          'Creating a task or export queues a job. The worker shows '
          '⠋ ProcessTask … then ✓ when it finishes.',
    ),
  ];

  app.router.group(
    prefix: '/api/v1',
    callback: (router) {
      router.get('/tasks', tasks.index);
      router.post('/tasks', tasks.store);
      router.post('/demo/export', demo.export);
      router.get('/demo/cache', demo.cacheProbe);
      router.get('/me', demo.me, middleware: [AuthMiddleware()]);
    },
  );

  await Queue.push(
    ProcessTaskJob({'title': 'Welcome', 'status': 'pending'}),
  );
  await Queue.push(ExportReportJob(name: 'startup'));
  await Queue.push(ExportReportJob(name: 'monthly'));
  await Schedule.every(const Duration(seconds: 25), HeartbeatJob());

  await app.serve();
}
