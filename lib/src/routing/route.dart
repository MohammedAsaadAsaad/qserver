import '../http/enums.dart';
import '../http/quds_request.dart';
import '../http/quds_response.dart';
import '../http/middleware.dart';

typedef RouteHandler = Future<QudsResponse> Function(QudsRequest request);

class Route {
  final HttpMethod method;
  final String path;
  final RouteHandler handler;
  final List<Middleware> middleware;

  late final RegExp _pathRegex;
  final List<String> _paramNames = [];

  Route(this.method, this.path, this.handler, {this.middleware = const []}) {
    _compilePath();
  }

  void _compilePath() {
    String regexPath = path.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_]+)\}'), (
      match,
    ) {
      _paramNames.add(match.group(1)!);
      return r'([^/]+)';
    });
    _pathRegex = RegExp('^$regexPath\$');
  }

  bool matches(HttpMethod requestMethod, String requestPath) {
    if (method != requestMethod) return false;
    return _pathRegex.hasMatch(requestPath);
  }

  Map<String, String> extractParams(String requestPath) {
    final match = _pathRegex.firstMatch(requestPath);
    final Map<String, String> params = {};
    if (match != null) {
      for (int i = 0; i < _paramNames.length; i++) {
        params[_paramNames[i]] = match.group(i + 1)!;
      }
    }
    return params;
  }
}
