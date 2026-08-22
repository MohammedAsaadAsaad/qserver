# qserver

A comprehensive, expressive, and type-safe backend framework for Dart.

qserver provides a complete ecosystem for building server-side applications, featuring a clean routing engine, request middleware, object-oriented input validation, an IoC container for dependency injection, asynchronous background job queues, real-time WebSocket event broadcasting, and tight database integration via the Quds DB ecosystem.

## Features

- **Object-Oriented Routing**: Clean route registration, request pipeline matching, prefix grouping, and custom request middleware.
- **Form Request Validation**: Fluent validation rules that authorize and validate incoming payload parameters automatically, instantly halting execution on validation failures.
- **Dependency Injection**: A lightweight, native IoC Container for registering and resolving singletons and factory instances globally.
- **Asynchronous Queue Worker**: Offload heavy or slow workloads into background jobs using an asynchronous worker queue.
- **WebSocket Event Broadcasting**: Broadcast events on private or public channels to real-time clients instantly.
- **Database Table Providers**: Streamlined database integration using models and table providers powered by PostgreSQL, MySQL, and other DB interfaces.
- **Structured logging**: Color-coded, component-scoped boot and runtime logs. The live terminal monitor updates in place (no flicker) on a TTY, with a duration column and LOAD / LAT / ERR / MEM / Q / WS pressure bars; piped/CI output stays append-only.
- **CLI Utility Tool**: Instantly scaffold new projects, make controllers, database models, requests, and background jobs.
- **Identity**: Email/password plus Google, Apple, and Firebase sign-in, all issuing the same JWT access/refresh pair. Optional `Mailer.send` and `DatabaseUserStore`.
- **Object storage**: Local disk, S3-compatible, or Google Cloud Storage.
- **Health checks**: Liveness, readiness (database / Redis / custom probes), and optional webhook alerts.
- **Admin Insights**: Opt-in JSON APIs and an HTML dashboard for recent exceptions and failed jobs.
- **Production ops**: Graceful shutdown, opt-in request limits, `QUEUE_CONCURRENCY`, and Prometheus text at `GET /quds/metrics`.

---

## Installation

Add `qserver` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  qserver: ^0.0.16
```

---

## Getting Started

### 1. Scaffold a New Project

Use the `qserver` CLI executable to quickly set up a new project structure:

```bash
qserver create my_backend_app
```

This command automatically generates the standard directory structure, configurations, and a fully functional task-manager example.

### 2. Standard Directory Layout

A typical project has the following layout:

```text
my_backend_app/
├── .env                  # Environment configuration variables
├── pubspec.yaml          # Project dependency configurations
└── lib/
    ├── main.dart         # Application server bootstrap entrypoint
    ├── controllers/      # Route controllers
    ├── models/           # Database models and table providers
    ├── requests/         # Request validation form classes
    └── jobs/             # Asynchronous background tasks
```

---

## Core Concepts

### Application Bootstrapping

Initialize and start the application server inside your `lib/main.dart`:

```dart
import 'package:qserver/qserver.dart';
import 'controllers/task_controller.dart';

