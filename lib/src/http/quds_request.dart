import 'dart:io';
import '../container/quds_mapper.dart';
import 'uploaded_file.dart';
import 'request_parser.dart';
import 'validator.dart';
import '../routing/router.dart';

class QudsRequest {
  final HttpRequest _rawRequest;
  final dynamic _rawParsedBody;
  final Map<String, String> _routeParams;

  QudsRequest._(this._rawRequest, this._rawParsedBody, this._routeParams);

  String get method => _rawRequest.method;
  String get path => _rawRequest.uri.path;
  HttpRequest get rawRequest => _rawRequest;

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
    return QudsRequest._(request, parsedBody, routeParams);
  }

  /// Runs the object-oriented validation engine against the incoming payload.
  void validate(Map<String, QudsValidator> rules) {
    final Map<String, dynamic> data = _rawParsedBody is Map<String, dynamic>
        ? _rawParsedBody
        : {};

    final errors = ValidationEngine.validate(data, rules);

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
  String? query(String key) => _rawRequest.uri.queryParameters[key];

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
