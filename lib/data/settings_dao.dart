import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';

/// The `settings` key/value table.
///
/// A table rather than `shared_preferences`: it keeps preferences in the same
/// file as the data (so a backup captures everything) and drops a dependency.
class SettingsDao {
  const SettingsDao(this._db);

  final Database _db;

  static const String table = 'settings';

  Future<Map<String, String>> readAll() async {
    final rows = await _db.query(table);
    return {
      for (final row in rows)
        (row['key'] as String? ?? ''): (row['value'] as String? ?? ''),
    };
  }

  Future<AppSettings> load() async => AppSettings.fromMap(await readAll());

  Future<void> save(AppSettings settings) => writeAll(settings.toMap());

  Future<void> writeAll(Map<String, String> values) async {
    final batch = _db.batch();
    values.forEach((key, value) {
      batch.insert(
        table,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  Future<void> put(String key, String value) => _db.insert(
        table,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<String?> get(String key) async {
    final rows = await _db.query(
      table,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }
}
