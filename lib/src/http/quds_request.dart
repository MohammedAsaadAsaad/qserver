import 'dart:io';
import '../container/quds_mapper.dart';
import 'uploaded_file.dart';
import 'request_parser.dart';
import 'validator.dart';
import '../routing/router.dart';

class QudsRequest {
  final HttpRequest? _rawRequest;
  final dynamic _rawParsedBody;
  final Map<String, String> _routeParams;
  final String _method;
  final String _path;
  final Map<String, String> _queryParameters;
  final String _ip;
  final Map<String, String> _headers;

  QudsRequest._(
    this._rawRequest,
    this._rawParsedBody,
    this._routeParams, {
    required String method,
    required String path,
    Map<String, String> queryParameters = const {},
    String ip = '-',
    Map<String, String> headers = const {},
  })  : _method = method,
        _path = path,
        _queryParameters = queryParameters,
        _ip = ip,
        _headers = headers;

  /// Synthetic request for unit / integration tests (no live [HttpRequest]).
  factory QudsRequest.synthetic({
    required String method,
    required String path,
    Map<String, dynamic> body = const {},
    Map<String, String> routeParams = const {},
    Map<String, String> queryParameters = const {},
    String ip = '127.0.0.1',
    Map<String, String> headers = const {},
  }) {
    return QudsRequest._(
      null,
      body,
      routeParams,
      method: method,
      path: path,
      queryParameters: queryParameters,
      ip: ip,
      headers: headers,
    );
  }

  String get method => _rawRequest?.method ?? _method;
  String get path => _rawRequest?.uri.path ?? _path;

  /// Underlying dart:io request. Throws when this is a synthetic test request.
  HttpRequest get rawRequest {
    final raw = _rawRequest;
    if (raw == null) {
      throw StateError(
        'QudsRequest.rawRequest is unavailable for synthetic test requests.',
      );
    }
    return raw;
  }

  /// Path plus query string, e.g. `/tasks?page=2`.
  String get pathAndQuery {
    if (_rawRequest != null) {
      final query = _rawRequest!.uri.query;
      if (query.isEmpty) return path;
      return '$path?$query';
    }
    if (_queryParameters.isEmpty) return path;
    final q = _queryParameters.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$path?$q';
  }

  /// Client IP, preferring `X-Forwarded-For` when the app sits behind a proxy.
  String get ip {
    if (_rawRequest != null) {
      final forwarded = _rawRequest!.headers.value('x-forwarded-for');
      if (forwarded != null && forwarded.trim().isNotEmpty) {
        return forwarded.split(',').first.trim();
      }
      return _rawRequest!.connectionInfo?.remoteAddress.address ?? '-';
    }
    return _headers['x-forwarded-for']?.split(',').first.trim() ?? _ip;
  }

  /// Reads a request header (case-insensitive for live requests).
  String? header(String name) {
    if (_rawRequest != null) {
      return _rawRequest!.headers.value(name);
    }
    final lower = name.toLowerCase();
    for (final entry in _headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// The parsed request body (e.g. JSON map, form fields, or raw data).
  Map<String, dynamic> get body => (_rawParsedBody is Map<String, dynamic>)
      ? (_rawParsedBody as Map<String, dynamic>)
      : {};

  // A storage map for middleware to pass data to controllers (like the authenticated user)
  final Map<String, dynamic> attributes = {};

  /// Retrieves the authenticated user payload.
  /// If a [key] is provided, it retrieves a specific field (e.g., user('id')).
  T? user<T>([String? key]) {
    final payload = attributes['user'];
    if (payload == null) return null;

    if (key != null && payload is Map) {
      return payload[key] as T?;
    }

    return payload as T?;
  }

  static Future<QudsRequest> from(
    HttpRequest request, {
    Map<String, String> routeParams = const {},
  }) async {
    final parsedBody = await RequestParser.parseBody(request);
    return QudsRequest._(
      request,
      parsedBody,
      routeParams,
      method: request.method,
      path: request.uri.path,
      queryParameters: request.uri.queryParameters,
      ip: request.connectionInfo?.remoteAddress.address ?? '-',
    );
  }

  /// Runs the object-oriented validation engine against the incoming payload.
  void validate(Map<String, QudsValidator> rules) {
    final Map<String, dynamic> data =
        _rawParsedBody is Map<String, dynamic> ? _rawParsedBody : {};

    final errors = ValidationEngine.validate(data, rules);

    if (errors.isNotEmpty) {
      throw QudsValidationException(errors);
    }
  }

  /// Async validation path for DB-backed rules (Unique/Exists). Opt-in.
  Future<void> validateAsync(
    Map<String, QudsValidator> rules, {
    Map<String, AsyncQudsValidator> asyncRules = const {},
  }) async {
    validate(rules);
    final Map<String, dynamic> data =
        _rawParsedBody is Map<String, dynamic> ? _rawParsedBody : {};
    final errors = await ValidationEngine.validateAsync(data, asyncRules);
    if (errors.isNotEmpty) {
      throw QudsValidationException(errors);
    }
  }

  /// Extracts a standard value from a JSON Map or Form data
  T? input<T>(String key, {T? defaultValue}) {
    if (_rawParsedBody is Map<String, dynamic>) {
      final value = (_rawParsedBody as Map<String, dynamic>)[key];
      if (value is T) return value;
    }
    return defaultValue;
  }

  /// Extracts URL route parameters (e.g., /users/{id})
  String? param(String key) => _routeParams[key];

  /// Easy access to query parameters (e.g., ?search=term)
  String? query(String key) {
    if (_rawRequest != null) {
      return _rawRequest!.uri.queryParameters[key];
    }
    return _queryParameters[key];
  }

  /// Extracts a single Object of type T directly from the request body
  T? get<T>() {
    if (_rawParsedBody is Map<String, dynamic>) {
      return QudsMapper.build<T>(_rawParsedBody);
    }
    return null;
  }

  /// Extracts a List of Objects of type T if the client sent a JSON array
  List<T> getList<T>() {
    if (_rawParsedBody is List) {
      return (_rawParsedBody as List)
          .map((item) => QudsMapper.build<T>(item))
          .whereType<T>() // Filters out nulls safely
          .toList();
    }
    return [];
  }

  /// Checks if a file was uploaded under the given field name
  bool hasFile(String key) {
    if (_rawParsedBody is Map<String, dynamic>) {
      return (_rawParsedBody as Map<String, dynamic>)[key] is UploadedFile;
    }
    return false;
  }

  /// Retrieves an uploaded file safely
  UploadedFile? file(String key) {
    if (hasFile(key)) {
      return (_rawParsedBody as Map<String, dynamic>)[key] as UploadedFile;
    }
    return null;
  }
}
