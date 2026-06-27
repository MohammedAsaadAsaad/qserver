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

  // ... [Keep your existing _executePipeline and dispatch methods exactly as they were] ...

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

  Future<void> dispatch(HttpRequest rawRequest) async {
    try {
      final methodStr = rawRequest.method.toUpperCase();
      final requestMethod = HttpMethod.values.firstWhere(
        (m) => m.value == methodStr,
        orElse: () => throw Exception("Unsupported HTTP Method"),
      );

      final path = rawRequest.uri.path;

      Route? route;
      for (var r in _routes) {
        if (r.matches(requestMethod, path)) {
          route = r;
          break;
        }
      }

      final routeParams =
          route != null ? route.extractParams(path) : <String, String>{};
      final qudsRequest = await QudsRequest.from(
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
    } catch (e) {
      // Delegate all errors to the Global Handler!
      final res = GlobalExceptionHandler.handle(
        e is Exception ? e : Exception(e.toString()),
        null, // We could pass qudsRequest here if it successfully parsed
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
