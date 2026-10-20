/// Represents standard HTTP Methods handled by Quds Server
enum HttpMethod {
  get('GET'),
  post('POST'),
  put('PUT'),
  patch('PATCH'),
  delete('DELETE'),
  options('OPTIONS');

  final String value;
  const HttpMethod(this.value);

  static HttpMethod? tryParse(String raw) {
    final method = raw.toUpperCase();
    for (final value in HttpMethod.values) {
      if (value.value == method) return value;
    }
    return null;
  }
}

/// Represents standard MIME/Media Types for automated body parsing
enum MediaType {
  json('application/json'),
  formUrlEncoded('application/x-www-form-urlencoded'),
  multipartFormData('multipart/form-data'),
  textPlain('text/plain');

  final String value;
  const MediaType(this.value);

  /// Helper to strictly convert raw header strings into the Enum
  static MediaType? fromString(String? mimeType) {
    if (mimeType == null) return null;
    for (var type in MediaType.values) {
      if (type.value == mimeType) return type;
    }
    return null;
  }
}
