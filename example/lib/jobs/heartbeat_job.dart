import 'package:qserver/qserver.dart';

class HeartbeatJob extends Job {
  @override
  String get label => 'Heartbeat';

  @override
  Future<void> handle() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    Log.debug('Scheduler pulse', component: 'schedule');
  }
}
