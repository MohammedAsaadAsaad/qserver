import '../container/service_provider.dart';
import '../logging/quds_log.dart';

/// Opt-in provider for the [Schedule] facade.
///
/// Not auto-registered by [QudsServerApp]. Apps that use
/// `Schedule.every(...)` should register this (or call schedules after the
/// queue worker is running).
class ScheduleServiceProvider extends ServiceProvider {
  @override
  void register() {}

  @override
  Future<void> boot() async {
    Log.info('Schedule service ready (interval jobs via Queue)');
  }
}
