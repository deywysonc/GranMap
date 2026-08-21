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
      version: 1,
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
            attempts INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            UNIQUE(scope, sequence)
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_outbox_scope_sequence ON outbox(scope, sequence)',
        );
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
      await transaction.delete(
        'outbox',
        where: 'scope = ?',
        whereArgs: [scope],
      );
      for (var index = 0; index < operations.length; index++) {
        final operation = operations[index];
        await transaction.insert('outbox', {
          'scope': scope,
          'sequence': index,
          'operation': operation['type']?.toString() ?? 'unknown',
          'payload': jsonEncode(operation),
          'attempts': 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> readOutbox(String scope) async {
    final database = await _db;
    final rows = await database.query(
      'outbox',
      columns: ['payload'],
      where: 'scope = ?',
      whereArgs: [scope],
      orderBy: 'sequence ASC',
    );
    return rows
        .map(
          (row) => jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        )
        .toList(growable: true);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
