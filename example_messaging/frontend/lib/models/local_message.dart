import 'package:quds_db_sqlite/quds_db_sqlite.dart';

class LocalMessage extends StandardDbModel {
  final sender = StringField(columnName: 'sender', notNull: true);
  final receiver = StringField(columnName: 'receiver', notNull: true);
  final content = StringField(columnName: 'content', notNull: true);

  @override
  List<FieldDefinition>? getFields() => [sender, receiver, content];
}
