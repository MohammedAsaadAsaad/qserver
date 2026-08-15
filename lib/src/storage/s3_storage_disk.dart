import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../container/quds_env.dart';
import '../logging/quds_log.dart';
import 'storage_disk.dart';

/// Minimal S3-compatible disk using HTTP + AWS Signature Version 4.
///
/// Supports [put], [exists] (HEAD), and [delete]. Listing and multipart
/// uploads are out of scope. Configure via `S3_*` / `AWS_*` env vars.
class S3StorageDisk implements StorageDisk {
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;
  final String? endpoint;
  final String? publicUrlBase;
  final http.Client _client;

  S3StorageDisk({
    String? bucket,
    String? region,
    String? accessKey,
    String? secretKey,
    String? endpoint,
    String? publicUrlBase,
    http.Client? client,
  })  : bucket = bucket ??
            env<String>('S3_BUCKET') ??
            env<String>('AWS_BUCKET') ??
            '',
        region = region ??
            env<String>('S3_REGION') ??
            env<String>('AWS_DEFAULT_REGION') ??
            'us-east-1',
        accessKey = accessKey ??
            env<String>('S3_ACCESS_KEY') ??
            env<String>('AWS_ACCESS_KEY_ID') ??
            '',
        secretKey = secretKey ??
            env<String>('S3_SECRET_KEY') ??
            env<String>('AWS_SECRET_ACCESS_KEY') ??
            '',
        endpoint = endpoint ?? env<String>('S3_ENDPOINT'),
        publicUrlBase = publicUrlBase ?? env<String>('S3_PUBLIC_URL'),
        _client = client ?? http.Client();

  Uri _objectUri(String path) {
    final key = path.replaceAll(RegExp(r'^/+'), '');
    final ep = endpoint;
    if (ep != null && ep.isNotEmpty) {
      final base = ep.endsWith('/') ? ep.substring(0, ep.length - 1) : ep;
      return Uri.parse('$base/$bucket/$key');
    }
    return Uri.parse('https://$bucket.s3.$region.amazonaws.com/$key');
  }

  @override
  Future<String> put(String path, List<int> bytes) async {
    _ensureConfigured();
    final uri = _objectUri(path);
    final headers = _sign(
      method: 'PUT',
      uri: uri,
      payload: bytes,
      contentType: 'application/octet-stream',
    );
    final response = await _client.put(uri, headers: headers, body: bytes);
    if (response.statusCode >= 300) {
      throw StateError(
        'S3 put failed (${response.statusCode}): ${response.body}',
      );
    }
    return url(path) ?? uri.toString();
  }

  @override
  Future<bool> exists(String path) async {
    _ensureConfigured();
    final uri = _objectUri(path);
    final headers = _sign(method: 'HEAD', uri: uri, payload: const []);
    final response = await _client.head(uri, headers: headers);
    return response.statusCode == 200;
  }

  @override
  Future<void> delete(String path) async {
    _ensureConfigured();
    final uri = _objectUri(path);
    final headers = _sign(method: 'DELETE', uri: uri, payload: const []);
    final response = await _client.delete(uri, headers: headers);
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw StateError(
        'S3 delete failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  @override
  String? url(String path) {
    final base = publicUrlBase;
    if (base == null || base.isEmpty) return null;
    final key = path.replaceAll(RegExp(r'^/+'), '');
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$trimmed/$key';
  }

  void _ensureConfigured() {
    if (bucket.isEmpty || accessKey.isEmpty || secretKey.isEmpty) {
      Log.warning(
        'S3 disk missing S3_BUCKET / S3_ACCESS_KEY / S3_SECRET_KEY (or AWS_* equivalents)',
      );
      throw StateError('S3 storage is not configured');
    }
  }

  Map<String, String> _sign({
    required String method,
    required Uri uri,
    required List<int> payload,
    String? contentType,
  }) {
    final now = DateTime.now().toUtc();
    final amzDate = _formatAmzDate(now);
    final dateStamp = amzDate.substring(0, 8);
    final payloadHash = sha256.convert(payload).toString();

    final headers = <String, String>{
      'host': uri.host + (uri.hasPort ? ':${uri.port}' : ''),
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };
    if (contentType != null) {
      headers['content-type'] = contentType;
    }

    final signedHeaderNames = headers.keys.map((k) => k.toLowerCase()).toList()
      ..sort();
    final canonicalHeaders = signedHeaderNames
        .map((k) => '$k:${headers[k]!.trim()}\n')
        .join();
    final signedHeaders = signedHeaderNames.join(';');

    final canonicalUri = uri.path.isEmpty ? '/' : _uriEncodePath(uri.path);
    final canonicalQuery = _canonicalQuery(uri);
    final canonicalRequest = [
      method,
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signingKey = _getSignatureKey(secretKey, dateStamp, region, 's3');
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    headers['authorization'] =
        'AWS4-HMAC-SHA256 Credential=$accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    return headers;
  }

  static List<int> _getSignatureKey(
    String key,
    String dateStamp,
    String regionName,
    String serviceName,
  ) {
    final kDate = Hmac(sha256, utf8.encode('AWS4$key'))
        .convert(utf8.encode(dateStamp))
        .bytes;
    final kRegion =
        Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
    final kService =
        Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
    return Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
  }

  static String _formatAmzDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}T'
        '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}Z';
  }

  static String _uriEncodePath(String path) {
    return path.split('/').map(Uri.encodeComponent).join('/');
  }

  static String _canonicalQuery(Uri uri) {
    if (uri.query.isEmpty) return '';
    final parts = <String>[];
    uri.queryParametersAll.forEach((key, values) {
      for (final v in values) {
        parts.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(v)}',
        );
      }
    });
    parts.sort();
    return parts.join('&');
  }
}