void main() async {
  final app = QudsServerApp();

  // Register core services
  await app.registerProviders([
    DatabaseServiceProvider(), // Postgres integration
    QueueServiceProvider(),    // Background jobs worker
    BroadcastServiceProvider(), // WebSockets engine
  ]);

  // Apply global middleware
  app.router.use(CorsMiddleware());
  app.router.use(LoggerMiddleware());
  app.router.use(ExceptionHandlerMiddleware());

  // Define HTTP routes
  final taskController = TaskController();
  app.router.group(
    prefix: '/api/v1',
    callback: (router) {
      router.get('/tasks', taskController.index);
      router.post('/tasks', taskController.store);
    },
  );

  // Start HTTP server
  await app.serve();
}
```

Boot and runtime logs look like this (no screen wipe):

```text
12:03:12.100  INFO   boot      Starting application boot
12:03:12.110  INFO   boot      Loading .env
12:03:12.112  INFO   boot      Environment ready  env=local
12:03:12.180  INFO   db        Connecting postgres 127.0.0.1:5432/app_db
12:03:12.310  INFO   db        Connected postgres · 130ms
12:03:12.320  INFO   queue     Worker listening
12:03:12.330  INFO   ws        WebSocket endpoint ready at /ws
12:03:12.340  INFO   http      Listening on http://0.0.0.0:8000  env=local  pid=1842
```

The live monitor is **on by default**. On an interactive TTY it updates in place (the framed panel) with centered `APP_NAME`, compact stats, and capped Traffic / Log / Exceptions panes. When the monitor is on, line logs are **not** duplicated to stdout. Set `QUDS_MONITOR=false` for append-only lines. VS Code / Cursor **Debug Console is not a TTY** — use a Terminal or `launch.json` `"console": "integratedTerminal"`. `LOG_LEVEL=debug` adds more detail.

In `local` / `dev`, saving a `.dart` or `.env` file **hot-restarts** the process (new `main()`, new routes). Dart has no Flutter-style hot reload for HTTP apps. Set `QUDS_HOT_RESTART=false` to turn it off. While the IDE debugger is attached, use the debugger’s restart control instead.

### Routing and Middleware

Register routes using standard HTTP methods. You can group routes under a path prefix or specific middleware chains:

```dart
// Route grouping with prefixes and custom middleware
app.router.group(
  prefix: '/admin',
  middleware: [AuthMiddleware()],
  callback: (router) {
    router.get('/dashboard', adminController.dashboard);
  },
);
```

To create custom middleware, extend the `Middleware` class and implement the `handle` method:

```dart
import 'package:qserver/qserver.dart';

class CheckHeaderMiddleware extends Middleware {
  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    if (request.rawRequest.headers.value('X-Custom-Header') == null) {
      return QudsResponse.error('Missing required header', status: 400);
    }
    return await next(request);
  }
}
```

### Exception handling and logs

Register `ExceptionHandlerMiddleware` **after** the logger. It catches errors in the pipeline, converts them to HTTP responses, and stores them so you can review them later (live monitor + `storage/logs/exceptions.log`).

```dart
app.router.use(LoggerMiddleware());
app.router.use(ExceptionHandlerMiddleware(
  handler: (error, stack, request) {
    if (error is FormatException) {
      return QudsResponse.error(error.message, status: 400);
    }
    return null; // fall back to 422 / 403 / 500
  },
));
```

Unexpected exceptions are always recorded. Validation (422) and authorization (403) failures are not, unless you pass `logExpected: true`. Inspect recent records with `ExceptionLog.recent`, or read the log file at `ExceptionLog.filePath`.

Even without the middleware, `GlobalExceptionHandler` still records unexpected errors that bubble out of `dispatch`.

### Requests and Input Validation

Input validation uses Form Request classes to separate validation logic from controllers. Create validation rules by extending `QudsFormRequest`:

```dart
import 'package:qserver/qserver.dart';

class CreateTaskRequest extends QudsFormRequest {
  CreateTaskRequest(super.request);

  @override
  Future<bool> authorize() async {
    // Check if the user is authorized to perform this request
    return true;
  }

  @override
  Map<String, QudsValidator> rules() {
    return {
      'title': IsRequired().isString().min(3).max(50),
      'description': IsString().max(255),
    };
  }
}
```

Inside your controller, call `await form.validate()`. If authorization or validation fails, it throws an exception that immediately stops controller execution and returns a formatted JSON validation response (status 422):

```dart
Future<QudsResponse> store(QudsRequest request) async {
  final form = CreateTaskRequest(request);
  await form.validate(); // Validation failure halts execution instantly

  // Access the parsed request body map
  final data = request.body;
  
  // Populate database model directly
  final task = Task()..fromMap(data);
  await provider.insertEntry(task);

  return QudsResponse.json({'status': 'success', 'data': data}, status: 201);
}
```

### Dependency Injection (IoC Container)

Register and resolve dependencies anywhere in your application:

```dart
// Register a singleton
QudsContainer.singleton<AuthService>(AuthServiceImpl());

// Resolve the singleton inside a controller or constructor
final authService = QudsContainer.resolve<AuthService>();
```

### Background Jobs and Queue Worker

Background jobs execute heavy or asynchronous logic without blocking the main HTTP request loop. Declare a job by extending the `Job` class:

```dart
import 'package:qserver/qserver.dart';

