import 'cache_driver.dart';

class _CacheEntry {
  final dynamic value;
  final DateTime? expiresAt;

  _CacheEntry(this.value, this.expiresAt);

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// In-process cache with optional per-key TTL.
class MemoryCacheDriver implements CacheDriver {
  final Map<String, _CacheEntry> _store = {};

  @override
  Future<dynamic> get(String key) async {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  @override
  Future<void> put(String key, dynamic value, {Duration? ttl}) async {
    final expiresAt = ttl == null ? null : DateTime.now().add(ttl);
    _store[key] = _CacheEntry(value, expiresAt);
  }

  @override
  Future<void> forget(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> flush() async {
    _store.clear();
  }
}
