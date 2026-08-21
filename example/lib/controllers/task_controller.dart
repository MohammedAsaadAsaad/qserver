import 'package:qserver/qserver.dart';
import '../jobs/process_task_job.dart';
import '../models/task.dart';
import '../requests/create_task_request.dart';

/// Tasks persist in Postgres when the database booted; otherwise in memory.
class TaskController {
  TaskProvider? _provider;
  final List<Map<String, dynamic>> _memory = [];
  int _nextId = 1;

  bool get _hasDb => QudsContainer.isRegistered<DatabaseConnection>();

  TaskProvider get _db {
    return _provider ??= TaskProvider(
      QudsContainer.resolve<DatabaseConnection>() as PostgresDatabaseConnection,
    );
  }

  Future<QudsResponse> index(QudsRequest request) async {
    if (_hasDb) {
      await _db.initialize();
      final tasks = await _db.select();
      return QudsResponse.json({
        'message': 'Tasks retrieved successfully',
        'storage': 'postgres',
        'data': tasks.map((t) => t.toMap()).toList(),
      });
    }

    return QudsResponse.json({
      'message': 'Tasks retrieved successfully',
      'storage': 'memory',
      'data': _memory,
    });
  }

  Future<QudsResponse> store(QudsRequest request) async {
    final form = CreateTaskRequest(request);
    await form.validate();

    late final Map<String, dynamic> payload;
    if (_hasDb) {
      await _db.initialize();
      final task = Task()..fromMap(request.body);
      await _db.insertEntry(task);
      payload = task.toMap();
    } else {
      payload = {
        'id': _nextId++,
        'title': request.input<String>('title'),
        'description': request.input<String>('description'),
        'status': 'pending',
      };
      _memory.add(payload);
    }

    await Queue.push(ProcessTaskJob(payload));
    Broadcast.emit('public.tasks', 'TaskCreated', payload);

    return QudsResponse.json({
      'message': 'Task created — processing in the background',
      'storage': _hasDb ? 'postgres' : 'memory',
      'data': payload,
    }, status: 201);
  }
}
