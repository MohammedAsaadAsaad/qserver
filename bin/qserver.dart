import 'dart:io';

import 'package:qserver/qserver.dart';

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    _printHelp();
    return;
  }

  final command = arguments[0];

  switch (command) {
    case 'create':
      if (arguments.length < 2) {
        print('Error: Please provide a project name.');
        print('Usage: qserver create my_cool_server');
        return;
      }
      _createProject(arguments[1]);
      break;
    case 'serve':
      await _serveCommand();
      break;
    case 'make:controller':
      if (arguments.length < 2) {
        print('Error: Please provide a controller name.');
        return;
      }
      _makeController(arguments[1]);
      break;
    case 'make:model':
      if (arguments.length < 2) {
        print('Error: Please provide a model name.');
        return;
      }
      _makeModel(arguments[1]);
      break;
    case 'make:request':
      if (arguments.length < 2) {
        print('Error: Please provide a request name.');
        return;
      }
      _makeRequest(arguments[1]);
      break;
    case 'make:job':
      if (arguments.length < 2) {
        print('Error: Please provide a job name.');
        return;
      }
      _makeJob(arguments[1]);
      break;
    case 'make:middleware':
      if (arguments.length < 2) {
        print('Error: Please provide a middleware name.');
        return;
      }
      _makeMiddleware(arguments[1]);
      break;
    case 'make:provider':
      if (arguments.length < 2) {
        print('Error: Please provide a provider name.');
        return;
      }
      _makeProvider(arguments[1]);
      break;
    case 'cache:clear':
      print(
        'Cache.flush() clears the in-process cache at runtime.\n'
        'Call Cache.flush() from your app code, or restart the server.',
      );
      break;
    case 'make:migration':
      if (arguments.length < 2) {
        print('Error: Please provide a migration name.');
        print('Usage: qserver make:migration create_users_table');
        return;
      }
      _makeMigration(arguments[1]);
      break;
    case 'migrate':
      await _migrateCommand();
      break;
    case 'migrate:rollback':
      await _migrateRollbackCommand();
      break;
    default:
      print('Unknown command: $command');
      _printHelp();
  }
}

void _printHelp() {
  print('Quds Server CLI (qserver)');
  print('Usage:');
  print('  qserver create <name>         Scaffolds a new Quds project');
  print('  qserver serve                 Starts the HTTP server');
  print('  qserver make:controller       Creates a new Controller');
  print('  qserver make:model            Creates a new Model');
  print('  qserver make:request          Creates a new Request class');
  print('  qserver make:job              Creates a new Background Job');
  print('  qserver make:middleware       Creates a new Middleware');
  print('  qserver make:provider         Creates a new Service Provider');
  print('  qserver make:migration        Creates database/migrations/<id>/');
  print('  qserver migrate               Applies pending SQL migrations');
  print('  qserver migrate:rollback      Rolls back the last migration');
  print('  qserver cache:clear           Shows how to flush the cache');
}

// ==========================================
// The Project Scaffolding Engine
// ==========================================

