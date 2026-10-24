import 'dart:io';

import 'package:dbmigrator/dbmigrator.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';

class MySQLMigrator with Migratable {
  MySQLMigrator({required MySQLConnection connection, required this.options}) : _conn = connection;

  final MySQLConnection _conn;
  final MySQLMigrationOptions options;

  @override
  MySQLMigrationOptions get migrationOptions => options;

  String get versionTable => options.versionTable;

  @override
  bool isRetryable(Object error) {
    if (error is SocketException) return true;

    if (error is MySQLServerException) {
      // Try evaluating by error code
      return const {
        1040,
        // ER_CON_COUNT_ERROR - Too many connections
        1053,
        // ER_SERVER_SHUTDOWN - Server shutdown in progress
        1158,
        // ER_NET_READ_ERROR - Got an error reading communication packets
        1159,
        // ER_NET_READ_INTERRUPTED - Got timeout reading communication packets
        1160,
        // ER_NET_ERROR_ON_WRITE - Got an error writing communication packets
        1161,
        // ER_NET_WRITE_INTERRUPTED - Got timeout writing communication packets
        2002,
        // CR_CONNECTION_ERROR - Can't connect to server
        2003,
        // CR_CONN_HOST_ERROR - Can't connect to MySQL server
        2006,
        // CR_SERVER_GONE_ERROR - MySQL server has gone away
        2013,
        // CR_SERVER_LOST - Lost connection to MySQL server during query
        1213,
        // ER_LOCK_DEADLOCK - Deadlock found when trying to get lock
        1205,
        // ER_LOCK_WAIT_TIMEOUT - Lock wait timeout exceeded
      }.contains(error.errorCode);
    }

    return false;
  }

  @override
  Future<void> acquireLock() async {
    final result = await _conn.execute('SELECT GET_LOCK(:key, :timeout) AS lock_acquired', {
      'key': options.lockKey,
      'timeout': options.timeout.inSeconds,
    });

    final lock = result.rows.firstOrNull?.assoc()['lock_acquired'];
    // GET_LOCK returns 1 on success, 0 on timeout and NULL on error
    if (int.tryParse('$lock') != 1) {
      throw MigrationError(
        message: 'Failed to acquire lock "${options.lockKey}" within ${options.timeout.inSeconds}s timeout.',
      );
    }
  }

  @override
  Future<void> releaseLock() async {
    await _conn.execute('SELECT RELEASE_LOCK(:key)', {'key': options.lockKey});
  }

  @override
  Future<void> transaction(Future<dynamic> Function(MySQLConnection ctx) fn) async {
    await _conn.transactional((conn) async {
      await fn(conn);
    });
  }

  @override
  Future<dynamic> execute(Object obj, {Map<String, dynamic> params = const {}, dynamic ctx}) async {
    if (ctx == null || ctx is! MySQLConnection) throw ArgumentError('ctx is not a MySQLConnection instance');
    if (params.isNotEmpty && obj is! String) throw ArgumentError('when params are given, then obj has to be a string');

    if (params.isNotEmpty) {
      return await ctx.execute(obj as String, params);
    }

    // Migration scripts may contain multiple statements; they are sent to the server as a single query.
    return await ctx.execute(obj.toString());
  }

  @override
  Future<({String version, String checksum})?> queryVersion() async {
    try {
      final sql =
          'SELECT version, checksum FROM `${options.schema}`.`${options.versionTable}` ORDER BY id DESC LIMIT 1';
      final result = await _conn.execute(sql);
      final row = result.rows.isEmpty ? <String, dynamic>{} : result.rows.first.assoc();

      return (version: row['version'] as String? ?? '', checksum: row['checksum'] as String? ?? '');
    } catch (e) {
      if (e is MySQLServerException && e.errorCode == 1146) {
        String sql =
            """
            CREATE TABLE IF NOT EXISTS `${options.schema}`.`${options.versionTable}` (
                 id           BIGINT AUTO_INCREMENT PRIMARY KEY,
                 version      VARCHAR(255) NOT NULL,
                 checksum     VARCHAR(255) NOT NULL,
                 started_at   DATETIME NOT NULL,
                 completed_at DATETIME NOT NULL,
                 direction    VARCHAR(10) NOT NULL CHECK (direction IN ('up', 'down')),
                 comments     TEXT
            )
        """;
        await _conn.execute(sql);

        sql =
            """
            CREATE INDEX `idx_${options.versionTable}_version` ON `${options.schema}`.`${options.versionTable}` (version);
            """;
        try {
          await _conn.execute(sql);
        } catch (_) {
          // Index might already exist
        }

        return (version: Migratable.minVersion, checksum: '');
      }

      rethrow;
    }
  }

  @override
  Future<void> saveVersion({required MigrationResult result, dynamic ctx, String? comment}) async {
    if (ctx == null || ctx is! MySQLConnection) throw ArgumentError('ctx is not a MySQLConnection instance');

    await ctx.execute(
      """INSERT INTO `${options.schema}`.`${options.versionTable}` (version, checksum, started_at, completed_at, direction, comments)
           VALUES (:version, :checksum, :started_at, :completed_at, :direction, :comments)""",
      {
        'version': result.toVersion,
        'checksum': result.checksum,
        'started_at': result.started.toIso8601String(),
        'completed_at': result.completed.toIso8601String(),
        'direction': result.direction == MigrationDirection.down ? 'down' : 'up',
        'comments': comment,
      },
    );
  }
}

class MySQLMigrationOptions extends MigrationOptions {
  MySQLMigrationOptions({
    required super.path,
    super.filesPattern,
    super.directoryBased,
    super.schema,
    super.versionTable,
    super.retries,
    super.retryDelay,
    super.timeout,
    super.checksums,
    super.encoding,
    super.lockKey,
  }) : assert(schema.isNotEmpty, 'schema must not be empty'),
       assert(versionTable.isNotEmpty, 'version table must not be empty');
}
