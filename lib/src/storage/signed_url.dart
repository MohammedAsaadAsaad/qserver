import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../container/quds_env.dart';

/// HMAC query signatures for local (or non-S3) temporary URLs.
class SignedUrl {
  static String get _secret => env<String>(
        'APP_KEY',
        'qserver_fallback_secret_key_change_in_production',
      )!;

  static String sign(String path, int expiresEpochSeconds) {
    final payload = '$path|$expiresEpochSeconds';
    return base64Url
        .encode(
          Hmac(sha256, utf8.encode(_secret))
              .convert(utf8.encode(payload))
              .bytes,
        )
        .replaceAll('=', '');
  }

  /// `/quds/files?path=...&expires=...&sig=...`
  static String issue(
    String path, {
    Duration ttl = const Duration(minutes: 15),
    String prefix = '/quds/files',
  }) {
    final key = path.replaceAll(RegExp(r'^/+'), '');
    final expires =
        DateTime.now().toUtc().add(ttl).millisecondsSinceEpoch ~/ 1000;
    final sig = sign(key, expires);
    return '$prefix?path=${Uri.encodeQueryComponent(key)}'
        '&expires=$expires&sig=${Uri.encodeQueryComponent(sig)}';
  }

  static bool valid({
    required String path,
    required String expires,
    required String sig,
  }) {
    final key = path.replaceAll(RegExp(r'^/+'), '');
    if (key.contains('..') || key.contains(String.fromCharCode(0))) {
      return false;
    }
    final epoch = int.tryParse(expires);
    if (epoch == null) return false;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if (epoch < now) return false;
    final expected = sign(key, epoch);
    return _equal(sig, expected);
  }

  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }
}
