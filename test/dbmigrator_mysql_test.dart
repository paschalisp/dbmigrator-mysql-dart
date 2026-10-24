import 'dart:convert';

import 'package:dbmigrator/dbmigrator.dart';
import 'package:dbmigrator_mysql/dbmigrator_mysql.dart';
import 'package:mysql_dart/exception.dart';
import 'package:mysql_dart/mysql_dart.dart';
import 'package:test/test.dart';

const mysqlPort = 3906;
const mariaDbPort = 3907;

/// Connection shared by the groups that call [useConnection].
late MySQLConnection conn;

Future<MySQLConnection> connect({int port = mysqlPort}) async {
  final connection = await MySQLConnection.createConnection(
    host: '127.0.0.1',
    port: port,
    userName: 'root',
    password: 'test',
    databaseName: 'test_db',
  );
  await connection.connect();
  return connection;
}

Future<void> dropBaseTables() async {
  await conn.execute('DROP TABLE IF EXISTS _version;');
  await conn.execute('DROP TABLE IF EXISTS table1;');
  await conn.execute('DROP TABLE IF EXISTS table2;');
  await conn.execute('DROP TABLE IF EXISTS table3;');
}

/// Opens [conn] before each test and closes it afterwards, running [cleanUp] on both occasions.
void useConnection({int port = mysqlPort, Future<void> Function() cleanUp = dropBaseTables}) {
  setUp(() async {
    conn = await connect(port: port);
    await cleanUp();
  });

  tearDown(() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!conn.connected) return;

    await cleanUp();
    await conn.close();
  });
}

