import '../container/quds_env.dart';
import '../routing/router.dart';
import 'enums.dart';
import 'quds_response.dart';

/// Opt-in OpenAPI 3 document from registered routes. Off unless
/// `QUDS_OPENAPI=true`.
class OpenApiRoutes {
  /// Registers `GET /quds/openapi.json` when `QUDS_OPENAPI=true`.
  static void register(QudsRouter router) {
    final enabled = env<bool>('QUDS_OPENAPI', false) ?? false;
    if (!enabled) return;
    if (router.hasRoute(HttpMethod.get, '/quds/openapi.json')) return;

    router.get('/quds/openapi.json', (request) async {
      return QudsResponse.json(build(router));
    });
  }

  /// Builds an OpenAPI 3.0 document from [router.listRoutes].
  static Map<String, dynamic> build(QudsRouter router) {
    final title = env<String>('APP_NAME', 'Quds API') ?? 'Quds API';
    final paths = <String, dynamic>{};

    for (final route in router.listRoutes()) {
      if (route.path == '/quds/openapi.json') continue;
      final path = route.path.replaceAllMapped(
        RegExp(r'\{\*([a-zA-Z0-9_]+)\}'),
        (m) => '{${m.group(1)}}',
      );
      final item =
          (paths[path] as Map<String, dynamic>?) ?? <String, dynamic>{};
      item[route.method.value.toLowerCase()] = {
        'summary': '${route.method.value} $path',
        'responses': {
          '200': {'description': 'OK'},
        },
      };
      paths[path] = item;
    }

    return {
      'openapi': '3.0.3',
      'info': {
        'title': title,
        'version': env<String>('APP_VERSION', '1.0.0') ?? '1.0.0',
      },
      'paths': paths,
    };
  }
}
