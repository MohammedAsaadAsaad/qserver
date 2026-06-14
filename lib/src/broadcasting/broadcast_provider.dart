import '../container/service_provider.dart';
import '../container/quds_container.dart';
import '../http/quds_response.dart';
import '../routing/router.dart';
import 'broadcast_manager.dart';

class BroadcastServiceProvider extends ServiceProvider {
  @override
  void register() {
    // Bind the manager as a singleton to maintain the socket lists globally
    QudsContainer.singleton<BroadcastManager>(BroadcastManager());
  }

  @override
  void boot() {
    final router = QudsContainer.resolve<QudsRouter>();
    final manager = QudsContainer.resolve<BroadcastManager>();

    // Automatically inject the WebSocket entry point into the app
    router.get('/ws', (request) async {
      await manager.handleUpgrade(request.rawRequest);

      // Return the special upgraded response so the router doesn't crash
      return QudsResponse.upgraded();
    });

    print('📻 WebSocket Broadcasting Engine initialized at /ws');
  }
}
