// import 'dart:io' show Platform;
// import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../container/service_provider.dart';
import '../container/quds_container.dart';
import '../container/quds_env.dart';

// import 'package:quds_db_interface/quds_db_interface.dart';
import 'package:quds_db_postgres/quds_db_postgres.dart';
import 'package:quds_db_mysql/quds_db_mysql.dart';
// import 'package:quds_db_sqlite/quds_db_sqlite.dart';

class DatabaseServiceProvider extends ServiceProvider {
  @override
  void register() {
    // Registration handled in boot due to async initialization
  }

  @override
  Future<void> boot() async {
    final connectionType = env<String>('DB_CONNECTION', 'postgres')!;

    DatabaseAdapter adapter;
    DatabaseConnection connection;

    try {
      switch (connectionType) {
        case 'postgres':
          adapter = PostgresDatabaseAdapter();
          await adapter.initialize(
            PostgresDatabaseSettings(
              dbName: env<String>('DB_DATABASE', 'quds_db')!,
              host: env<String>('DB_HOST', '127.0.0.1')!,
              port: env<int>('DB_PORT', 5432)!,
              userName: env<String>('DB_USERNAME', 'root')!,
              password: env<String>('DB_PASSWORD', '')!,
              version: 1,
            ),
          );
          connection =
              await adapter.getConnection() as PostgresDatabaseConnection;
          break;

        case 'mysql':
          adapter = MysqlDatabaseAdapter();
          await adapter.initialize(
            MysqlDatabaseSettings(
              dbName: env<String>('DB_DATABASE', 'quds_db')!,
              host: env<String>('DB_HOST', '127.0.0.1')!,
              port: env<int>('DB_PORT', 3306)!,
              userName: env<String>('DB_USERNAME', 'root')!,
              password: env<String>('DB_PASSWORD', '')!,
              version: 1,
            ),
          );
          connection = await adapter.getConnection() as MysqlDatabaseConnection;
          break;

        // case 'sqlite':
        //   // Initialize FFI for server environments
        //   if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        //     sqfliteFfiInit();
        //     databaseFactory = databaseFactoryFfi;
        //   }
        //   adapter = SqliteDatabaseAdapter();
        //   await adapter.initialize(
        //     SqliteDatabaseSettings(
        //       dbName: env<String>('DB_DATABASE', 'database.sqlite')!,
        //       version: 1,
        //     ),
        //   );
        //   connection =
        //       await adapter.getConnection() as SqliteDatabaseConnection;
        //   break;

        default:
          throw Exception("Unsupported DB_CONNECTION: $connectionType");
      }

      // Bind the active connection and adapter globally so providers can use them
      QudsContainer.singleton<DatabaseAdapter>(adapter);
      QudsContainer.singleton<DatabaseConnection>(connection);

      print('📦 Connected to $connectionType database via Quds DB ecosystem.');
    } catch (e) {
      print('\x1B[31m❌ Database connection failed. Error: $e\x1B[0m');
    }
  }
}
