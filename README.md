A MySQL/MariaDB database migration library with file-based, versioned schema management supporting both upgrades and downgrades, in Dart.

[![pub package](https://img.shields.io/pub/v/dbmigrator_mysql.svg)](https://pub.dev/packages/dbmigrator_mysql)
[![package publisher](https://img.shields.io/pub/publisher/dbmigrator_mysql.svg)](https://pub.dev/packages/dbmigrator_mysql/publisher)

## Usage
```dart
import 'package:dbmigrator_mysql/dbmigrator_mysql.dart';
import 'package:mysql_dart/mysql_dart.dart';

void main() async {
  final conn = await MySQLConnection.createConnection(
    host: "127.0.0.1",
    port: 3306,
    userName: "test",
    password: "test",
    databaseName: "test_db",
    collation: 'utf8mb4_general_ci',
  );

  // actually connect to database
  await conn.connect();

  final res = await conn.migrator(options: MySQLMigrationOptions(schema: 'test_db', path: './migrations')).migrate(version: '2.0.0');
  print(res.message); // "Migrated from 1.0.0 ➡ 2.0.0 in 3 seconds."
}
```

## Features

Briefly, the package provides the following features:

- **Semantic version resolution** — migration versions are parsed, compared, and ordered using [pub_semver](https://pub.dev/packages/pub_semver).
- **Upgrading & downgrading** — determines whether to upgrade or downgrade based on the current vs. target version.
- **Two migration file structure modes:**
    - **File-based** — `.[up|down].sql` files named with their version (e.g., `1.0.0.up.sql`, `1.0.0.down.sql`, `1.2.0_add_users.up.sql`).
    - **Directory-based** — version-named subdirectories containing `.[up|down].sql` files.
- Multiple files with the same version prefix are supported and executed in alphabetical order (e.g., `1.2.0_a_core_tables.up.sql`,
  `1.2.0_b_crm_tables.up.sql`), in both file-based and directory-based structures.
- **SHA-256 checksum verification** — optional integrity checks to detect migration files modified after applying the migration.
- **Migration locks** — acquire and release migration locks to ensure no other migration can be performed at the same time
  (essential in clustered environments).
- **Transaction-safe execution** — provides the foundation to execute all migration files under a single transaction context.
- **Retry logic** — configurable retry attempts and timeouts for failed migration operations.

> For a detailed list of **features** and **configuration options**, see the [dbmigrator](https://pub.dev/packages/dbmigrator),
which implements the migration logic this package derives from.


## Writing migration scripts

A migration file may contain any number of statements (DDL, multi-row `INSERT`s, stored routines, comments, ...). The whole
file is sent to the server as a single multi-statement query, so the script is parsed by the server and not by this package.

Keep in mind:

- **`DELIMITER` is not supported.** It is a client-side command of the `mysql` CLI, not SQL, and the server rejects it. It is
  not needed: the server parses `BEGIN ... END` bodies of procedures, functions and triggers by itself, so end them with a
  plain `;`.
- **Do not write empty statements** (`;;`, `; ;`, or a comment followed by a bare `;`). The server rejects them inside a
  multi-statement query. An empty script is rejected as well.
- **DDL is not transactional in MySQL/MariaDB.** Statements such as `CREATE`, `ALTER` and `DROP` commit implicitly, so if a
  statement in the middle of a script fails, the earlier statements stay applied and the version is not recorded. Prefer small,
  idempotent scripts (`IF NOT EXISTS` / `IF EXISTS`) so that a failed migration can be safely re-run.

The test suite covers this with real-world fixtures (`test/migrations/complex`: mysqldump style output, inserts with tricky
strings, comments, Unicode, and routines/triggers) executed against both MySQL and MariaDB.

## Additional information

### Other RDBMS migration tools

> - [dbmigrator_psql](https://pub.dev/packages/dbmigrator_psql) - Migrations for PostgreSQL databases.
> - [dbmigrator_mssql](https://pub.dev/packages/dbmigrator_mssql) - Migrations for Microsoft SQL Server databases.

### Contributing

Please file feature requests and bugs at the [issue tracker][tracker].

### License

Licensed under the BSD-3-Clause License.

[tracker]: https://github.com/paschalisp/dbmigrator-mysql-dart/issues/new