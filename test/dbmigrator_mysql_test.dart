import 'package:dbmigrator/dbmigrator.dart';
import 'package:dbmigrator_mysql/dbmigrator_mysql.dart';
import 'package:mysql_client_plus/mysql_client_plus.dart';
import 'package:test/test.dart';

void main() {
  group('File-based migrations execution', () {
    late final MySQLConnection conn;

    setUpAll(() async {
      conn = await MySQLConnection.createConnection(
        host: "127.0.0.1",
        port: 3906,
        userName: "root",
        password: "test",
        databaseName: "test_db",
        collation: 'utf8_general_ci',
        //timeoutMs: 10000,
        //securityContext: context,
        onBadCertificate: (certificate) => true,
        //secure: false,
      );

      // actually connect to database
      await conn.connect();
      print(conn.connected);
    });

    setUp(() async {
      await conn.execute('SELECT CAST(RELEASE_ALL_LOCKS() AS SIGNED INTEGER)');
      await conn.execute('''
        DROP TABLE IF EXISTS _version;
        DROP TABLE IF EXISTS table1;
        DROP TABLE IF EXISTS table2;
        DROP TABLE IF EXISTS table3;
      ''');
    });

    tearDown(() async {
      await conn.execute('SELECT CAST(RELEASE_ALL_LOCKS() AS SIGNED INTEGER)');
      await conn.execute('''
        DROP TABLE IF EXISTS _version;
        DROP TABLE IF EXISTS table1;
        DROP TABLE IF EXISTS table2;
        DROP TABLE IF EXISTS table3;
      ''');
    });

    tearDownAll(() async {
      await conn.close();
    });

    test('Executes the correct upgrade migration files', () async {
      final res = await conn
          .migrator(options: MySQLMigrationOptions(path: './test/migrations/dir-based', directoryBased: true))
          .migrate(version: '2.0.0');
      expect(res.direction, MigrationDirection.up);
      expect(res.files.names(), containsAllInOrder(['0.0.1/up.sql', '1.0.0/up.sql', '1.1.0/up.sql', '2.0.0/up.sql']));
    });

    test('Executes the correct upgrade migration files', () async {
      final res = await conn
          .migrator(options: MySQLMigrationOptions(path: './test/migrations/dir-based', directoryBased: true))
          .migrate(version: '2.0.0');
      expect(res.direction, MigrationDirection.up);
      expect(res.files.names(), containsAllInOrder(['0.0.1/up.sql', '1.0.0/up.sql', '1.1.0/up.sql', '2.0.0/up.sql']));
    });

    test('Upgrading to the last version creates all tables with the subsequent changes', () async {
      await conn
          .migrator(options: MySQLMigrationOptions(path: './test/migrations/dir-based', directoryBased: true))
          .migrate(version: '2.0.0');

      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table1'), completes);
      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table2'), completes);
      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table3'), completes);
    });

    test('Downgrading from the last version alters all tables accordingly', () async {
      final options = MySQLMigrationOptions(path: './test/migrations/dir-based', directoryBased: true);
      // Upgrade to latest schema
      await conn.migrator(options: options).migrate(version: '2.0.0');
      // Downgrade back to 1.0.0
      final res = await conn.migrator(options: options).migrate(version: '1.0.0');

      expect(res.direction, MigrationDirection.down);
      expect(res.files.names(), containsAllInOrder(['2.0.0/down.sql', '1.1.0/down.sql']));

      await expectLater(conn.execute('SELECT id, col1 FROM table1'), completes);
      await expectLater(conn.execute('SELECT id, col1 FROM table2'), completes);

      await expectLater(conn.execute('SELECT id, col1, col2 FROM table1'), doesNotComplete);
      await expectLater(conn.execute('SELECT id, col1, col2 FROM table2'), doesNotComplete);
      await expectLater(conn.execute('SELECT * FROM table3'), doesNotComplete);
    });
  });
}
