import 'package:qserver/qserver.dart';

class Task extends StandardDbModel {
  final title = StringField(columnName: 'title', notNull: true);
  final description = StringField(columnName: 'description');
  final status = StringField(columnName: 'status', defaultValue: 'pending');

  @override
  List<FieldDefinition>? getFields() => [title, description, status];
}

// We use the Postgres provider here since it matches our .env
class TaskProvider extends PostgresStandardTableProvider<Task> {
  TaskProvider(PostgresDatabaseConnection connection)
    : super(connection, () => Task(), 'tasks');
}
