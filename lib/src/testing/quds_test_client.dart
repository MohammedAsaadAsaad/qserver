import '../http/enums.dart';
import '../http/quds_response.dart';
import '../routing/router.dart';

/// Lightweight HTTP test helper that exercises a [QudsRouter] without binding a port.
class QudsTestClient {
  final QudsRouter router;

  QudsTestClient(this.router);

  Future<QudsResponse> get(
    String path, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) {
    return router.dispatchTest(
      HttpMethod.get,
      path,
      query: query,
      headers: headers,
    );
  }

  Future<QudsResponse> post(
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) {
    return router.dispatchTest(
      HttpMethod.post,
      path,
      body: body,
      query: query,
      headers: headers,
    );
  }

  Future<QudsResponse> put(
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) {
    return router.dispatchTest(
      HttpMethod.put,
      path,
      body: body,
      query: query,
      headers: headers,
    );
  }

  Future<QudsResponse> delete(
    String path, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
  }) {
    return router.dispatchTest(
      HttpMethod.delete,
      path,
      query: query,
      headers: headers,
    );
  }
}
