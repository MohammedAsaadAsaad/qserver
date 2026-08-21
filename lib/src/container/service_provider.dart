import 'dart:async';

/// The base class for bootstrapping the application
abstract class ServiceProvider {
  /// Called first. Use this strictly to bind things into the QudsContainer.
  void register();

  /// Called after all other Service Providers have been registered.
  /// Use this to initialize routing, define gates, or register mappers.
  FutureOr<void> boot();

  /// Called during [QudsServerApp.close]. Default is a no-op so existing
  /// providers keep compiling without changes.
  FutureOr<void> shutdown() {}
}
