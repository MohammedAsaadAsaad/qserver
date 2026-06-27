import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class ApiService {
  final String backendUrl;

  ApiService({this.backendUrl = 'http://localhost:8080'});

  Future<List<ChatMessage>> fetchChatHistory(String currentUser, String contact) async {
    final response = await http.get(Uri.parse(
        '$backendUrl/api/v1/messages?sender=$currentUser&receiver=$contact'));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final list = decoded['data'] as List;
      return list.map((m) => ChatMessage.fromJson(m)).toList();
    } else {
      throw http.ClientException('Server returned ${response.statusCode}', response.request?.url);
    }
  }

  Future<ChatMessage?> fetchLastMessage(String currentUser, String contact) async {
    final response = await http.get(Uri.parse(
        '$backendUrl/api/v1/messages?sender=$currentUser&receiver=$contact&limit=1'));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final list = decoded['data'] as List;
      if (list.isNotEmpty) {
        return ChatMessage.fromJson(list[0]);
      }
      return null;
    } else {
      throw http.ClientException('Server returned ${response.statusCode}', response.request?.url);
    }
  }

  Future<void> sendMessage(String currentUser, String receiver, String text) async {
    final response = await http.post(
      Uri.parse('$backendUrl/api/v1/messages'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sender': currentUser,
        'receiver': receiver,
        'content': text,
      }),
    );

    if (response.statusCode != 201) {
      throw http.ClientException('Failed to send message: ${response.statusCode}', response.request?.url);
    }
  }
}
