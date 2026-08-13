/// Contract for cache backends (memory, Redis, …).
abstract class CacheDriver {
  Future<dynamic> get(String key);
  Future<void> put(String key, dynamic value, {Duration? ttl});
  Future<void> forget(String key);
  Future<void> flush();
}
