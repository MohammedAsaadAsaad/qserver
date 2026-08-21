/// Thrown when the request body exceeds [maxBytes].
class QudsPayloadTooLargeException implements Exception {
  final int? contentLength;
  final int maxBytes;

  QudsPayloadTooLargeException({
    this.contentLength,
    required this.maxBytes,
  });

  String get message =>
      'Payload too large. Maximum allowed is $maxBytes bytes.';

  @override
  String toString() => message;
}

/// Thrown when a request exceeds the configured handler timeout.
class QudsRequestTimeoutException implements Exception {
  final Duration timeout;

  QudsRequestTimeoutException(this.timeout);

  String get message =>
      'Request timed out after ${timeout.inMilliseconds}ms.';

  @override
  String toString() => message;
}

/// Thrown when the server is draining or at its concurrency cap.
class QudsServiceUnavailableException implements Exception {
  final String message;

  QudsServiceUnavailableException(this.message);

  @override
  String toString() => message;
}
