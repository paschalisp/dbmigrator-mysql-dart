import 'package:mysql_client_plus/mysql_client_plus.dart';

import 'dbmigrator_mysql.dart';

extension MySQLConnectionMigrationExtensions on MySQLConnection {
  MySQLMigrator migrator({required MySQLMigrationOptions options}) => MySQLMigrator(connection: this, options: options);
}
