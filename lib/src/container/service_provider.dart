import 'dart:async';

/// The base class for bootstrapping the application
abstract class ServiceProvider {
  /// Called first. Use this strictly to bind things into the QudsContainer.
  void register();

  /// Called after all other Service Providers have been registered.
  /// Use this to initialize routing, define gates, or register mappers.
  FutureOr<void> boot();
}
