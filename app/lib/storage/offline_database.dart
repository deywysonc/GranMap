import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class OfflineDatabase {
  Database? _database;

  Future<Database> get _db async {
    final current = _database;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final opened = await openDatabase(
      path.join(root, 'granmap_offline.db'),
      version: 2,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await database.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE cache_entries(
            key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE outbox(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scope TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            idempotency_key TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            dead_letter INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            UNIQUE(scope, sequence),
            UNIQUE(scope, idempotency_key)
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_outbox_scope_sequence ON outbox(scope, sequence)',
        );
        await database.execute(
          'CREATE INDEX idx_outbox_due ON outbox(scope, dead_letter, next_attempt_at)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE outbox ADD COLUMN idempotency_key TEXT NOT NULL DEFAULT ''",
          );
          await database.execute(
            'ALTER TABLE outbox ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE outbox ADD COLUMN last_error TEXT',
          );
          await database.execute(
            'ALTER TABLE outbox ADD COLUMN dead_letter INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE outbox ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute('''
            UPDATE outbox
            SET idempotency_key = scope || '-' || id,
                updated_at = created_at
            WHERE idempotency_key = ''
          ''');
          await database.execute(
            'CREATE UNIQUE INDEX idx_outbox_scope_idempotency ON outbox(scope, idempotency_key)',
          );
          await database.execute(
            'CREATE INDEX idx_outbox_due ON outbox(scope, dead_letter, next_attempt_at)',
          );
        }
      },
    );
    _database = opened;
    return opened;
  }

  Future<void> put(String key, String payload) async {
    final database = await _db;
    await database.insert('cache_entries', {
      'key': key,
      'payload': payload,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> read(String key) async {
    final database = await _db;
    final rows = await database.query(
      'cache_entries',
      columns: ['payload'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String;
  }

  Future<void> remove(String key) async {
    final database = await _db;
    await database.delete('cache_entries', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> replaceOutbox(
    String scope,
    List<Map<String, dynamic>> operations,
  ) async {
    final database = await _db;
    await database.transaction((transaction) async {
      final previousRows = await transaction.query(
        'outbox',
        where: 'scope = ?',
        whereArgs: [scope],
      );
      final previousByKey = {
        for (final row in previousRows)
          row['idempotency_key']?.toString() ?? '': row,
      };
      await transaction.delete(
        'outbox',
        where: 'scope = ?',
        whereArgs: [scope],
      );
      for (var index = 0; index < operations.length; index++) {
        final operation = Map<String, dynamic>.from(operations[index]);
        final idempotencyKey =
            operation['idempotency_key']?.toString() ??
            '$scope-${operation['type'] ?? 'operation'}-$index';
        final previous = previousByKey[idempotencyKey];
        final now = DateTime.now().millisecondsSinceEpoch;
        final attempts =
            (operation['attempts'] as num?)?.toInt() ??
            (previous?['attempts'] as int? ?? 0);
        final nextAttemptAt =
            (operation['next_attempt_at'] as num?)?.toInt() ??
            (previous?['next_attempt_at'] as int? ?? 0);
        final lastError =
            operation['last_error']?.toString() ??
            previous?['last_error']?.toString();
        final deadLetter =
            operation['dead_letter'] == true ||
            operation['dead_letter'] == 1 ||
            previous?['dead_letter'] == 1;
        operation
          ..['idempotency_key'] = idempotencyKey
          ..['attempts'] = attempts
          ..['next_attempt_at'] = nextAttemptAt
          ..['last_error'] = lastError
          ..['dead_letter'] = deadLetter;
        await transaction.insert('outbox', {
          'scope': scope,
          'sequence': index,
          'operation': operation['type']?.toString() ?? 'unknown',
          'payload': jsonEncode(operation),
          'idempotency_key': idempotencyKey,
          'attempts': attempts,
          'next_attempt_at': nextAttemptAt,
          'last_error': lastError,
          'dead_letter': deadLetter ? 1 : 0,
          'created_at': previous?['created_at'] as int? ?? now,
          'updated_at': now,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> readOutbox(String scope) async {
    final database = await _db;
    final rows = await database.query(
      'outbox',
      columns: [
        'payload',
        'idempotency_key',
        'attempts',
        'next_attempt_at',
        'last_error',
        'dead_letter',
      ],
      where: 'scope = ?',
      whereArgs: [scope],
      orderBy: 'sequence ASC',
    );
    return rows
        .map((row) {
          final operation =
              jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          return operation
            ..['idempotency_key'] = row['idempotency_key']
            ..['attempts'] = row['attempts']
            ..['next_attempt_at'] = row['next_attempt_at']
            ..['last_error'] = row['last_error']
            ..['dead_letter'] = row['dead_letter'] == 1;
        })
        .toList(growable: true);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
