import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Opt-in rate limiter. Not applied globally unless the developer adds it.
class RateLimitMiddleware extends Middleware {
  final int max;
  final Duration window;
  final String Function(QudsRequest request)? keyResolver;

  final Map<String, List<DateTime>> _hits = {};

  RateLimitMiddleware({
    this.max = 60,
    this.window = const Duration(minutes: 1),
    this.keyResolver,
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final key = (keyResolver ?? _defaultKey)(request);
    final now = DateTime.now();
    final cutoff = now.subtract(window);

    final stamps = (_hits[key] ?? <DateTime>[])
      ..removeWhere((t) => t.isBefore(cutoff));

    if (stamps.length >= max) {
      _hits[key] = stamps;
      return QudsResponse.error(
        'Too Many Requests',
        status: 429,
      );
    }

    stamps.add(now);
    _hits[key] = stamps;
    return next(request);
  }

  static String _defaultKey(QudsRequest request) => request.ip;
}
