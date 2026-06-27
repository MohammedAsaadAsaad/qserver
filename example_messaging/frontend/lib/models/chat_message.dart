class ChatMessage {
  final int? id;
  final String sender;
  final String receiver;
  final String content;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      sender: json['sender'] ?? '',
      receiver: json['receiver'] ?? '',
      content: json['content'] ?? '',
      timestamp: json['creationTime'] != null
          ? DateTime.tryParse(json['creationTime']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
