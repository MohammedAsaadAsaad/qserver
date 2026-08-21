import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'storage_disk.dart';

/// Google Cloud Storage disk via the JSON API.
///
/// Auth (first match):
/// - [accessToken] / `GCS_ACCESS_TOKEN`
/// - service account `GCS_CLIENT_EMAIL` + `GCS_PRIVATE_KEY` (JWT bearer grant)
///
/// Configure with `FILESYSTEM_DISK=gcs` and `GCS_BUCKET`.
class GcsStorageDisk implements StorageDisk {
  final String bucket;
  final String? publicUrlBase;
  final String? accessToken;
  final String? clientEmail;
  final String? privateKeyPem;
  final http.Client _client;

  String? _cachedToken;
  DateTime? _cachedTokenExpiry;

  GcsStorageDisk({
    String? bucket,
    String? publicUrlBase,
    String? accessToken,
    String? clientEmail,
    String? privateKeyPem,
    http.Client? client,
  })  : bucket = bucket ?? env<String>('GCS_BUCKET') ?? '',
        publicUrlBase = publicUrlBase ?? env<String>('GCS_PUBLIC_URL'),
        accessToken = accessToken ?? env<String>('GCS_ACCESS_TOKEN'),
        clientEmail = clientEmail ?? env<String>('GCS_CLIENT_EMAIL'),
        privateKeyPem = privateKeyPem ?? env<String>('GCS_PRIVATE_KEY'),
        _client = client ?? http.Client();

  Uri _objectUri(String path, {bool upload = false}) {
    final key = path.replaceAll(RegExp(r'^/+'), '');
    if (upload) {
      return Uri.parse(
        'https://storage.googleapis.com/upload/storage/v1/b/$bucket/o'
        '?uploadType=media&name=${Uri.encodeQueryComponent(key)}',
      );
    }
    return Uri.parse(
      'https://storage.googleapis.com/storage/v1/b/$bucket/o/${Uri.encodeComponent(key)}',
    );
  }

  Future<Map<String, String>> _headers({String? contentType}) async {
    final token = await _resolveToken();
    return {
      'Authorization': 'Bearer $token',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  Future<String> _resolveToken() async {
    final staticToken = accessToken;
    if (staticToken != null && staticToken.isNotEmpty) return staticToken;

    if (_cachedToken != null &&
        _cachedTokenExpiry != null &&
        DateTime.now().isBefore(_cachedTokenExpiry!)) {
      return _cachedToken!;
    }

    final email = clientEmail;
    final pem = privateKeyPem?.replaceAll(r'\n', '\n');
    if (email == null || email.isEmpty || pem == null || pem.isEmpty) {
      Log.warning(
        'GCS disk missing GCS_ACCESS_TOKEN or GCS_CLIENT_EMAIL / GCS_PRIVATE_KEY',
      );
      throw StateError('GCS storage is not configured');
    }

    final now = DateTime.now().toUtc();
    final assertion = JWT(
      {
        'iss': email,
        'sub': email,
        'aud': 'https://oauth2.googleapis.com/token',
        'scope': 'https://www.googleapis.com/auth/devstorage.full_control',
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': now.add(const Duration(minutes: 55)).millisecondsSinceEpoch ~/ 1000,
      },
    ).sign(RSAPrivateKey(pem), algorithm: JWTAlgorithm.RS256);

    final response = await _client.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
      },
    );
    if (response.statusCode >= 300) {
      throw StateError(
        'GCS token exchange failed (${response.statusCode}): ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw StateError('GCS token exchange returned no access_token');
    }
    _cachedToken = token;
    _cachedTokenExpiry = DateTime.now().add(const Duration(minutes: 50));
    return token;
  }

  void _ensureBucket() {
    if (bucket.isEmpty) {
      throw StateError('GCS storage is not configured (GCS_BUCKET)');
    }
  }

  @override
  Future<String> put(String path, List<int> bytes) async {
    _ensureBucket();
    final uri = _objectUri(path, upload: true);
    final response = await _client.post(
      uri,
      headers: await _headers(contentType: 'application/octet-stream'),
      body: bytes,
    );
    if (response.statusCode >= 300) {
      throw StateError(
        'GCS put failed (${response.statusCode}): ${response.body}',
      );
    }
    return url(path) ?? uri.toString();
  }

  @override
  Future<bool> exists(String path) async {
    _ensureBucket();
    final response = await _client.get(
      _objectUri(path),
      headers: await _headers(),
    );
    return response.statusCode == 200;
  }

  @override
  Future<void> delete(String path) async {
    _ensureBucket();
    final response = await _client.delete(
      _objectUri(path),
      headers: await _headers(),
    );
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw StateError(
        'GCS delete failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  String? url(String path) {
    final key = path.replaceAll(RegExp(r'^/+'), '');
    final base = publicUrlBase;
    if (base != null && base.isNotEmpty) {
      final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      return '$trimmed/$key';
    }
    if (bucket.isEmpty) return null;
    return 'https://storage.googleapis.com/$bucket/$key';
  }
}
