import 'package:quds_db_interface/quds_db_interface.dart';

import '../container/quds_container.dart';

/// Thin facade over the container-bound [DatabaseConnection].
class Database {
  /// The active connection registered by [DatabaseServiceProvider].
  static DatabaseConnection get connection =>
      QudsContainer.resolve<DatabaseConnection>();

  /// Runs [operation] inside the connection's transaction.
  static Future<T> transaction<T>(Future<T> Function() operation) {
    return connection.transaction(operation);
  }
}
