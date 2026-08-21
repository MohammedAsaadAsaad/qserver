import 'package:qserver/qserver.dart';

/// Longer job so the queue preloader is easy to see in the terminal.
class ExportReportJob extends Job {
  final String name;

  ExportReportJob({this.name = 'weekly'});

  @override
  String get label => 'Export report ($name)';

  @override
  Future<void> handle() async {
    await Future<void>.delayed(const Duration(seconds: 12));
  }
}
