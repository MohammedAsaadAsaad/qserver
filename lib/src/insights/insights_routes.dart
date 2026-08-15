import '../container/quds_env.dart';
import '../exceptions/exception_log.dart';
import '../http/enums.dart';
import '../http/middleware/insights_auth_middleware.dart';
import '../http/quds_response.dart';
import '../routing/router.dart';

/// Registers Admin Insights routes when [QUDS_INSIGHTS]=true.
class InsightsRoutes {
  /// Optional override for admin authorization (JWT role, etc.).
  static InsightsAuthorizer? authorizer;

  static void register(QudsRouter router) {
    final enabled = env<bool>('QUDS_INSIGHTS', false) ?? false;
    if (!enabled) return;

    final gate = InsightsAuthMiddleware(authorizer: authorizer);

    if (!router.hasRoute(HttpMethod.get, '/quds/insights/exceptions')) {
      router.get(
        '/quds/insights/exceptions',
        (request) async {
          final limit =
              int.tryParse(request.query('limit') ?? '')?.clamp(1, 100) ?? 50;
          final items = ExceptionLog.recent.reversed.take(limit).map((r) {
            return r.toJson(includeStack: request.query('stack') != '0');
          }).toList();
          return QudsResponse.json({
            'total': ExceptionLog.total,
            'count': items.length,
            'data': items,
          });
        },
        middleware: [gate],
      );
    }

    if (!router.hasRoute(HttpMethod.get, '/quds/insights/health-summary')) {
      router.get(
        '/quds/insights/health-summary',
        (request) async {
          final last = ExceptionLog.recent.isEmpty
              ? null
              : ExceptionLog.recent.last.toJson(includeStack: false);
          return QudsResponse.json({
            'status': 'ok',
            'exceptionsTotal': ExceptionLog.total,
            'exceptionsInMemory': ExceptionLog.recent.length,
            'lastException': last,
          });
        },
        middleware: [gate],
      );
    }
  }
}
