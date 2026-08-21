import 'package:qserver/qserver.dart';

class ProcessTaskJob extends Job {
  final Map<String, dynamic> taskData;

  ProcessTaskJob(this.taskData);

  @override
  String get label => 'ProcessTask ${taskData['title'] ?? 'untitled'}';

  @override
  Future<void> handle() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    await Future<void>.delayed(const Duration(seconds: 4));
  }
}
