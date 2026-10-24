import 'package:dbmigrator_mysql/dbmigrator_mysql.dart';
import 'package:mysql_dart/mysql_dart.dart';

void main() async {
  final conn = await MySQLConnection.createConnection(
    host: "127.0.0.1",
    port: 3306,
    userName: "test",
    password: "test",
    databaseName: "test_db",
    //collation: 'utf8mb4_general_ci',
    //timeoutMs: 10000,
    //securityContext: context,
    //onBadCertificate: (certificate) => true,
  );

  // actually connect to database
  await conn.connect();

  final res = await conn
      .migrator(
        options: MySQLMigrationOptions(schema: 'test_db', path: './migrations'),
      )
      .migrate(version: '2.0.0');

  print(res.message); // "Migrated from 1.0.0 ➡ 2.0.0 in 3 seconds."
}
