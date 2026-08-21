import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../container/service_provider.dart';
import '../logging/quds_log.dart';
import 'cache_driver.dart';
import 'memory_cache_driver.dart';
import 'redis_cache_driver.dart';

/// Opt-in provider that binds [CacheDriver] from `CACHE_DRIVER`.
///
/// Apps that never register this keep the default [MemoryCacheDriver]
/// from [QudsServerApp]. Prefer env-based auto-config via
/// `_configureDriversFromEnv` when `CACHE_DRIVER` is set.
class CacheServiceProvider extends ServiceProvider {
  @override
  void register() {
    final driver = (env<String>('CACHE_DRIVER', 'memory') ?? 'memory')
        .toLowerCase();
    switch (driver) {
      case 'redis':
        QudsContainer.singleton<CacheDriver>(RedisCacheDriver());
        Log.info('Driver redis', component: 'cache');
        break;
      default:
        QudsContainer.singleton<CacheDriver>(MemoryCacheDriver());
        Log.info('Driver memory', component: 'cache');
    }
  }

  @override
  Future<void> boot() async {}

  @override
  Future<void> shutdown() async {
    if (QudsContainer.isRegistered<CacheDriver>()) {
      final driver = QudsContainer.resolve<CacheDriver>();
      if (driver is RedisCacheDriver) {
        await driver.close();
      }
    }
  }
}
