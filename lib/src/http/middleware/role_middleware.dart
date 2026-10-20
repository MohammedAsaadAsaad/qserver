import '../../routing/router.dart';
import '../auth/auth.dart';
import '../auth/gate.dart';
import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Requires `user.role` or `user.roles` to intersect [roles]. Opt-in per route.
class RoleMiddleware extends Middleware {
  final List<String> roles;

  RoleMiddleware(this.roles);

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final user = _resolveUser(request);
    if (user == null) {
      throw QudsAuthorizationException(
        'Unauthenticated. Please provide a valid Bearer token.',
      );
    }
    if (!_hasRole(user)) {
      throw QudsAuthorizationException('This action is unauthorized.');
    }
    request.attributes['user'] ??= user;
    return next(request);
  }

  bool _hasRole(dynamic user) {
    if (user is! Map) return false;
    final wanted = roles.map((r) => r.toLowerCase()).toSet();
    final role = user['role']?.toString().toLowerCase();
    if (role != null && wanted.contains(role)) return true;
    final list = user['roles'];
    if (list is List) {
      for (final item in list) {
        if (wanted.contains(item.toString().toLowerCase())) return true;
      }
    }
    return false;
  }

  static dynamic _resolveUser(QudsRequest request) {
    final existing = request.user();
    if (existing != null) return existing;
    final header = request.header('authorization');
    if (header == null || !header.toLowerCase().startsWith('bearer ')) {
      return null;
    }
    return Auth.verify(header.substring(7).trim());
  }
}

/// Requires [Gate.allows] for [ability]. Opt-in per route.
class GateMiddleware extends Middleware {
  final String ability;
  final Object? argument;

  GateMiddleware(this.ability, {this.argument});

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final user = RoleMiddleware._resolveUser(request);
    if (user == null) {
      throw QudsAuthorizationException(
        'Unauthenticated. Please provide a valid Bearer token.',
      );
    }
    request.attributes['user'] ??= user;
    Gate.authorize(ability, user, argument);
    return next(request);
  }
}
