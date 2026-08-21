import 'dart:async';
import 'dart:io';
import 'qserver.dart';

export 'src/exceptions/http_exceptions.dart';
export 'src/http/readiness.dart';
export 'src/http/server_runtime.dart';
export 'src/database/database.dart';
export 'src/queue/queue_worker.dart';
export 'src/http/quds_request.dart';
export 'src/http/quds_response.dart';
export 'src/http/enums.dart';
export 'src/http/middleware.dart';
export 'src/container/quds_mapper.dart';
export 'src/container/quds_container.dart';
export 'src/container/service_provider.dart';
export 'src/container/quds_env.dart';
export 'src/routing/router.dart';
export 'src/routing/route.dart';
export 'src/http/quds_form_request.dart';
export 'src/http/middleware/cors_middleware.dart';
export 'src/http/middleware/logger_middleware.dart';
export 'src/http/middleware/exception_handler_middleware.dart';
export 'src/http/middleware/rate_limit_middleware.dart';
export 'src/http/middleware/security_headers_middleware.dart';
export 'src/http/middleware/request_id_middleware.dart';
export 'src/http/middleware/insights_auth_middleware.dart';
export 'src/exceptions/exception_handler.dart';
export 'src/exceptions/exception_log.dart';
export 'src/storage/storage.dart';
export 'src/storage/storage_disk.dart';
export 'src/storage/local_storage_disk.dart';
export 'src/storage/s3_storage_disk.dart';
export 'src/storage/gcs_storage_disk.dart';
export 'src/http/uploaded_file.dart';
export 'src/http/auth/auth.dart';
export 'src/http/auth/user_store.dart';
export 'src/http/auth/database_user_store.dart';
export 'src/http/auth/mailer.dart';
export 'src/http/auth/password_hasher.dart';
export 'src/http/auth/email_auth.dart';
export 'src/http/auth/social_auth.dart';
export 'src/http/auth/auth_routes.dart';
export 'src/http/middleware/auth_middleware.dart';
export 'src/queue/job.dart';
export 'src/queue/queue.dart';
export 'src/queue/queue_driver.dart';
export 'src/queue/queue_provider.dart';
export 'src/queue/serializable_job.dart';
export 'src/queue/job_registry.dart';
export 'src/queue/database_queue_driver.dart';
export 'src/queue/queue_runtime.dart';
export 'src/schedule/schedule.dart';
export 'src/schedule/schedule_provider.dart';
export 'src/broadcasting/broadcast.dart';
export 'src/broadcasting/broadcast_provider.dart';
export 'src/broadcasting/broadcast_manager.dart';
export 'src/broadcasting/redis_broadcast_bridge.dart';
export 'src/http/middleware/server_monitor.dart';
export 'src/database/database_provider.dart';
export 'src/database/migration_runner.dart';
export 'src/http/dashboard.dart';
export 'src/http/validator.dart';
export 'src/cache/cache.dart';
export 'src/cache/cache_driver.dart';
export 'src/cache/memory_cache_driver.dart';
export 'src/cache/redis_cache_driver.dart';
export 'src/cache/cache_provider.dart';
export 'src/logging/quds_log.dart';
export 'src/logging/log_spinner.dart';
export 'src/testing/quds_test_client.dart';
export 'src/insights/insights_routes.dart';
export 'src/insights/insights_dashboard.dart';
export 'src/insights/metrics_routes.dart';
export 'src/http/hot_restart.dart';
export 'package:quds_db_interface/quds_db_interface.dart';
export 'package:quds_db_postgres/quds_db_postgres.dart';
export 'package:quds_db_mysql/quds_db_mysql.dart';

class QudsServerApp {
  static final DateTime _startTime = DateTime.now();
  final QudsRouter router = QudsRouter();
  final List<ServiceProvider> _providers = [];
  final ServerRuntime runtime = ServerRuntime();

  /// Opt-in console at `GET /`. Off by default for security.
  bool showWelcomePage = false;
  String? welcomeHeading;
  String? welcomeSubheading;
  List<DashboardCard>? welcomeCards;

  /// Optional Insights authorizer (JWT admin role, etc.). Used when Insights is on.
  InsightsAuthorizer? insightsAuthorizer;

  /// `0` = unlimited (default, same as 0.0.10). Override with `MAX_CONCURRENT_REQUESTS`.
  int maxConcurrentRequests = 0;

  /// `0` = disabled (default). Override with `REQUEST_TIMEOUT_SECONDS`.
  int requestTimeoutSeconds = 0;

  /// `0` = unlimited (default). Override with `MAX_BODY_BYTES`.
  int maxBodyBytes = 0;

  /// Drain window used by [close]. Override with `SHUTDOWN_TIMEOUT_SECONDS`.
  int shutdownTimeoutSeconds = 15;

  bool _closed = false;
  bool _listeningSignals = false;
  bool _envDriversApplied = false;

