import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';
import '../../container/quds_env.dart';

typedef InsightsAuthorizer = Future<bool> Function(QudsRequest request);

/// Protects Admin Insights routes. Default: Bearer [QUDS_INSIGHTS_TOKEN].
/// Replace later with JWT role checks via [authorizer].
class InsightsAuthMiddleware extends Middleware {
  final InsightsAuthorizer? authorizer;

  InsightsAuthMiddleware({this.authorizer});

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final ok = authorizer != null
        ? await authorizer!(request)
        : await _defaultTokenGate(request);
    if (!ok) {
      return QudsResponse.error('Unauthorized', status: 401);
    }
    return next(request);
  }

  static Future<bool> _defaultTokenGate(QudsRequest request) async {
    final expected = env<String>('QUDS_INSIGHTS_TOKEN');
    if (expected == null || expected.isEmpty) {
      // Insights enabled without a token is refused (fail closed).
      return false;
    }
    final header = request.header('authorization');
    String? provided;
    if (header != null && header.toLowerCase().startsWith('bearer ')) {
      provided = header.substring(7).trim();
    }
    provided ??= request.attributes['insightsToken'] as String?;
    return provided != null && provided == expected;
  }
}
