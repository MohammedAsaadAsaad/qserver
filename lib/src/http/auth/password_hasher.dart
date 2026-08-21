import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../container/quds_env.dart';

/// Salted SHA-256 password hashes (`v1$salt$digest`).
class PasswordHasher {
  static String get _pepper => env<String>(
        'APP_KEY',
        'qserver_fallback_secret_key_change_in_production',
      )!;

  static String hash(String password) {
    final salt = _randomHex(16);
    return 'v1\$$salt\$${_digest(salt, password)}';
  }

  static bool verify(String password, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 3 || parts[0] != 'v1') return false;
    final expected = _digest(parts[1], password);
    return _constantTimeEquals(expected, parts[2]);
  }

  static String _digest(String salt, String password) {
    return sha256.convert(utf8.encode('$salt.$password.$_pepper')).toString();
  }

  static String _randomHex(int bytes) {
    final rand = Random.secure();
    return List.generate(bytes, (_) => rand.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
