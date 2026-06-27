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
    provider = TaskProvider(connection);
  }

  /// Fetches all tasks from the database
  Future<QudsResponse> index(QudsRequest request) async {
    await provider.initialize(); // Ensures table exists

    final tasks = await provider.select();

    // Convert the StandardDbModels into JSON maps
    final taskData = tasks.map((t) => t.toMap()).toList();

    return QudsResponse.json({
      'message': 'Tasks retrieved successfully',
      'data': taskData,
    });
  }

  /// Validates, saves, broadcasts, and queues a new task
  Future<QudsResponse> store(QudsRequest request) async {
    final form = CreateTaskRequest(request);
    await form.validate();

    await provider.initialize();

    // 1. Create and populate the Model
    final task = Task()..fromMap(request.body);

    // 2. Save using the Quds DB Provider
    await provider.insertEntry(task);

    final responsePayload = task.toMap();

    // 3. Queue and Broadcast
    Queue.push(ProcessTaskJob(responsePayload));
    Broadcast.emit('public.tasks', 'TaskCreated', responsePayload);

    return QudsResponse.json({
      'message': 'Task created successfully!',
      'data': responsePayload,
    }, status: 201);
  }
}
