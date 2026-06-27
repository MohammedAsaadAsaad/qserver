import 'package:backend/main.dart' as server_app;
import 'package:test/test.dart';

void main() {
  test('Run Chat Server', () async {
    // Disable test timeout to keep the backend running indefinitely
    await server_app.main();
  }, timeout: Timeout.none);
}
