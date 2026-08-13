import 'dart:io';
import '../exceptions/exception_handler.dart';
import 'route.dart';
import '../http/enums.dart';
import '../http/quds_request.dart';
import '../http/quds_response.dart';
import '../http/middleware.dart';

class QudsRouter {
  final List<Route> _routes = [];
  final List<Middleware> _globalMiddleware = [];

  // State variables for route grouping
  String _currentPrefix = '';
  List<Middleware> _currentGroupMiddleware = [];

  /// Snapshot of registered routes (method + path) for debugging / CLI.
  List<({HttpMethod method, String path})> listRoutes() {
    return _routes.map((r) => (method: r.method, path: r.path)).toList();
  }

  void use(Middleware middleware) {
    _globalMiddleware.add(middleware);
  }

  /// Groups routes under a common prefix and/or shared middleware.
  /// Supports nested groups.
  void group({
    String prefix = '',
    List<Middleware> middleware = const [],
    required void Function(QudsRouter) callback,
  }) {
    // Save previous state to support nesting
    final previousPrefix = _currentPrefix;
    final previousMiddleware = List<Middleware>.from(_currentGroupMiddleware);

    // Apply new group state
    _currentPrefix = previousPrefix + prefix;
    _currentGroupMiddleware.addAll(middleware);

    // Execute the callback where the user defines their routes
    callback(this);

    // Restore previous state after the group is fully defined
    _currentPrefix = previousPrefix;
    _currentGroupMiddleware = previousMiddleware;
  }

  /// Helper to build the final path
  String _buildPath(String path) {
    final fullPath = '$_currentPrefix$path';
    return fullPath.replaceAll('//', '/'); // Clean up double slashes
  }

  void get(
    String path,
    RouteHandler handler, {
    List<Middleware> middleware = const [],
  }) {
    _routes.add(
      Route(
        HttpMethod.get,
        _buildPath(path),
        handler,
        middleware: [..._currentGroupMiddleware, ...middleware],
      ),
    );
  }

  void post(
    String path,
    RouteHandler handler, {
    List<Middleware> middleware = const [],
  }) {
    _routes.add(
      Route(
        HttpMethod.post,
        _buildPath(path),
        handler,
        middleware: [..._currentGroupMiddleware, ...middleware],
      ),
    );
  }

  void put(
    String path,
    RouteHandler handler, {
    List<Middleware> middleware = const [],
  }) {
    _routes.add(
      Route(
        HttpMethod.put,
        _buildPath(path),
        handler,
        middleware: [..._currentGroupMiddleware, ...middleware],
      ),
    );
  }

  void delete(
    String path,
    RouteHandler handler, {
    List<Middleware> middleware = const [],
  }) {
    _routes.add(
      Route(
        HttpMethod.delete,
        _buildPath(path),
        handler,
        middleware: [..._currentGroupMiddleware, ...middleware],
      ),
    );
  }

  Future<QudsResponse> _executePipeline(
    QudsRequest request,
    Route route,
  ) async {
    final allMiddleware = [..._globalMiddleware, ...route.middleware];
    int index = 0;

    Future<QudsResponse> next(QudsRequest req) async {
      if (index < allMiddleware.length) {
        final currentMiddleware = allMiddleware[index++];
        return await currentMiddleware.handle(req, next);
      } else {
        return await route.handler(req);
      }
    }

    return await next(request);
  }

  bool hasRoute(HttpMethod method, String path) {
    return _routes.any((r) => r.method == method && r.path == path);
  }

  Route? _findRoute(HttpMethod method, String path) {
    for (var r in _routes) {
      if (r.matches(method, path)) return r;
    }
    return null;
  }

  /// Dispatches a prepared [QudsRequest] through matching + middleware pipeline.
  Future<QudsResponse> handle(QudsRequest request) async {
    final methodStr = request.method.toUpperCase();
    final requestMethod = HttpMethod.values.firstWhere(
      (m) => m.value == methodStr,
      orElse: () => throw Exception("Unsupported HTTP Method"),
    );

    final path = request.path;
    final route = _findRoute(requestMethod, path);

    if (route != null) {
      return await _executePipeline(request, route);
    }

    final dummy404Route = Route(
      requestMethod,
      path,
      (req) async => QudsResponse.error("Route Not Found", status: 404),
    );
    return await _executePipeline(request, dummy404Route);
  }

  /// Test-friendly dispatch that builds a synthetic request and returns the response.
  Future<QudsResponse> dispatchTest(
    HttpMethod method,
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    String ip = '127.0.0.1',
  }) async {
    final route = _findRoute(method, path);
    final routeParams =
        route != null ? route.extractParams(path) : <String, String>{};

    final request = QudsRequest.synthetic(
      method: method.value,
      path: path,
      body: body,
      routeParams: routeParams,
      queryParameters: query,
      headers: headers,
      ip: ip,
    );

    try {
      if (route != null) {
        return await _executePipeline(request, route);
      }
      final dummy404Route = Route(
        method,
        path,
        (req) async => QudsResponse.error("Route Not Found", status: 404),
      );
      return await _executePipeline(request, dummy404Route);
    } catch (e, stack) {
      return GlobalExceptionHandler.handle(
        e,
        stackTrace: stack,
        request: request,
      );
    }
  }

  Future<void> dispatch(HttpRequest rawRequest) async {
    QudsRequest? qudsRequest;
    try {
      final methodStr = rawRequest.method.toUpperCase();
      final requestMethod = HttpMethod.values.firstWhere(
        (m) => m.value == methodStr,
        orElse: () => throw Exception("Unsupported HTTP Method"),
      );

      final path = rawRequest.uri.path;

      final route = _findRoute(requestMethod, path);

      final routeParams =
          route != null ? route.extractParams(path) : <String, String>{};
      qudsRequest = await QudsRequest.from(
        rawRequest,
        routeParams: routeParams,
      );

      QudsResponse response;
      if (route != null) {
        response = await _executePipeline(qudsRequest, route);
      } else {
        final dummy404Route = Route(
          requestMethod,
          path,
          (req) async => QudsResponse.error("Route Not Found", status: 404),
        );
        response = await _executePipeline(qudsRequest, dummy404Route);
      }
      await response.send(rawRequest.response);
    } catch (e, stack) {
      final res = GlobalExceptionHandler.handle(
        e,
        stackTrace: stack,
        request: qudsRequest,
      );
      await res.send(rawRequest.response);
    }
  }
}

class QudsValidationException implements Exception {
  final Map<String, List<String>> errors;
  QudsValidationException(this.errors);
}

class QudsAuthorizationException implements Exception {
  final String message;
  QudsAuthorizationException(this.message);
}
