import 'package:mysql_dart/mysql_dart.dart';

import 'dbmigrator_mysql.dart';

extension MySQLConnectionMigrationExtensions on MySQLConnection {
  MySQLMigrator migrator({required MySQLMigrationOptions options}) => MySQLMigrator(connection: this, options: options);
}