  QudsServerApp() {
    QudsContainer.singleton<QudsRouter>(router);
    if (!QudsContainer.isRegistered<CacheDriver>()) {
      QudsContainer.singleton<CacheDriver>(MemoryCacheDriver());
    }
    if (!QudsContainer.isRegistered<TokenStore>()) {
      QudsContainer.singleton<TokenStore>(MemoryTokenStore());
    }
    if (!QudsContainer.isRegistered<UserStore>()) {
      QudsContainer.singleton<UserStore>(MemoryUserStore());
    }
  }

  /// Switches optional drivers from env after providers have registered/booted.
  ///
  /// Defaults remain memory cache, memory queue, and local storage unless the
  /// corresponding env var is set.
  Future<void> _configureDriversFromEnv() async {
    if (_envDriversApplied) return;
    _envDriversApplied = true;

    final cacheDriver =
        (env<String>('CACHE_DRIVER', 'memory') ?? 'memory').toLowerCase();
    if (cacheDriver == 'redis') {
      QudsContainer.singleton<CacheDriver>(RedisCacheDriver());
      Log.info('Driver redis', component: 'cache');
    }

    final queueDriver =
        (env<String>('QUEUE_DRIVER', 'memory') ?? 'memory').toLowerCase();
    if (queueDriver == 'database') {
      if (QudsContainer.isRegistered<DatabaseConnection>()) {
        QudsContainer.singleton<QueueDriver>(
          DatabaseQueueDriver(QudsContainer.resolve<DatabaseConnection>()),
        );
        Log.info('Driver database', component: 'queue');
      } else {
        Log.warning(
          'QUEUE_DRIVER=database but DatabaseConnection is not registered',
          component: 'queue',
        );
      }
    }

    final filesystemDisk =
        (env<String>('FILESYSTEM_DISK', 'local') ?? 'local').toLowerCase();
    if (filesystemDisk != 'local') {
      Storage.configureFromEnv(filesystemDisk);
    }

    final broadcastDriver =
        (env<String>('BROADCAST_DRIVER', 'local') ?? 'local').toLowerCase();
    if (broadcastDriver == 'redis') {
      if (QudsContainer.isRegistered<BroadcastManager>()) {
        await RedisBroadcastBridge.attach(
          QudsContainer.resolve<BroadcastManager>(),
        );
      } else {
        Log.warning(
          'BROADCAST_DRIVER=redis requires BroadcastServiceProvider '
          '(BroadcastManager not registered)',
          component: 'ws',
        );
      }
    }

    final userStore =
        (env<String>('AUTH_USER_STORE', 'memory') ?? 'memory').toLowerCase();
    if (userStore == 'database') {
      if (QudsContainer.isRegistered<DatabaseConnection>()) {
        final current = QudsContainer.isRegistered<UserStore>()
            ? QudsContainer.resolve<UserStore>()
            : null;
        if (current == null || current.runtimeType == MemoryUserStore) {
          QudsContainer.singleton<UserStore>(
            DatabaseUserStore(QudsContainer.resolve<DatabaseConnection>()),
          );
          Log.info('User store database', component: 'auth');
        }
      } else {
        Log.warning(
          'AUTH_USER_STORE=database but DatabaseConnection is not registered',
          component: 'auth',
        );
      }
    }

    final migrateOnBoot = env<bool>('MIGRATE_ON_BOOT', false) ?? false;
    if (migrateOnBoot) {
      if (QudsContainer.isRegistered<DatabaseConnection>()) {
        try {
          await FileMigrationRunner.fromContainer().migrate();
        } on StateError catch (e) {
          Log.warning('$e', component: 'db');
        }
      } else {
        Log.warning(
          'MIGRATE_ON_BOOT=true but DatabaseConnection is not registered',
          component: 'db',
        );
      }
    }
  }