void main() {
  group('Directory-based migrations execution with MySQLConnection', () {
    final options = MySQLMigrationOptions(schema: 'test_db', path: './test/migrations/dir-based', directoryBased: true);

    useConnection();

    test('Executes the correct upgrade migration files', () async {
      final res = await conn.migrator(options: options).migrate(version: '2.0.0');
      expect(res.direction, MigrationDirection.up);
      expect(res.files.names(), containsAllInOrder(['0.0.1/up.sql', '1.0.0/up.sql', '1.1.0/up.sql', '2.0.0/up.sql']));
    });

    test('Upgrading to the last version creates all tables with the subsequent changes', () async {
      await conn.migrator(options: options).migrate(version: '2.0.0');

      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table1'), completes);
      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table2'), completes);
      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table3'), completes);
    });

    test('Downgrading from the last version alters all tables accordingly', () async {
      // Upgrade to latest schema
      await conn.migrator(options: options).migrate(version: '2.0.0');
      // Downgrade back to 1.0.0
      final res = await conn.migrator(options: options).migrate(version: '1.0.0');

      expect(res.direction, MigrationDirection.down);
      expect(res.files.names(), containsAllInOrder(['2.0.0/down.sql', '1.1.0/down.sql']));

      await expectLater(conn.execute('SELECT id, col1 FROM table1'), completes);
      await expectLater(conn.execute('SELECT id, col1 FROM table2'), completes);

      await expectLater(conn.execute('SELECT id, col1, col2 FROM table1'), throwsA(isA<MySQLServerException>()));
      await expectLater(conn.execute('SELECT id, col1, col2 FROM table2'), throwsA(isA<MySQLServerException>()));
      await expectLater(conn.execute('SELECT * FROM table3'), throwsA(isA<MySQLServerException>()));
    });
  });

  group('File-based migrations execution with MySQLConnection', () {
    final options = MySQLMigrationOptions(
      schema: 'test_db',
      path: './test/migrations/file-based',
      directoryBased: false,
    );

    useConnection();

    test('Executes file-based upgrade migration files', () async {
      final res = await conn.migrator(options: options).migrate(version: '2.0.0');
      expect(res.direction, MigrationDirection.up);
      expect(res.files.names(), containsAllInOrder(['0.0.1.up.sql', '1.0.0.up.sql', '1.1.0.up.sql', '2.0.0.up.sql']));
    });
  });

  group('Migration locking mechanisms', () {
    late MySQLConnection conn1;
    late MySQLConnection conn2;

    setUp(() async {
      conn1 = await connect();
      conn2 = await connect();
    });

    tearDown(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (conn1.connected) {
        await conn1.execute("SELECT RELEASE_LOCK('test_lock_key')");
        await conn1.close();
      }
      if (conn2.connected) {
        await conn2.execute("SELECT RELEASE_LOCK('test_lock_key')");
        await conn2.close();
      }
    });

    test('Acquires and releases advisory lock properly', () async {
      final migrator1 = conn1.migrator(
        options: MySQLMigrationOptions(
          schema: 'test_db',
          path: './test/migrations/dir-based',
          lockKey: 'test_lock_key',
          timeout: const Duration(seconds: 1),
        ),
      );

      final migrator2 = conn2.migrator(
        options: MySQLMigrationOptions(
          schema: 'test_db',
          path: './test/migrations/dir-based',
          lockKey: 'test_lock_key',
          timeout: const Duration(seconds: 1),
        ),
      );

      // conn1 acquires lock
      await migrator1.acquireLock();

      // conn2 attempting to acquire the same lock with short timeout should throw MigrationError
      await expectLater(migrator2.acquireLock(), throwsA(isA<MigrationError>()));

      // conn1 releases lock
      await migrator1.releaseLock();

      // conn2 should now be able to acquire lock
      await expectLater(migrator2.acquireLock(), completes);
      await migrator2.releaseLock();
    });
  });

  group('Migrations execution against MariaDB', () {
    final options = MySQLMigrationOptions(schema: 'test_db', path: './test/migrations/dir-based', directoryBased: true);

    useConnection(port: mariaDbPort);

    test('Executes upgrade migrations against MariaDB', () async {
      final res = await conn.migrator(options: options).migrate(version: '2.0.0');
      expect(res.direction, MigrationDirection.up);
      expect(res.files.names(), containsAllInOrder(['0.0.1/up.sql', '1.0.0/up.sql', '1.1.0/up.sql', '2.0.0/up.sql']));

      await expectLater(conn.execute('SELECT id, col1, col2, col3 FROM table1'), completes);
    });
  });

  // Real-world scripts (mysqldump output, stored routines, inserts with tricky strings) run against both
  // servers. Each script is sent to the server as a single multi-statement query.
  for (final server in [(name: 'MySQL', port: mysqlPort), (name: 'MariaDB', port: mariaDbPort)]) {
    group('Complex migration scripts against ${server.name}', () {
      final options = MySQLMigrationOptions(schema: 'test_db', path: './test/migrations/complex', directoryBased: true);

      Future<void> cleanUp() async {
        await conn.execute('DROP PROCEDURE IF EXISTS complex_unicode_proc');
        await conn.execute('DROP TABLE IF EXISTS `complex_表_πίνακας_جدول_ключ`');
        await conn.execute('DROP TABLE IF EXISTS complex_unicode');
        await conn.execute('DROP TRIGGER IF EXISTS complex_items_after_delete');
        await conn.execute('DROP TRIGGER IF EXISTS complex_edge_before_insert');
        await conn.execute('DROP PROCEDURE IF EXISTS complex_crlf_proc');
        await conn.execute('DROP PROCEDURE IF EXISTS complex_note');
        await conn.execute('DROP PROCEDURE IF EXISTS complex_classify');
        await conn.execute('DROP FUNCTION IF EXISTS complex_fib');
        await conn.execute('DROP TABLE IF EXISTS complex_crlf');
        await conn.execute('DROP TABLE IF EXISTS complex_edge_log');
        await conn.execute('DROP TABLE IF EXISTS `complex;odd``name`');
        await conn.execute('DROP TABLE IF EXISTS complex_edge');
        await conn.execute('DROP FUNCTION IF EXISTS complex_count_items');
        await conn.execute('DROP PROCEDURE IF EXISTS complex_add_item');
        await conn.execute('DROP TABLE IF EXISTS complex_log');
        await conn.execute('DROP TABLE IF EXISTS complex_items');
        await conn.execute('DROP TABLE IF EXISTS _version');
      }

      Future<List<String>> labels() async {
        final res = await conn.execute('SELECT label FROM complex_items ORDER BY id');
        return res.rows.map<String>((r) => r.colAt(0)!).toList();
      }

      useConnection(port: server.port, cleanUp: cleanUp);

      test('mysqldump style script keeps every row and value intact', () async {
        final res = await conn.migrator(options: options).migrate(version: '1.0.0');
        expect(res.direction, MigrationDirection.up);

        expect(await labels(), [
          'semicolon;inside',
          '-- not a comment',
          '/* not a comment */',
          '# not a comment',
          "it's quoted",
          'double "quoted"; value',
          "backslash \\ and ' escape; ok",
          'multi\nline; value',
        ]);

        final notes = await conn.execute('SELECT note FROM complex_items WHERE id = 8');
        expect(notes.rows.first.colAt(0), isNull);
      });

      test('stored procedure, function and trigger created by a multi-statement script work', () async {
        await conn.migrator(options: options).migrate(version: '2.0.0');

        // 8 rows from the dump, + 1 from the procedure call, - 1 deleted by the migration
        final count = await conn.execute('SELECT complex_count_items()');
        expect(count.rows.first.colAt(0), '8');

        expect(await labels(), contains('from migration; with "quotes" and -- dashes'));
        expect(await labels(), isNot(contains('semicolon;inside')));

        final log = await conn.execute('SELECT message FROM complex_log ORDER BY id');
        expect(log.rows.map((r) => r.colAt(0)), [
          'added: from migration; with "quotes" and -- dashes',
          'deleted: semicolon;inside',
        ]);

        // The routines are usable after the migration
        await conn.execute("CALL complex_add_item('later')");
        expect(await labels(), contains('later'));
      });

      Future<Map<int, String?>> edgeLabels() async {
        final res = await conn.execute('SELECT id, label FROM complex_edge ORDER BY id');
        return {for (final r in res.rows) int.parse(r.colAt(0)!): r.colAt(1)};
      }

      Future<Map<int, int?>> edgeAmounts() async {
        final res = await conn.execute('SELECT id, amount FROM complex_edge ORDER BY id');
        return {for (final r in res.rows) int.parse(r.colAt(0)!): int.tryParse(r.colAt(1) ?? '')};
      }

      test('literals, escapes, comments and odd whitespace never break statements apart', () async {
        await conn.migrator(options: options).migrate(version: '3.0.0');

        expect(await edgeLabels(), {
          1: '/* x */', // replaced by the first of two statements on one line
          2: ';',
          3: ';;',
          4: "'",
          5: 'x;y', // 'x;y'WHERE: a literal directly followed by a keyword
          6: "'",
          7: '"',
          8: "'",
          9: '"',
          10: r'a\',
          11: r'C:\temp\; D:\',
          12: 'a;b',
          13: r'100\%',
          14: 'tab\there\nnewline',
          15: 'a "b"; c',
          16: 'ab;cd',
          17: 'a;b',
          18: 'ünï;cödé ✓ – ‘quoted’',
          19: '-- ;',
          20: 'first line\n;\nlast line;',
          21: '*/ ; /*',
          22: '#--/*;*/',
          23: r'$$ // ;; ||',
          24: '`;`',
          25: 'minus minus',
          26: 'minus comment minus',
          27: 'comment between operands',
          40: 'value; with semicolon',
          41: 'conditional; comment',
        });
      });

      test('arithmetic, multi-line statements with comments and statements sharing a line', () async {
        await conn.migrator(options: options).migrate(version: '3.0.0');

        final amounts = await edgeAmounts();
        expect(amounts[2], 102); // second statement on the line of another one
        expect(amounts[3], 1000); // multi-line UPDATE with comments and a ';' on its own line
        expect(amounts[25], 14); // 10--4 is arithmetic, not a comment
        expect(amounts[26], 14); // 10-/* ; */-4
        expect(amounts[27], 11); // 10 /* ; */ + -- add; one \n 1
        expect(amounts[40], 40);
      });

      test('identifiers containing semicolons, quotes and comment markers', () async {
        await conn.migrator(options: options).migrate(version: '3.0.0');

        final res = await conn.execute(
          'SELECT `col;umn`, `a``b`, `dash -- col`, `hash # col`, `/* c */` FROM `complex;odd``name`',
        );
        expect(res.rows.single.typedAssoc().values.toList(), [1, 2, 3, 4, 5]);

        final cols = await conn.execute('SHOW COLUMNS FROM complex_edge');
        expect(cols.rows.map((r) => r.colByName('Field')), contains('delimiter'));
      });

      test('routines with nested blocks and a mysqldump style trigger', () async {
        await conn.migrator(options: options).migrate(version: '4.0.0');

        final labels = await edgeLabels();
        expect(labels[100], 'defaulted; by trigger'); // BEFORE INSERT trigger from the /*!50003 ... */ definition
        expect(labels[101], 'prepared; statement'); // PREPARE / EXECUTE from a user variable
        expect(labels[102], 'small');
        expect(labels[103], 'negative');

        final amounts = await edgeAmounts();
        expect(amounts[102], 55); // complex_fib(10)
        expect(amounts[103], 6765); // complex_fib(20)

        final log = await conn.execute('SELECT message FROM complex_edge_log ORDER BY id');
        expect(log.rows.map((r) => r.colAt(0)), [
          'uses // inside; a string => small',
          'uses // inside; a string => negative',
          r'note: semi; colon -- and # and /* */ $ $$ is not the end inside a string',
        ]);
      });

      test('CRLF line endings, a trailing comment and a last statement without a semicolon', () async {
        await conn.migrator(options: options).migrate(version: '5.0.0');

        final res = await conn.execute('SELECT id, note FROM complex_crlf ORDER BY id');
        expect(res.rows.map((r) => r.colAt(1)), [
          'line one;\r\nline two!',
          'second!',
          'last statement without a semicolon',
        ]);
      });

      // Everything the `complex` migrations create, as `kind name` -> column names (empty for non-tables).
      Future<Map<String, List<String>>> snapshot() async {
        final objects = <String, List<String>>{};

        final columns = await conn.execute(
          "SELECT table_name, column_name FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name LIKE 'complex%' ORDER BY table_name, ordinal_position",
        );
        for (final r in columns.rows) {
          objects.putIfAbsent('table ${r.colAt(0)}', () => []).add(r.colAt(1)!);
        }

        final routines = await conn.execute(
          "SELECT routine_type, routine_name FROM information_schema.routines WHERE routine_schema = DATABASE() AND routine_name LIKE 'complex%'",
        );
        for (final r in routines.rows) {
          objects['${r.colAt(0)!.toLowerCase()} ${r.colAt(1)}'] = [];
        }

        final triggers = await conn.execute(
          "SELECT trigger_name FROM information_schema.triggers WHERE trigger_schema = DATABASE() AND trigger_name LIKE 'complex%'",
        );
        for (final r in triggers.rows) {
          objects['trigger ${r.colAt(0)}'] = [];
        }

        return objects;
      }

      // The objects each version adds on top of the previous ones.
      final createdBy = <String, Map<String, List<String>>>{
        '1.0.0': {
          'table complex_items': ['id', 'label', 'note'],
        },
        '2.0.0': {
          'table complex_log': ['id', 'message'],
          'procedure complex_add_item': [],
          'function complex_count_items': [],
          'trigger complex_items_after_delete': [],
        },
        '3.0.0': {
          'table complex_edge': ['id', 'label', 'amount', 'delimiter'],
          'table complex;odd`name': ['col;umn', 'a`b', 'dash -- col', 'hash # col', '/* c */'],
        },
        '4.0.0': {
          'table complex_edge_log': ['id', 'message'],
          'function complex_fib': [],
          'procedure complex_classify': [],
          'procedure complex_note': [],
          'trigger complex_edge_before_insert': [],
        },
        '5.0.0': {
          'table complex_crlf': ['id', 'note'],
          'procedure complex_crlf_proc': [],
        },
        '6.0.0': {
          'table complex_unicode': ['id', 'lang', 'label', 'όνομα', '名前', 'اسم'],
          'table complex_表_πίνακας_جدول_ключ': ['ключ', 'κλειδί', 'キー'],
          'procedure complex_unicode_proc': [],
        },
      };

      Map<String, List<String>> expectedAt(String version) {
        final versions = createdBy.keys.toList();
        return {for (final v in versions.take(versions.indexOf(version) + 1)) ...createdBy[v]!};
      }

      test('every version creates exactly the objects it declares, and its down script removes them', () async {
        final versions = createdBy.keys.toList();
        expect(await snapshot(), isEmpty);

        for (final version in versions) {
          final res = await conn.migrator(options: options).migrate(version: version);
          expect(res.direction, MigrationDirection.up);
          expect(await snapshot(), expectedAt(version), reason: 'after upgrading to $version');
        }

        for (final version in versions.reversed.skip(1).followedBy(['0.0.0'])) {
          final res = await conn.migrator(options: options).migrate(version: version);
          expect(res.direction, MigrationDirection.down);
          expect(
            await snapshot(),
            version == '0.0.0' ? isEmpty : expectedAt(version),
            reason: 'after downgrading to $version',
          );
        }
      });

      test('the objects created by each version behave as defined, not just exist', () async {
        await conn.migrator(options: options).migrate(version: '5.0.0');

        final kinds = {'complex_fib(10)': '55', 'complex_count_items()': '8'};
        for (final e in kinds.entries) {
          final res = await conn.execute('SELECT ${e.key}');
          expect(res.rows.first.colAt(0), e.value, reason: e.key);
        }

        // Triggers fire: 2.0.0 logs deletes, 4.0.0 defaults a NULL label
        await conn.execute("DELETE FROM complex_items WHERE label = '# not a comment'");
        final deleted = await conn.execute(
          "SELECT COUNT(*) FROM complex_log WHERE message = 'deleted: # not a comment'",
        );
        expect(deleted.rows.first.colAt(0), '1');

        await conn.execute('INSERT INTO complex_edge (id, label, amount) VALUES (500, NULL, 0)');
        final label = await conn.execute('SELECT label FROM complex_edge WHERE id = 500');
        expect(label.rows.first.colAt(0), 'defaulted; by trigger');
      });

      // What `complex/6.0.0` stores in complex_unicode.label, by id.
      final unicodeLabels = <int, String>{
        1: "Καλημέρα κόσμε; Ελληνικά 'με απόστροφο' -- όχι σχόλιο",
        2: 'Ποιο είναι το όνομά σου\u037e', // U+037E GREEK QUESTION MARK, canonically a ';' look-alike
        3: '你好，世界；这是中文; "引号" /* 不是注释 */',
        4: '繁體中文：資料庫遷移 # 不是註解 ✓',
        5: 'こんにちは世界；日本語 カタカナ 漢字 -- コメントではない',
        6: '안녕하세요 세계; 한국어',
        7: 'مرحبا بالعالم؛ نص عربي; مع "اقتباس" و \'اقتباس\' # ليس تعليقا',
        8: 'مرحبا \u202eabc 123\u200b mixed LTR/RTL \u200e\u200f end', // RTL override, ZWSP, LRM, RLM
        9: 'שלום עולם; עברית /* לא הערה */',
        10: 'Привет, мир; кириллица -- не комментарий',
        11: 'नमस्ते दुनिया; देवनागरी',
        12: 'สวัสดีชาวโลก; ภาษาไทย',
        13: '😀😃😄 😍🥳; 🚀🔥 \'💯\' "🎉"',
        14: '👨\u200d👩\u200d👧\u200d👦 🇬🇷 👍🏽 ❤\ufe0f ✌\ufe0f 🏳\ufe0f\u200d🌈',
        15: '；；；＇＂｀－－\u3000＃', // fullwidth look-alikes and an ideographic space
        16: 'e\u0301 n\u0303 ü ñ', // decomposed accents are not normalised
        17: 'line\u2028separator and paragraph\u2029separator; NBSP\u00a0here \ufeffbom \u200bzwsp',
        18: 'Ελληνικά 中文 العربية 😀 English; all together -- # /* */',
        19: '‘curly’ “curly” «guillemets» „low“ ‹single› ′prime″ ´acute˜ ʼmodifier',
        20: "backslash \\ then Ω 😀 中; and 'quoted' 😀", // \Ω, \😀 and \中 are unknown escapes: the backslash is dropped
        21: 'ΈναΔύο😀',
        22: '𝒜𝔅ℂ 𠜎𠜱𠝹 𐍈 𝄞;', // characters outside the BMP
        23: 'γλώσσα; 语言; لغة; 🌍',
        24: 'πίνακας; 表; جدول; 📦',
        40: 'Ωμέγα; 😀 中',
        41: 'υπό όρους; 条件付き 😀',
        42: 'α;β😀',
        900: 'Γειά σου; 你好; مرحبا; ★ // not the end',
      };

      test('unicode text in INSERT statements is stored exactly, whatever the script or emoji', () async {
        await conn.migrator(options: options).migrate(version: '6.0.0');

        final res = await conn.execute('SELECT id, label, HEX(label), CHAR_LENGTH(label) FROM complex_unicode');
        final rows = {for (final r in res.rows) int.parse(r.colAt(0)!): r};

        // Nothing is lost or duplicated
        expect(rows.keys.toList()..sort(), unicodeLabels.keys.toList()..sort());

        for (final e in unicodeLabels.entries) {
          final row = rows[e.key]!;
          expect(row.colAt(1), e.value, reason: 'label of row ${e.key}');
          // The bytes on the server are the UTF-8 bytes of the expected text (no "?" substitutions, no mojibake)
          expect(row.colAt(2), _hex(e.value), reason: 'bytes of row ${e.key}');
          expect(int.parse(row.colAt(3)!), e.value.runes.length, reason: 'characters of row ${e.key}');
        }

        final langs = await conn.execute('SELECT id, lang FROM complex_unicode WHERE id IN (1, 7, 13, 17, 900)');
        expect(
          {for (final r in langs.rows) int.parse(r.colAt(0)!): r.colAt(1)},
          {1: 'el', 7: 'ar', 13: 'emoji', 17: 'separators', 900: 'proc'},
        );
      });

      test('non-ASCII identifiers and statements with unicode comments take effect', () async {
        await conn.migrator(options: options).migrate(version: '6.0.0');

        // Updates that were separated by, or followed, unicode comments
        final names = await conn.execute('SELECT `όνομα`, `اسم` FROM complex_unicode WHERE id = 1');
        expect(names.rows.single.typedAssoc().values.toList(), ['Νίκος', 'أحمد']);
        final cjk = await conn.execute('SELECT `名前` FROM complex_unicode WHERE id = 3');
        expect(cjk.rows.single.colAt(0), '名前；値');

        final other = await conn.execute('SELECT `ключ`, `κλειδί`, `キー` FROM `complex_表_πίνακας_جدول_ключ`');
        expect(other.rows.single.typedAssoc().values.toList(), [1, 2, 3]);
      });

      test('downgrading from the edge case versions removes everything they created', () async {
        await conn.migrator(options: options).migrate(version: '6.0.0');
        final res = await conn.migrator(options: options).migrate(version: '2.0.0');
        expect(res.direction, MigrationDirection.down);
        expect(
          res.files.names(),
          containsAllInOrder(['6.0.0/down.sql', '5.0.0/down.sql', '4.0.0/down.sql', '3.0.0/down.sql']),
        );

        for (final sql in [
          'SELECT * FROM complex_edge',
          'SELECT * FROM complex_edge_log',
          'SELECT * FROM complex_crlf',
          'SELECT * FROM complex_unicode',
          'SELECT * FROM `complex_表_πίνακας_جدول_ключ`',
          "CALL complex_unicode_proc('x')",
          'SELECT * FROM `complex;odd``name`',
          'SELECT complex_fib(1)',
          "CALL complex_classify(1, @k)",
          "CALL complex_note('x')",
          "CALL complex_crlf_proc()",
        ]) {
          await expectLater(conn.execute(sql), throwsA(isA<MySQLServerException>()), reason: sql);
        }

        // 2.0.0 is still in place
        await expectLater(conn.execute('SELECT complex_count_items()'), completes);
      });

      test('downgrading drops the routines and tables', () async {
        await conn.migrator(options: options).migrate(version: '2.0.0');
        final res = await conn.migrator(options: options).migrate(version: '0.0.0');
        expect(res.direction, MigrationDirection.down);

        await expectLater(conn.execute('SELECT * FROM complex_items'), throwsA(isA<MySQLServerException>()));
        await expectLater(conn.execute('SELECT * FROM complex_log'), throwsA(isA<MySQLServerException>()));
        await expectLater(conn.execute("CALL complex_add_item('x')"), throwsA(isA<MySQLServerException>()));
      });
    });
  }
}

String _hex(String s) => utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