void _createProject(String projectName) {
  final root = Directory(projectName);
  if (root.existsSync()) {
    print('❌ Error: Directory [$projectName] already exists.');
    return;
  }

  print('Scaffolding new Quds Server project: $projectName...');
  root.createSync();

  Directory('${root.path}/lib/controllers').createSync(recursive: true);
  Directory('${root.path}/lib/models').createSync(recursive: true);
  Directory('${root.path}/lib/requests').createSync(recursive: true);
  Directory('${root.path}/lib/jobs').createSync(recursive: true);
  Directory('${root.path}/database/migrations').createSync(recursive: true);

  // 1. pubspec.yaml
  File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: $projectName
description: A powerful Dart API built with Quds Server.
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  qserver: any
''');

  // 2. .env
  File('${root.path}/.env').writeAsStringSync('''
APP_NAME="$projectName"
APP_ENV=local
APP_KEY=secret_key_change_me_in_production
APP_PORT=8000

# Options: postgres, mysql, sqlite
DB_CONNECTION=postgres
DB_HOST=127.0.0.1
DB_PORT=5432
DB_DATABASE=${projectName}_db
DB_USERNAME=postgres
DB_PASSWORD=postgres

# Optional drivers (defaults keep 0.0.9 behavior: memory / local)
# CACHE_DRIVER=memory
# CACHE_DRIVER=redis
# QUEUE_DRIVER=memory
# QUEUE_DRIVER=database
# FILESYSTEM_DISK=local
# FILESYSTEM_DISK=s3
# FILESYSTEM_DISK=gcs
# BROADCAST_DRIVER=local
# BROADCAST_DRIVER=redis
# QUDS_MONITOR=
# QUDS_INSIGHTS=false
# QUDS_INSIGHTS_TOKEN=
# HEALTH_WEBHOOK_URL=
# MIGRATE_ON_BOOT=false
# GOOGLE_CLIENT_ID=
# APPLE_CLIENT_ID=
# FIREBASE_API_KEY=

# Optional production limits (0 = unlimited / disabled — same as previous versions)
# MAX_CONCURRENT_REQUESTS=0
# REQUEST_TIMEOUT_SECONDS=0
# MAX_BODY_BYTES=0
# SHUTDOWN_TIMEOUT_SECONDS=15
# QUEUE_RESERVE_TIMEOUT_SECONDS=900
# MIGRATE_LOCK_SECONDS=30

# REDIS_HOST=127.0.0.1
# REDIS_PORT=6379
# REDIS_PASSWORD=
# REDIS_PREFIX=quds:

# S3_BUCKET=
# S3_REGION=us-east-1
# S3_ACCESS_KEY=
# S3_SECRET_KEY=
# S3_ENDPOINT=
# S3_PUBLIC_URL=

# GCS_BUCKET=
# GCS_PUBLIC_URL=
# GCS_ACCESS_TOKEN=
# GCS_CLIENT_EMAIL=
# GCS_PRIVATE_KEY=
''');

  // 2b. docker-compose (postgres + redis) for local development
  File('${root.path}/docker-compose.yml').writeAsStringSync('''
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: ${projectName}_db
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  pgdata:
''');

  // 3. lib/main.dart
  File('${root.path}/lib/main.dart').writeAsStringSync('''
import 'package:qserver/qserver.dart';
import 'controllers/task_controller.dart';

void main() async {
  final app = QudsServerApp();

  // 1. Register Core Engine Services
  await app.registerProviders([
    DatabaseServiceProvider(), // Boots Native PostgreSQL
    QueueServiceProvider(), // Boots Background Worker
    BroadcastServiceProvider(), // Boots WebSocket Engine
  ]);

  // 2. Apply Global Middleware
  app.router.use(CorsMiddleware());
  app.router.use(LoggerMiddleware()); // Live traffic + timestamps in the terminal
  app.router.use(ExceptionHandlerMiddleware()); // Catch, log, and review exceptions

  // 3. Configure WebSocket Channels
  Broadcast.channel('public.tasks', (user, channel) async {
    return true; // Allow anyone to listen to public tasks
  });

  // 4. Define HTTP Routes
  final taskController = TaskController();

  app.showWelcomePage = true;
  app.welcomeHeading = 'Welcome to Quds Task Manager API!';
  app.welcomeSubheading = 'Use this premium console to monitor server metrics, manage tasks, and trigger background worker executions.';
  app.welcomeCards = [
    DashboardCard(
      title: 'Developer Portal',
      content: 'This application is a demo project showcasing database migration, asynchronous queuing, event broadcasting via websockets, and robust request routing.',
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
''');

  // 4. lib/models/task.dart
  File('${root.path}/lib/models/task.dart').writeAsStringSync('''
import 'package:qserver/qserver.dart';

class Task extends StandardDbModel {
  final title = StringField(columnName: 'title', notNull: true);
  final description = StringField(columnName: 'description');

  @override
  List<FieldDefinition>? getFields() => [title, description];
}

// Defaulting to Postgres. Change to Mysql or Sqlite TableProvider if needed.
class TaskProvider extends PostgresStandardTableProvider<Task> {
  TaskProvider(super.connection, super.modelFactory,
      [super.tableName = 'tasks']);
}
''');

  // 5. lib/requests/create_task_request.dart
  File('${root.path}/lib/requests/create_task_request.dart').writeAsStringSync('''
import 'package:qserver/qserver.dart';

class CreateTaskRequest extends QudsFormRequest {
  CreateTaskRequest(super.request);

  @override
  Future<bool> authorize() async {
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
''');

  // 6. lib/jobs/process_task_job.dart
  File('${root.path}/lib/jobs/process_task_job.dart').writeAsStringSync('''
import 'package:qserver/qserver.dart';

class ProcessTaskJob extends Job {
  final Map<String, dynamic> taskData;

  ProcessTaskJob(this.taskData);

  @override
  String get label => 'ProcessTask \${taskData['title'] ?? ''}';

  @override
  Future<void> handle() async {
    await Future.delayed(const Duration(seconds: 2));
  }
}
''');

  // 7. lib/controllers/task_controller.dart
  File('${root.path}/lib/controllers/task_controller.dart').writeAsStringSync('''
import 'package:qserver/qserver.dart';
import '../models/task.dart';
import '../requests/create_task_request.dart';
import '../jobs/process_task_job.dart';

class TaskController {
  late final TaskProvider provider;

  TaskController() {
    // Dynamically grab the active connection from the IoC Container
    final connection =
        QudsContainer.resolve<DatabaseConnection>()
            as PostgresDatabaseConnection;
    provider = TaskProvider(connection, () => Task());
  }

  /// Fetches all tasks from the database
  Future<QudsResponse> index(QudsRequest request) async {
    await provider.initialize(); // Ensures table exists

    final tasks = await provider.select();

    // Convert the StandardDbModels into JSON maps
    final taskData = tasks
        .map(
          (t) => {
            'id': t.id.value,
            'title': t.title.value,
            'description': t.description.value,
          },
        )
        .toList();

    return QudsResponse.json({
      'message': 'Tasks retrieved successfully',
      'data': taskData,
    });
  }

  /// Validates, saves, broadcasts, and queues a new task
  Future<QudsResponse> store(QudsRequest request) async {
    final form = CreateTaskRequest(request);
    await form.validate(); // Halts execution on failure

    await provider.initialize();

    // 1. Create and populate the Model using fromMap
    final task = Task()..fromMap(request.body);

    // 2. Save using the Quds DB Provider
    await provider.insertEntry(task);

    final responsePayload = {
      'id': task.id.value,
      'title': task.title.value,
      'description': task.description.value,
    };

    // 3. Queue and Broadcast
    Queue.push(ProcessTaskJob(responsePayload));
    Broadcast.emit('public.tasks', 'TaskCreated', responsePayload);

    return QudsResponse.json({
      'message': 'Task created successfully!',
      'data': responsePayload,
    }, status: 201);
  }
}
''');

  print('Running dart pub get inside [$projectName]...');
  final pubGetResult = Process.runSync(
    'dart',
    ['pub', 'get'],
    workingDirectory: projectName,
    runInShell: true,
  );
  if (pubGetResult.exitCode != 0) {
    print('Warning: dart pub get failed:');
    print(pubGetResult.stderr);
  } else {
    print('Dependencies resolved successfully.');
  }

  print('Project [$projectName] created successfully!');
}

// Add these functions to bin/quds.dart

void _makeController(String name) {
  final dir = Directory('lib/controllers');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}/${name.toLowerCase()}.dart');

  if (file.existsSync()) {
    print('Warning: Controller $name already exists.');
    return;
  }

  final template =
      '''
import 'package:qserver/qserver.dart';

class $name {
  Future<QudsResponse> index(QudsRequest request) async {
    return QudsResponse.json({'message': 'Welcome to $name'});
  }

  Future<QudsResponse> store(QudsRequest request) async {
    // Handle creation logic
    return QudsResponse.json({'status': 'created'}, status: 201);
  }
}
''';

  file.writeAsStringSync(template);
  print('Controller [$name] created successfully at ${file.path}');
}

void _makeModel(String name) {
  final dir = Directory('lib/models');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}/${name.toLowerCase()}.dart');

  if (file.existsSync()) {
    print('Warning: Model $name already exists.');
    return;
  }

  final tableName = '${name.toLowerCase()}s';

  // Generates a StandardDbModel and its Postgres Provider by default
  final template =
      '''
import 'package:qserver/qserver.dart';

class $name extends StandardDbModel {
  // Define your fields here using the quds_db ecosystem
  final title = StringField(columnName: 'title', notNull: true);
  final createdAt = DateTimeField(columnName: 'created_at');

  @override
  List<FieldDefinition>? getFields() => [title, createdAt];
}

// Defaulting to Postgres. Change to Mysql or Sqlite TableProvider if needed.
class ${name}Provider extends PostgresStandardTableProvider<$name> {
  ${name}Provider(super.connection, super.modelFactory,
      [super.tableName = '$tableName']);
}
''';

  file.writeAsStringSync(template);
  print(
    'Model [$name] and ${name}Provider created successfully at ${file.path}',
  );
}

void _makeRequest(String name) {
  final dir = Directory('lib/requests');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}/${name.toLowerCase()}.dart');

  if (file.existsSync()) {
    print('Warning: Request $name already exists.');
    return;
  }

  final template = '''
import 'package:qserver/qserver.dart';

/// A Form Request that handles input validation and authorization.
class $name extends QudsFormRequest {
  $name(super.request);

  @override
  Future<bool> authorize() async {
    // Return true if the user is authorized to perform this request
    return true;
  }

  @override
  Map<String, QudsValidator> rules() {
    return {
      'title': IsRequired().isString().min(3).max(50),
    };
  }
}
''';

  file.writeAsStringSync(template);
  print('Request [$name] created successfully at ${file.path}');
}

Future<void> _serveCommand() async {
  print('Starting Quds Server...');
  print('Tip: To start with hot-reload instead, run: dart run --observe lib/main.dart\n');

  final process = await Process.start(
    'dart',
    ['run', 'lib/main.dart'],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );

  ProcessSignal.sigint.watch().listen((_) {
    process.kill();
    exit(0);
  });

  await process.exitCode;
}

void _makeJob(String name) {
  final dir = Directory('lib/jobs');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}/${name.toLowerCase()}.dart');

  final template =
      '''
import 'package:qserver/qserver.dart';

class $name extends Job {
  final Map<String, dynamic> data;

  // Pass whatever data the job needs to run via the constructor
  $name(this.data);

  @override
  Future<void> handle() async {
    // The queue worker shows a preloader for this job automatically.
  }
}
''';

  file.writeAsStringSync(template);
  print('Job [$name] created successfully at ${file.path}');
}

void _makeMiddleware(String name) {
  final dir = Directory('lib/middleware');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}/${name.toLowerCase()}.dart');
  if (file.existsSync()) {
    print('Warning: Middleware $name already exists.');
    return;
  }

  final template = '''
import 'package:qserver/qserver.dart';

class $name extends Middleware {
  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    // Before the next middleware / handler
    final response = await next(request);
    // After the response
    return response;
  }
}
''';

  file.writeAsStringSync(template);
  print('Middleware [$name] created successfully at ${file.path}');
}

void _makeProvider(String name) {
  final dir = Directory('lib/providers');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final file = File('${dir.path}/${name.toLowerCase()}.dart');
  if (file.existsSync()) {
    print('Warning: Provider $name already exists.');
    return;
  }

  final template = '''
import 'package:qserver/qserver.dart';

class $name extends ServiceProvider {
  @override
  void register() {
    // Bind services into the container here
  }

  @override
  Future<void> boot() async {
    // Start background work after all providers are registered
  }
}
''';

  file.writeAsStringSync(template);
  print('Provider [$name] created successfully at ${file.path}');
}

void _makeMigration(String name) {
  final safe = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:-]'), '')
      .replaceAll('.', '')
      .replaceAll('T', '')
      .substring(0, 14);
  final id = '${stamp}_$safe';
  final dir = Directory('database/migrations/$id');
  if (dir.existsSync()) {
    print('Warning: Migration $id already exists.');
    return;
  }
  dir.createSync(recursive: true);
  File('${dir.path}/up.sql').writeAsStringSync(
    '-- Migration: $id\n-- Write your UP SQL here.\n',
  );
  File('${dir.path}/down.sql').writeAsStringSync(
    '-- Migration: $id\n-- Write your DOWN SQL here.\n',
  );
  print('Migration [$id] created at ${dir.path}');
}

Future<void> _migrateCommand() async {
  await _withDatabaseConnection((connection) async {
    try {
      final count = await FileMigrationRunner(connection).migrate();
      print(count == 0 ? 'No pending migrations.' : 'Applied $count migration(s).');
    } on StateError catch (e) {
      print('Error: $e');
      exitCode = 1;
    }
  });
}

Future<void> _migrateRollbackCommand() async {
  await _withDatabaseConnection((connection) async {
    try {
      final ok = await FileMigrationRunner(connection).rollback();
      print(ok ? 'Rollback complete.' : 'Nothing to roll back.');
    } on StateError catch (e) {
      print('Error: $e');
      exitCode = 1;
    }
  });
}

Future<void> _withDatabaseConnection(
  Future<void> Function(DatabaseConnection connection) action,
) async {
  await QudsEnv.load();
  QudsContainer.clear();
  final provider = DatabaseServiceProvider();
  provider.register();
  await provider.boot();

  if (!QudsContainer.isRegistered<DatabaseConnection>()) {
    print('Error: Database connection failed. Check .env DB_* settings.');
    exitCode = 1;
    return;
  }

  final connection = QudsContainer.resolve<DatabaseConnection>();
  await action(connection);
}
