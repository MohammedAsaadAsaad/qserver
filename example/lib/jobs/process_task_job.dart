import 'package:qserver/qserver.dart';

class ProcessTaskJob extends Job {
  final Map<String, dynamic> taskData;

  ProcessTaskJob(this.taskData);

  @override
  Future<void> handle() async {
    print(
      '⏳ Background Worker: Processing heavy data for Task [${taskData['title']}]...',
    );

    // Simulate heavy network or I/O work
    await Future.delayed(const Duration(seconds: 3));

    print(
      '✅ Background Worker: Finished processing Task [${taskData['title']}].',
    );
  }
}
