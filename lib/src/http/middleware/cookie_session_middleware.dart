import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../container/quds_env.dart';
import '../middleware.dart';
import '../quds_request.dart';
import '../quds_response.dart';

/// Signed cookie bag at `request.attributes['session']`. Opt-in.
class CookieSessionMiddleware extends Middleware {
  final String cookieName;
  final Duration ttl;
  final bool httpOnly;
  final String sameSite;
  final bool secure;

  CookieSessionMiddleware({
    this.cookieName = 'quds_session',
    this.ttl = const Duration(hours: 12),
    this.httpOnly = true,
    this.sameSite = 'Lax',
    this.secure = false,
  });

  @override
  Future<QudsResponse> handle(QudsRequest request, NextMiddleware next) async {
    final bag = _decode(request.cookie(cookieName)) ?? <String, dynamic>{};
    bag.putIfAbsent('csrf', () => _randomToken());
    request.attributes['session'] = bag;

    final response = await next(request);
    final current = Session.of(request);
    response.headers['Set-Cookie'] = _setCookie(_encode(current));
    return response;
  }

  String _setCookie(String value) {
    final parts = <String>[
      '$cookieName=$value',
      'Path=/',
      'Max-Age=${ttl.inSeconds}',
      'SameSite=$sameSite',
    ];
    if (httpOnly) parts.add('HttpOnly');
    if (secure) parts.add('Secure');
    return parts.join('; ');
  }

  static String _secret() => env<String>(
        'APP_KEY',
        'qserver_fallback_secret_key_change_in_production',
      )!;

  static String _encode(Map<String, dynamic> bag) {
    final payload = base64Url.encode(utf8.encode(jsonEncode(bag)));
    final sig = base64Url.encode(
      Hmac(sha256, utf8.encode(_secret())).convert(utf8.encode(payload)).bytes,
    );
    return '$payload.$sig';
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('.');
    if (parts.length != 2) return null;
    final expected = base64Url.encode(
      Hmac(sha256, utf8.encode(_secret())).convert(utf8.encode(parts[0])).bytes,
    );
    if (!_equal(parts[1], expected)) return null;
    try {
      final json = utf8.decode(base64Url.decode(parts[0]));
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }

  static String _randomToken() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Mutable cookie session map. Empty unless [CookieSessionMiddleware] ran.
class Session {
  static Map<String, dynamic> of(QudsRequest request) {
    final existing = request.attributes['session'];
    if (existing is Map<String, dynamic>) return existing;
    if (existing is Map) {
      final copy = Map<String, dynamic>.from(existing);
      request.attributes['session'] = copy;
      return copy;
    }
    final bag = <String, dynamic>{};
    request.attributes['session'] = bag;
    return bag;
  }
}
