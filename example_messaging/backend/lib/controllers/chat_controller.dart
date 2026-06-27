import 'package:qserver/qserver.dart';
import '../models/message.dart';

class ChatController {
  late final MessageProvider provider;

  ChatController() {
    // Resolve SQLite connection from Container
    final connection =
        QudsContainer.resolve<DatabaseConnection>() as MysqlDatabaseConnection;
    provider = MessageProvider(connection);
  }

  /// Fetches historical chat messages between two users from the SQLite database
  Future<QudsResponse> getMessages(QudsRequest request) async {
    final sender = request.query('sender');
    final receiver = request.query('receiver');
    final limitStr = request.query('limit');
    final limit = limitStr != null ? int.tryParse(limitStr) : null;

    if (sender == null || receiver == null) {
      return QudsResponse.error('Missing sender or receiver parameter');
    }

    await provider.initialize();

    final messages = await provider.select(
      where: (m) =>
          (m.sender.equals(sender) & m.receiver.equals(receiver)) |
          (m.sender.equals(receiver) & m.receiver.equals(sender)),
      orderBy: (m) => [m.creationTime.descOrder],
      limit: limit,
    );

    if (limit == null) {
      messages.sort((a, b) {
        final aTime =
            a.creationTime.value ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.creationTime.value ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
    }

    final data = messages.map((m) => m.toMap()).toList();
    return QudsResponse.json({'data': data});
  }

  /// Validates, saves to SQLite, and broadcasts a new message in real-time
  Future<QudsResponse> sendMessage(QudsRequest request) async {
    final message = Message()..fromMap(request.body);

    if (message.sender.value == null ||
        message.sender.value!.isEmpty ||
        message.receiver.value == null ||
        message.receiver.value!.isEmpty ||
        message.content.value == null ||
        message.content.value!.isEmpty) {
      return QudsResponse.error(
        'Sender, receiver, and content are required',
        status: 422,
      );
    }

    await provider.initialize();
    await provider.insertEntry(message);

    final responsePayload = message.toMap();

    // Broadcast the event to recipient and sender channels
    Broadcast.emit(
      'chat.${message.sender.value}',
      'MessageReceived',
      responsePayload,
    );
    Broadcast.emit(
      'chat.${message.receiver.value}',
      'MessageReceived',
      responsePayload,
    );

    return QudsResponse.json({
      'message': 'Message sent and stored successfully!',
      'data': responsePayload,
    }, status: 201);
  }
}
