import 'dart:io' show Platform;
import 'package:quds_db_sqlite/quds_db_sqlite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/local_message.dart';
import '../models/chat_message.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  late final SqliteStandardTableProvider<LocalMessage> _localMessageProvider;

  Future<void> initialize() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final adapter = SqliteDatabaseAdapter();
    await adapter.initialize(
      SqliteDatabaseSettings(
        dbName: 'whatsapp_clone.db',
        version: 1,
      ),
    );
    final connection = await adapter.getConnection() as SqliteDatabaseConnection;
    _localMessageProvider = SqliteStandardTableProvider<LocalMessage>(
      connection,
      () => LocalMessage(),
      'messages',
    );
    await _localMessageProvider.initialize();
  }

  Future<void> saveMessage(ChatMessage msg) async {
    if (msg.id == null) return;
    try {
      final exists = await _localMessageProvider.exists(msg.id!);
      if (!exists) {
        final localMsg = LocalMessage()
          ..id.value = msg.id
          ..sender.value = msg.sender
          ..receiver.value = msg.receiver
          ..content.value = msg.content
          ..creationTime.value = msg.timestamp;
        await _localMessageProvider.insertEntry(localMsg);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<ChatMessage>> getChatHistory(String currentUser, String contact) async {
    try {
      final messages = await _localMessageProvider.select(
        where: (m) =>
            (m.sender.equals(currentUser) & m.receiver.equals(contact)) |
            (m.sender.equals(contact) & m.receiver.equals(currentUser)),
        orderBy: (m) => [m.creationTime.ascOrder],
      );

      return messages
          .map((m) => ChatMessage(
                id: m.id.value,
                sender: m.sender.value ?? '',
                receiver: m.receiver.value ?? '',
                content: m.content.value ?? '',
                timestamp: m.creationTime.value ?? DateTime.now(),
              ))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<ChatMessage?> getLastMessage(String currentUser, String contact) async {
    try {
      final messages = await _localMessageProvider.select(
        where: (m) =>
            (m.sender.equals(currentUser) & m.receiver.equals(contact)) |
            (m.sender.equals(contact) & m.receiver.equals(currentUser)),
        orderBy: (m) => [m.creationTime.descOrder],
        limit: 1,
      );

      if (messages.isNotEmpty) {
        final m = messages.first;
        return ChatMessage(
          id: m.id.value,
          sender: m.sender.value ?? '',
          receiver: m.receiver.value ?? '',
          content: m.content.value ?? '',
          timestamp: m.creationTime.value ?? DateTime.now(),
        );
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }
}
