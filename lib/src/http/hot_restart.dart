import 'dart:async';
import 'dart:io';

import '../container/quds_env.dart';
import '../logging/quds_log.dart';

/// File-watch **hot restart** (full process respawn). Not Flutter hot reload.
///
/// Dart cannot reliably hot-reload a running HTTP app: routes, singletons,
/// and open sockets stay as they were. This watcher kills the child and
/// starts a new `dart run` so `main()` runs again.
///
/// On by default when `APP_ENV` is local/dev. Off in production, under
/// `package:test`, and when a debugger is attached. Override with
/// `QUDS_HOT_RESTART=true|false`.
class HotRestart {
  static const childEnvKey = 'QUDS_HOT_RESTART_CHILD';

  static const _watchExtensions = {'.dart', '.env'};

  /// `true` when this process should *want* hot restart (env / local).
  static bool get enabled {
    final raw = env<String>('QUDS_HOT_RESTART');
    if (raw != null) {
      final lower = raw.toLowerCase();
      if (lower == 'false' || lower == '0' || lower == 'off') return false;
      if (lower == 'true' || lower == '1' || lower == 'on') return true;
    }
    return isLocalEnvironment();
  }

  static bool get isChild =>
      Platform.environment[childEnvKey] == '1' ||
      Platform.environment[childEnvKey] == 'true';

  static bool get debuggerAttached {
    return Platform.executableArguments.any(
      (arg) =>
          arg.contains('enable-vm-service') ||
          arg.contains('--observe') ||
          arg.contains('pause_isolates_on_start'),
    );
  }

  static bool get inTest => Zone.current[#test.declarer] != null;

  /// When true, [maybeSupervise] starts the watcher and does not return
  /// until the user stops the process.
  static bool get shouldSupervise =>
      enabled && !isChild && !inTest && !debuggerAttached;

  /// Starts the supervisor when [shouldSupervise]. Returns `true` if this
  /// isolate is the watcher (caller must not boot HTTP / providers).
  static Future<bool> maybeSupervise() async {
    if (inTest || isChild) return false;
    await QudsEnv.load();
    if (!enabled) return false;
    if (debuggerAttached) {
      Log.info(
        'Hot restart skipped — debugger attached. Use the IDE restart '
        'control, or run without the debugger (`dart run` / `qserver serve`).',
        component: 'boot',
      );
      return false;
    }
    if (!shouldSupervise) return false;
    await _runSupervisor();
    return true;
  }

  static bool shouldWatchPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.contains('/.dart_tool/') ||
        normalized.contains('/.git/') ||
        normalized.contains('/storage/logs/')) {
      return false;
    }
    final name = normalized.split('/').last;
    if (name.startsWith('.env')) return true;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _watchExtensions.contains(name.substring(dot));
  }

  static Future<void> _runSupervisor() async {
    Log.info(
      'Hot restart watching lib/ and .env — save a file to respawn. '
      'QUDS_HOT_RESTART=false disables this.',
      component: 'boot',
    );

    Process? child;
    var shuttingDown = false;
    Timer? debounce;
    String? pendingPath;

    Future<void> stopChild() async {
      final current = child;
      child = null;
      if (current == null) return;
      current.kill(ProcessSignal.sigterm);
      try {
        await current.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        current.kill(ProcessSignal.sigkill);
        await current.exitCode;
      }
    }

    Future<void> startChild() async {
      if (shuttingDown) return;
      final exe = Platform.resolvedExecutable;
      final args = _childArgs();
      final env = Map<String, String>.from(Platform.environment)
        ..[childEnvKey] = '1';
      child = await Process.start(
        exe,
        args,
        environment: env,
        mode: ProcessStartMode.inheritStdio,
        workingDirectory: Directory.current.path,
      );
      unawaited(
        child!.exitCode.then((code) {
          if (!shuttingDown && child != null) {
            Log.warning(
              'Server exited ($code) — waiting for the next save',
              component: 'boot',
            );
          }
        }),
      );
    }

    Future<void> restart(String path) async {
      debounce?.cancel();
      pendingPath = path;
      debounce = Timer(const Duration(milliseconds: 400), () async {
        final changed = pendingPath;
        pendingPath = null;
        Log.info(
          'Hot restart ← ${changed ?? 'files'}',
          component: 'boot',
        );
        await stopChild();
        await startChild();
      });
    }

    final subscriptions = <StreamSubscription<FileSystemEvent>>[];

    void listen(Stream<FileSystemEvent> stream) {
      subscriptions.add(
        stream.listen((event) {
          if (shouldWatchPath(event.path)) {
            unawaited(restart(event.path));
          }
        }),
      );
    }

    final lib = Directory('lib');
    if (lib.existsSync()) {
      listen(lib.watch(recursive: true));
    }
    final bin = Directory('bin');
    if (bin.existsSync()) {
      listen(bin.watch(recursive: true));
    }
    for (final name in ['.env', '.env.local', '.env.development', '.env.dev']) {
      final file = File(name);
      if (file.existsSync()) {
        listen(file.watch());
      }
    }

    await startChild();

    final done = Completer<void>();
    void quit() {
      if (shuttingDown) return;
      shuttingDown = true;
      debounce?.cancel();
      unawaited(
        stopChild().whenComplete(() {
          for (final sub in subscriptions) {
            unawaited(sub.cancel());
          }
          if (!done.isCompleted) done.complete();
        }),
      );
    }

    ProcessSignal.sigint.watch().listen((_) => quit());
    if (!Platform.isWindows) {
      ProcessSignal.sigterm.watch().listen((_) => quit());
    }

    await done.future;
  }

  static List<String> _childArgs() {
    final exe = Platform.resolvedExecutable.toLowerCase();
    final isDartVm = exe.endsWith('dart') || exe.endsWith('dart.exe');
    if (!isDartVm) return const [];
    final script = Platform.script.toFilePath();
    if (script.endsWith('.dart') && File(script).existsSync()) {
      return ['run', script];
    }
    if (File('lib/main.dart').existsSync()) {
      return ['run', 'lib/main.dart'];
    }
    return ['run', script];
  }
}
