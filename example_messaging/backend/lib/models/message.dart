import 'package:qserver/qserver.dart';

class Message extends StandardDbModel {
  final sender = StringField(columnName: 'sender', notNull: true);
  final receiver = StringField(columnName: 'receiver', notNull: true);
  final content = StringField(columnName: 'content', notNull: true);

  @override
  List<FieldDefinition>? getFields() => [sender, receiver, content];

  @override
  Future<void> beforeSave(bool isNew) async {
    if (isNew) {
      creationTime.value = DateTime.now();
    }
    modificationTime.value = DateTime.now();
    await super.beforeSave(isNew);
  }
}

class MessageProvider extends MysqlStandardTableProvider<Message> {
  MessageProvider(MysqlDatabaseConnection connection)
    : super(connection, () => Message(), 'messages');
}
