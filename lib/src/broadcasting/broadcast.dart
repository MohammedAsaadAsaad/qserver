import '../container/quds_container.dart';
import 'broadcast_manager.dart';

/// A global facade for real-time WebSockets
class Broadcast {
  /// Defines an authorization rule for a private channel
  /// e.g., Broadcast.channel('chat.*', (user, channel) => user != null);
  static void channel(String name, ChannelAuthCallback check) {
    final manager = QudsContainer.resolve<BroadcastManager>();
    manager.defineChannel(name, check);
  }

  /// Broadcasts an event to everyone subscribed to the channel
  static void emit(
    String channelName,
    String event,
    Map<String, dynamic> data,
  ) {
    final manager = QudsContainer.resolve<BroadcastManager>();
    manager.emit(channelName, event, data);
  }
}
