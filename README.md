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
- **Developer Command Console**: An interactive terminal dashboard displaying live traffic logs, throughput statistics, average latency trends, and worker status.
- **CLI Utility Tool**: Instantly scaffold new projects, make controllers, database models, requests, and background jobs.

---

## Installation

Add `qserver` to your `pubspec.yaml` dependencies:

```yaml
dependencies:
  qserver: any
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
