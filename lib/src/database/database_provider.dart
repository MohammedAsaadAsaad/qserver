import '../container/service_provider.dart';
import '../container/quds_container.dart';
import '../container/quds_env.dart';
import '../logging/quds_log.dart';

import 'package:quds_db_postgres/quds_db_postgres.dart';
import 'package:quds_db_mysql/quds_db_mysql.dart';

class DatabaseServiceProvider extends ServiceProvider {
  @override
  void register() {
    // Registration handled in boot due to async initialization
  }

  @override
  Future<void> boot() async {
    final connectionType = env<String>('DB_CONNECTION', 'postgres')!;
    final host = env<String>('DB_HOST', '127.0.0.1')!;
    final port = env<int>(
      'DB_PORT',
      connectionType == 'mysql' ? 3306 : 5432,
    )!;
    final database = env<String>('DB_DATABASE', 'quds_db')!;

    Log.info(
      'Connecting $connectionType $host:$port/$database',
      component: 'db',
    );

    DatabaseAdapter adapter;
    DatabaseConnection connection;
    final sw = Stopwatch()..start();

    try {
      switch (connectionType) {
        case 'postgres':
          adapter = PostgresDatabaseAdapter();
          await adapter.initialize(
            PostgresDatabaseSettings(
              dbName: database,
              host: host,
              port: port,
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
              dbName: database,
              host: host,
              port: port,
              userName: env<String>('DB_USERNAME', 'root')!,
              password: env<String>('DB_PASSWORD', '')!,
              version: 1,
            ),
          );
          connection = await adapter.getConnection() as MysqlDatabaseConnection;
          break;

        case 'sqlite':
          throw Exception(
              "SQLite is not supported directly in the qserver backend package because it requires the Flutter SDK. Use postgres or mysql, or import quds_db_sqlite package in your application.");

        default:
          throw Exception("Unsupported DB_CONNECTION: $connectionType");
      }

      // Bind the active connection and adapter globally so providers can use them
      QudsContainer.singleton<DatabaseAdapter>(adapter);
      QudsContainer.singleton<DatabaseConnection>(connection);

      Log.info(
        'Connected $connectionType · ${sw.elapsedMilliseconds}ms',
        component: 'db',
      );
    } catch (e) {
      Log.error(
        'Connection failed · ${sw.elapsedMilliseconds}ms: $e',
        component: 'db',
      );
    }
  }

  @override
  Future<void> shutdown() async {
    if (QudsContainer.isRegistered<DatabaseAdapter>()) {
      try {
        await QudsContainer.resolve<DatabaseAdapter>().close();
        Log.info('Connection closed', component: 'db');
      } catch (e) {
        Log.debug('Database adapter close: $e', component: 'db');
      }
    }
  }
}
