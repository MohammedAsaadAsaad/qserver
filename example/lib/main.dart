import 'package:qserver/qserver.dart';
import 'controllers/task_controller.dart';

void main() async {
  final app =
      QudsServerApp(); // Assuming QudsApp is your main application wrapper

  // 1. Register Core Engine Services
  await app.registerProviders([
    DatabaseServiceProvider(), // Boots Native PostgreSQL
    QueueServiceProvider(), // Boots Background Worker
    BroadcastServiceProvider(), // Boots WebSocket Engine
  ]);

  // 2. Apply Global Middleware
  app.router.use(CorsMiddleware());
  app.router.use(LoggerMiddleware()); // Your beautiful visual terminal monitor!

  // 3. Configure WebSocket Channels
  Broadcast.channel('public.tasks', (user, channel) async {
    return true; // Allow anyone to listen to public tasks
  });

  // 4. Define HTTP Routes
  final taskController = TaskController();

  app.welcomeHeading = 'Welcome to Quds Task Manager API!';
  app.welcomeSubheading =
      'Use this premium console to monitor server metrics, manage tasks, and trigger background worker executions.';
  app.welcomeCards = [
    DashboardCard(
      title: 'Developer Portal',
      content:
          'This application is a demo project showcasing database migration, asynchronous queuing, event broadcasting via websockets, and robust request routing.',
    ),
  ];

  app.router.group(
    prefix: '/api/v1',
    middleware: [],
    callback: (router) {
      router.get('/tasks', taskController.index);
      router.post('/tasks', taskController.store);
    },
  );

  // 5. Start the Server
  await app.serve();
}
