import 'dart:io';
import 'qserver.dart';

export 'src/http/quds_request.dart';
export 'src/http/quds_response.dart';
export 'src/http/enums.dart';
export 'src/http/middleware.dart';
export 'src/container/quds_mapper.dart';
export 'src/container/quds_container.dart';
export 'src/container/service_provider.dart';
export 'src/container/quds_env.dart'; // Export the env helper
export 'src/routing/router.dart';
export 'src/routing/route.dart';
export 'src/http/quds_form_request.dart';
export 'src/http/middleware/cors_middleware.dart';
export 'src/http/middleware/logger_middleware.dart';
export 'src/exceptions/exception_handler.dart';
export 'src/storage/storage.dart';
export 'src/http/uploaded_file.dart';
export 'src/http/auth/auth.dart';
export 'src/http/middleware/auth_middleware.dart';
export 'src/queue/job.dart';
export 'src/queue/queue.dart';
export 'src/queue/queue_provider.dart';
export 'src/broadcasting/broadcast.dart';
export 'src/broadcasting/broadcast_provider.dart';
export 'src/broadcasting/broadcast_manager.dart';
export 'src/http/middleware/server_monitor.dart';
export 'src/database/database_provider.dart';
export 'src/http/dashboard.dart';
export 'src/http/validator.dart';
export 'package:quds_db_interface/quds_db_interface.dart';
export 'package:quds_db_postgres/quds_db_postgres.dart';
export 'package:quds_db_mysql/quds_db_mysql.dart';

class QudsServerApp {
  static final DateTime _startTime = DateTime.now();
  final QudsRouter router = QudsRouter();
  final List<ServiceProvider> _providers = [];

  bool showWelcomePage = true;
  String? welcomeHeading;
  String? welcomeSubheading;
  List<DashboardCard>? welcomeCards;

  QudsServerApp() {
    QudsContainer.singleton<QudsRouter>(router);

    router.get('/quds/stats', (request) async {
      final rssMb = (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1);

      int wsConnections = 0;
      try {
        final manager = QudsContainer.resolve<BroadcastManager>();
        wsConnections = manager.activeConnectionsCount;
      } catch (_) {}

      final uptimeDuration = DateTime.now().difference(_startTime);
      final h = uptimeDuration.inHours.toString().padLeft(2, '0');
      final m =
          uptimeDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s =
          uptimeDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
      final uptimeStr = '$h:$m:$s';

      return QudsResponse.json({
        'memory': '$rssMb MB',
        'os': Platform.operatingSystem,
        'dartVersion': Platform.version.split(' ').first,
        'processors': Platform.numberOfProcessors,
        'uptime': uptimeStr,
        'pid': pid,
        'wsConnections': wsConnections,
      });
    });
  }

  Future<void> registerProviders(List<ServiceProvider> providers) async {
    await QudsEnv.load();
    _providers.addAll(providers);
    for (var provider in _providers) {
      provider.register();
    }
    for (var provider in _providers) {
      await provider.boot();
    }
  }

  /// Starts the HTTP Server, pulling configs from the .env file automatically
  Future<void> serve({String? defaultHost, int? defaultPort}) async {
    await QudsEnv.load();

    if (showWelcomePage && !router.hasRoute(HttpMethod.get, '/')) {
      router.get('/', (request) async {
        return QudsResponse.html(ProjectInfoDashboard.render(
          welcomeHeading: welcomeHeading,
          welcomeSubheading: welcomeSubheading,
          customCards: welcomeCards,
        ));
      });
    }

    final host = env<String>('APP_HOST') ?? InternetAddress.anyIPv4.address;
    final port = env<int>('APP_PORT') ?? defaultPort ?? 8000;

    final server = await HttpServer.bind(host, port);

    // Catch CTRL+C to restore the terminal cursor before exiting
    ProcessSignal.sigint.watch().listen((ProcessSignal signal) {
      ServerMonitor.cleanup();
      exit(0);
    });

    print('\x1B[2J\x1B[H'); // Clear screen
    print('Starting Quds Server on http://$host:$port...');

    await for (HttpRequest request in server) {
      router.dispatch(request);
    }
  }
}
