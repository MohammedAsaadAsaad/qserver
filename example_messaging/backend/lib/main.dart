import 'package:qserver/qserver.dart';
import 'controllers/chat_controller.dart';

Future<void> main() async {
  final app = QudsServerApp();

  app.showWelcomePage = true;
  app.welcomeHeading = 'Welcome to Quds WhatsApp Backend API!';
  app.welcomeSubheading =
      'Use this real-time socket-based messaging backend with MySQL persistence.';

  // 1. Register Core Engine Services
  await app.registerProviders([
    DatabaseServiceProvider(), // Boots MySQL connection automatically based on .env
    BroadcastServiceProvider(), // Boots WebSocket Broadcasting Engine at /ws
  ]);

  // 2. Apply Global Middleware
  app.router.use(
    CorsMiddleware(),
  ); // Crucial for allowing frontend to make HTTP/WS connections
  app.router.use(LoggerMiddleware()); // Terminal visual metrics dashboard

  // 3. Configure WebSocket Channels
  Broadcast.channel('chat.*', (user, channel) async {
    return true; // Allow any client to subscribe for this demo
  });

  // 4. Define HTTP Routes
  final chatController = ChatController();

  app.router.group(
    prefix: '/api/v1',
    middleware: [],
    callback: (router) {
      router.get('/messages', chatController.getMessages);
      router.post('/messages', chatController.sendMessage);
    },
  );

  // 5. Start the Server
  await app.serve();
}