class SendEmailJob extends Job {
  final String email;
  final String content;

  SendEmailJob({required this.email, required this.content});

  @override
  Future<void> handle() async {
    // Heavy process to send email
    await EmailService.send(email, content);
  }
}
```

Push the job onto the worker queue:

```dart
Queue.push(SendEmailJob(email: 'user@example.com', content: 'Welcome to our platform!'));
```

While a job runs, the worker shows a preloader (`⠋ SendEmailJob`) and then a single result line:

```text
12:03:16.200  INFO   queue     ✓ SendEmailJob · 1.2s
12:03:18.010  ERROR  queue     ✗ SendEmailJob · 12ms — retry in 1s (1/3): SMTP timeout
```

Override `Job.label` if you want a friendlier name. Use `Log.spinner('Export')` / `Log.withSpinner(...)` for your own long work.

### WebSockets and Event Broadcasting

Declare event channels and broadcast payloads to clients listening in real-time:

```dart
// Register WebSocket channel in lib/main.dart
Broadcast.channel('public.updates', (user, channel) async {
  return true; // Authorize access to this channel
});

// Broadcast events inside your controller
Broadcast.emit('public.updates', 'StatusChanged', {
  'status': 'active',
  'updatedAt': DateTime.now().toIso8601String(),
});
```

Clients can connect to `ws://localhost:8000/ws` and subscribe to these channels.

### Identity (email and social)

`EmailAuth` and `SocialAuth` sit on top of the existing JWT `Auth` facade. Bind a `UserStore` (defaults to in-memory) if you want to persist users yourself.

```dart
final session = await EmailAuth.register(
  email: 'user@example.com',
  password: 'secret123',
);
// session['accessToken'], session['refreshToken']

EmailAuth.onVerificationToken = (user, token) {
  // send email
};

AuthRoutes.register(app.router); // POST /auth/register, /login, /google, ...
```

Social login verifies a provider token, then issues the same JWT pair:

```dart
final session = await SocialAuth.loginWithGoogle(idToken);
// Also: loginWithApple, loginWithFirebase
```

Set `GOOGLE_CLIENT_ID`, `APPLE_CLIENT_ID`, and `FIREBASE_API_KEY` when using the default verifiers. Replace `SocialAuth.verifiers['google']` in tests.

### File storage

```dart
Storage.configureFromEnv(); // FILESYSTEM_DISK=local|s3|gcs
await Storage.put('avatars/me.png', bytes);
```

GCS uses `GCS_BUCKET` plus `GCS_ACCESS_TOKEN`, or a service account (`GCS_CLIENT_EMAIL` + `GCS_PRIVATE_KEY`).

### Health checks and Insights

```dart
ReadinessChecker.add(() async => HealthCheckResult.ok('payments'));
HealthNotifier.onChange = (report) async {
  // Slack / email — also set HEALTH_WEBHOOK_URL
};

// QUDS_INSIGHTS=true and QUDS_INSIGHTS_TOKEN=...
// GET /quds/insights  (HTML)   GET /quds/insights/exceptions
// GET /quds/insights/failed-jobs

// QUDS_METRICS=true
// GET /quds/metrics   (Prometheus)
```

Set `Mailer.send` to deliver verification and reset tokens (or keep using `EmailAuth.onVerificationToken`). Persist users with `AUTH_USER_STORE=database` when a `DatabaseConnection` is registered.

---

## CLI Reference

The `qserver` executable assists with generating project components:

- **Create Project**:
  ```bash
  qserver create <project_name>
  ```
- **Run Server**:
  ```bash
  qserver serve
  ```
- **Generate Controller**:
  ```bash
  qserver make:controller <Name>
  ```
- **Generate Model**:
  ```bash
  qserver make:model <Name>
  ```
- **Generate Request Validation**:
  ```bash
  qserver make:request <Name>
  ```
- **Generate Background Job**:
  ```bash
  qserver make:job <Name>
  ```

---

## License

This framework is open-source software licensed under the [MIT License](LICENSE).