  void _registerWelcomeRoutes() {
    if (!router.hasRoute(HttpMethod.get, '/quds/stats')) {
      router.get('/quds/stats', (request) async {
        if (!isLocalEnvironment()) {
          return QudsResponse.error('Not found', status: 404);
        }

        final rssMb =
            (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1);

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

    if (!router.hasRoute(HttpMethod.get, '/')) {
      router.get('/', (request) async {
        return QudsResponse.html(ProjectInfoDashboard.render(
          welcomeHeading: welcomeHeading,
          welcomeSubheading: welcomeSubheading,
          customCards: welcomeCards,
        ));
      });
    }
  }

  void _registerHealthRoutes() {
    if (!router.hasRoute(HttpMethod.get, '/quds/health')) {
      router.get('/quds/health', (request) async {
        return QudsResponse.json({'status': 'ok'});
      });
    }

    if (!router.hasRoute(HttpMethod.get, '/quds/ready')) {
      router.get('/quds/ready', (request) async {
        final report = await ReadinessChecker.inspect();
        return QudsResponse.json(report.body, status: report.statusCode);
      });
    }
  }

  Future<void> registerProviders(List<ServiceProvider> providers) async {
    if (await HotRestart.maybeSupervise()) return;
    ServerMonitor.attach();
    Log.boot('Starting application boot');
    await QudsEnv.load();
    ServerMonitor.attach();
    _providers.addAll(providers);
    if (providers.isEmpty) {
      Log.boot('No service providers registered');
    } else {
      Log.boot('Registering ${providers.length} service provider(s)');
    }
    for (var provider in _providers) {
      provider.register();
      Log.debug('Registered ${provider.runtimeType}', component: 'boot');
    }
    for (var provider in _providers) {
      Log.boot('Booting ${provider.runtimeType}');
      await provider.boot();
    }
    await _configureDriversFromEnv();
    Log.boot('Providers ready');
  }

  void _applyRuntimeLimitsFromEnv() {
    maxConcurrentRequests =
        env<int>('MAX_CONCURRENT_REQUESTS', maxConcurrentRequests) ??
            maxConcurrentRequests;
    requestTimeoutSeconds =
        env<int>('REQUEST_TIMEOUT_SECONDS', requestTimeoutSeconds) ??
            requestTimeoutSeconds;
    maxBodyBytes = env<int>('MAX_BODY_BYTES', maxBodyBytes) ?? maxBodyBytes;
    shutdownTimeoutSeconds =
        env<int>('SHUTDOWN_TIMEOUT_SECONDS', shutdownTimeoutSeconds) ??
            shutdownTimeoutSeconds;

    runtime.maxConcurrentRequests = maxConcurrentRequests;
    runtime.maxBodyBytes = maxBodyBytes;
    runtime.shutdownTimeout = Duration(seconds: shutdownTimeoutSeconds);
    runtime.requestTimeout = requestTimeoutSeconds > 0
        ? Duration(seconds: requestTimeoutSeconds)
        : null;
  }

  void _listenShutdownSignals() {
    if (_listeningSignals) return;
    _listeningSignals = true;

    var forcing = false;
    Future<void> onSignal(ProcessSignal signal) async {
      if (forcing) {
        exit(1);
      }
      if (_closed) {
        exit(0);
      }
      forcing = true;
      Log.info('Received $signal — shutting down', component: 'boot');
      await close();
      exit(0);
    }

    ProcessSignal.sigint.watch().listen(onSignal);
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen(onSignal);
    }
  }

  /// Starts the HTTP Server, pulling configs from the .env file automatically
  Future<void> serve({
    String? defaultHost,
    int? defaultPort,
    bool listenForSignals = true,
  }) async {
    if (listenForSignals && await HotRestart.maybeSupervise()) return;
    ServerMonitor.attach();
    Log.boot('Preparing HTTP server');
    await QudsEnv.load();
    ServerMonitor.attach();
    await _configureDriversFromEnv();
    _applyRuntimeLimitsFromEnv();

    _registerHealthRoutes();
    InsightsRoutes.authorizer = insightsAuthorizer;
    InsightsRoutes.register(router);
    MetricsRoutes.register(router);

    if (showWelcomePage) {
      _registerWelcomeRoutes();
    }

    final host = env<String>('APP_HOST') ?? InternetAddress.anyIPv4.address;
    final port = env<int>('APP_PORT') ?? defaultPort ?? 8000;
    final appEnv = env<String>('APP_ENV', 'local') ?? 'local';

    Log.boot('Binding $host:$port');
    final server = await HttpServer.bind(host, port);
    runtime.server = server;
    runtime.accepting = true;
    _closed = false;

    if (listenForSignals) {
      _listenShutdownSignals();
    }

    if (maxConcurrentRequests > 0) {
      Log.info(
        'Max concurrent requests $maxConcurrentRequests',
        component: 'http',
      );
    }
    if (requestTimeoutSeconds > 0) {
      Log.info(
        'Request timeout ${requestTimeoutSeconds}s',
        component: 'http',
      );
    }

    ServerMonitor.listenHint = 'http://$host:$port  pid=$pid';
    Log.info(
      'Listening on http://$host:$port  env=$appEnv  pid=$pid',
      component: 'http',
    );

    await for (HttpRequest request in server) {
      unawaited(runtime.handle(request, router));
    }

    if (!_closed) {
      await close();
    }
  }

  /// Drains in-flight requests, stops providers, and closes sockets.
  ///
  /// Safe to call more than once. Existing apps that never call this keep
  /// running until a process signal arrives.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ServerMonitor.endLive();
    ServerMonitor.listenHint = null;
    Log.info('Shutting down', component: 'boot');

    await runtime.shutdown();

    for (final provider in _providers.reversed) {
      try {
        await provider.shutdown();
      } catch (e) {
        Log.warning('Provider shutdown failed (${provider.runtimeType}): $e');
      }
    }

    await RedisBroadcastBridge.detach();

    if (QudsContainer.isRegistered<CacheDriver>()) {
      final cache = QudsContainer.resolve<CacheDriver>();
      if (cache is RedisCacheDriver) {
        try {
          await cache.close();
        } catch (e) {
          Log.debug('Redis cache close: $e');
        }
      }
    }

    Log.info('Shutdown complete', component: 'boot');
  }
}
