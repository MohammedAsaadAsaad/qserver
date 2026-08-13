import '../container/quds_container.dart';
import 'cache_driver.dart';
import 'memory_cache_driver.dart';

/// Global facade for caching values (Laravel-style).
class Cache {
  static CacheDriver _driver() {
    if (!QudsContainer.isRegistered<CacheDriver>()) {
      QudsContainer.singleton<CacheDriver>(MemoryCacheDriver());
    }
    return QudsContainer.resolve<CacheDriver>();
  }

  static Future<T?> get<T>(String key) async {
    final value = await _driver().get(key);
    if (value == null) return null;
    return value as T?;
  }

  static Future<void> put(String key, dynamic value, {Duration? ttl}) {
    return _driver().put(key, value, ttl: ttl);
  }

  static Future<void> forget(String key) => _driver().forget(key);

  static Future<void> flush() => _driver().flush();
}
