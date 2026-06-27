import 'dart:convert';
import 'dart:io';

/// Encodes an object to JSON, formatting DateTime instances to ISO-8601 strings.
String qudsJsonEncode(dynamic object) {
  return jsonEncode(object, toEncodable: (nonEncodable) {
    if (nonEncodable is DateTime) {
      return nonEncodable.toIso8601String();
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

  /// Internal method used by the framework to flush data to the client
  Future<void> send(HttpResponse response) async {
    // If upgraded, do nothing! The WebSocket API now owns the connection.
    if (isUpgraded) return;

    response.statusCode = statusCode;
    headers.forEach((key, value) {
      response.headers.set(key, value);
    });
    response.write(body);
    await response.close();
  }
}
