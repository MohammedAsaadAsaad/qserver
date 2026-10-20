import 'dart:convert';
import 'dart:io';

import 'enums.dart';
import 'paginator.dart';
import 'sse.dart';

/// Encodes an object to JSON, formatting DateTime instances to ISO-8601 strings.
String qudsJsonEncode(dynamic object) {
  return jsonEncode(object, toEncodable: (nonEncodable) {
    if (nonEncodable is DateTime) {
      return nonEncodable.toUtc().toIso8601String();
    }
    return nonEncodable.toString();
  });
}

/// A fluent, easy-to-use builder for HTTP Responses
class QudsResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  // Add this flag to track hijacked WebSocket connections
  bool isUpgraded = false;

  /// Optional binary body (gzip, files). [body] is used when this is null.
  List<int>? rawBody;

  /// When set, [send] writes SSE frames until the stream completes.
  Stream<SseEvent>? eventStream;

  QudsResponse({
    this.statusCode = 200,
    this.body = '',
    Map<String, String> headers = const {},
  }) : headers = Map<String, String>.from(headers);

  /// Instantly creates a correctly formatted JSON response
  factory QudsResponse.json(Map<String, dynamic> data, {int status = 200}) {
    return QudsResponse(
      statusCode: status,
      body: qudsJsonEncode(data),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  /// Opt-in envelope. [json] is unchanged — existing maps stay as-is.
  factory QudsResponse.envelope({
    Object? data,
    String? message,
    Object? errors,
    Map<String, dynamic>? meta,
    int status = 200,
  }) {
    return QudsResponse.json({
      'success': status >= 200 && status < 300,
      'message': message,
      'data': data,
      'errors': errors,
      'meta': meta,
    }, status: status);
  }

  /// Paginated envelope using [Paginator.meta].
  factory QudsResponse.paginated(
    List<dynamic> data, {
    required int total,
    int page = 1,
    int perPage = 15,
    String? message,
    int status = 200,
  }) {
    final pager = Paginator(page: page, perPage: perPage, total: total);
    return QudsResponse.envelope(
      data: data,
      message: message,
      meta: pager.meta,
      status: status,
    );
  }

  factory QudsResponse.bytes(
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    int status = 200,
  }) {
    return QudsResponse(
      statusCode: status,
      headers: {'Content-Type': contentType},
    )..rawBody = bytes;
  }

  factory QudsResponse.sse(
    Stream<SseEvent> events, {
    Map<String, String> headers = const {},
  }) {
    return QudsResponse(
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        ...headers,
      },
    )..eventStream = events;
  }

  /// A special response used when the connection is upgraded to a WebSocket
  factory QudsResponse.upgraded() {
    return QudsResponse()..isUpgraded = true;
  }

  /// Instantly creates a plain text response
  factory QudsResponse.text(String text, {int status = 200}) {
    return QudsResponse(
      statusCode: status,
      body: text,
      headers: {'Content-Type': 'text/plain; charset=utf-8'},
    );
  }

  /// Instantly creates an HTML response
  factory QudsResponse.html(String html, {int status = 200}) {
    return QudsResponse(
      statusCode: status,
      body: html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// Standardized format for returning API errors
  factory QudsResponse.error(String message, {int status = 400}) {
    return QudsResponse.json({
      'error': true,
      'message': message,
    }, status: status);
  }

  factory QudsResponse.methodNotAllowed() {
    return QudsResponse.error('Method Not Allowed', status: 405)
      ..headers['Allow'] =
          HttpMethod.values.map((method) => method.value).join(', ');
  }

  /// Internal method used by the framework to flush data to the client
  Future<void> send(HttpResponse response) async {
    if (isUpgraded) return;

    try {
      response.statusCode = statusCode;
      headers.forEach((key, value) {
        response.headers.set(key, value);
      });
      final stream = eventStream;
      if (stream != null) {
        response.bufferOutput = false;
        await for (final event in stream) {
          response.write(event.encode());
          await response.flush();
        }
        await response.close();
        return;
      }
      final bytes = rawBody;
      if (bytes != null) {
        response.add(bytes);
      } else {
        response.write(body);
      }
      await response.close();
    } on HttpException {
      try {
        await response.close();
      } catch (_) {}
    } on SocketException {
      try {
        await response.close();
      } catch (_) {}
    } on StateError {
      try {
        await response.close();
      } catch (_) {}
    }
  }
}
