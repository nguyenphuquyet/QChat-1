import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(String userId)
    : super(
        driftDatabase(
          name: 'qchat_${userId.replaceAll('-', '')}',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );
  LocalDatabase.testing(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE outbox (id TEXT PRIMARY KEY, conversation TEXT NOT NULL, payload TEXT NOT NULL, created INTEGER NOT NULL, error TEXT)',
      );
    },
  );
  Future<void> cache(String key, Object value) => customStatement(
    'INSERT OR REPLACE INTO cache VALUES (?, ?)',
    [key, jsonEncode(value)],
  );
  Future<dynamic> read(String key) async {
    final row = await customSelect(
      'SELECT value FROM cache WHERE key = ?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    return row == null ? null : jsonDecode(row.read<String>('value'));
  }

  Future<void> removeCache(String key) =>
      customStatement('DELETE FROM cache WHERE key = ?', [key]);

  Future<void> mergeMessages(
    String conversation,
    List<Map<String, dynamic>> messages,
  ) => transaction(() async {
    final key = 'messages:$conversation';
    final rows = <String, dynamic>{};
    final cached = (await read(key) as List?) ?? [];
    for (final m in [...cached, ...messages]) {
      rows[m['id']] = m;
    }
    final sorted = rows.values.toList()
      ..sort((a, b) => (a['sequence'] as int).compareTo(b['sequence']));
    await cache(key, sorted);
  });

  Future<void> enqueue(Map<String, dynamic> payload) => customStatement(
    'INSERT OR IGNORE INTO outbox (id,conversation,payload,created) VALUES (?,?,?,?)',
    [
      payload['clientId'],
      payload['conversationId'],
      jsonEncode(payload),
      DateTime.now().millisecondsSinceEpoch,
    ],
  );
  Future<List<Map<String, dynamic>>> pending() async =>
      (await customSelect(
            'SELECT payload,created,error FROM outbox ORDER BY created',
          ).get())
          .map(
            (r) => {
              ...Map<String, dynamic>.from(
                jsonDecode(r.read<String>('payload')),
              ),
              'createdAt': DateTime.fromMillisecondsSinceEpoch(
                r.read<int>('created'),
              ).toIso8601String(),
              'failed': r.readNullable<String>('error') != null,
            },
          )
          .toList();
  Future<void> remove(String id) =>
      customStatement('DELETE FROM outbox WHERE id = ?', [id]);
  Future<void> markFailed(String id, bool failed) => customStatement(
    'UPDATE outbox SET error = ? WHERE id = ?',
    [failed ? 'send_failed' : null, id],
  );
  Future<void> clear() async {
    await customStatement('DELETE FROM cache');
    await customStatement('DELETE FROM outbox');
  }

  Future<void> clearReadCache() => customStatement('DELETE FROM cache');

  Future<({int bytes, int entries, int pending})> cacheStats() async {
    final cached = await customSelect(
      'SELECT COALESCE(SUM(LENGTH(CAST(value AS BLOB))), 0) AS bytes, COUNT(*) AS entries FROM cache',
    ).getSingle();
    final queued = await customSelect(
      'SELECT COUNT(*) AS count FROM outbox',
    ).getSingle();
    return (
      bytes: cached.read<int>('bytes'),
      entries: cached.read<int>('entries'),
      pending: queued.read<int>('count'),
    );
  }
}
