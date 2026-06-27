typedef JsonFactory<T> = T Function(Map<String, dynamic> json);

/// A centralized registry for instantiating DTOs and Models automatically
class QudsMapper {
  static final Map<Type, dynamic> _factories = {};

  /// Registers a factory blueprint for a specific type
  static void register<T>(JsonFactory<T> factory) {
    _factories[T] = factory;
  }

  /// Instantiates a single object of type T from a JSON map
  static T? build<T>(dynamic json) {
    if (json == null) return null;

    final factory = _factories[T] as JsonFactory<T>?;
    if (factory == null) {
      throw Exception(
        "QudsMapper Error: No factory registered for type $T. "
        "Ensure you registered it using QudsMapper.register<$T>(...) in your ServiceProvider.",
      );
    }

    return factory(json as Map<String, dynamic>);
  }
}
