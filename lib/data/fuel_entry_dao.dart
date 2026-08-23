import 'package:sqflite/sqflite.dart';

import '../models/fuel_entry.dart';

/// CRUD for the `fuel_entries` table.
class FuelEntryDao {
  const FuelEntryDao(this._db);

  final Database _db;

  static const String table = 'fuel_entries';

  /// Ordered by odometer ascending — the order the economy engine wants.
  Future<List<FuelEntry>> getForVehicle(int vehicleId) async {
    final rows = await _db.query(
      table,
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'odometer ASC, filled_at ASC, id ASC',
    );
    return rows.map(FuelEntry.fromMap).toList(growable: false);
  }

  Future<List<FuelEntry>> getAll() async {
    final rows = await _db.query(
      table,
      orderBy: 'vehicle_id ASC, odometer ASC, id ASC',
    );
    return rows.map(FuelEntry.fromMap).toList(growable: false);
  }

  Future<FuelEntry?> getById(int id) async {
    final rows = await _db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FuelEntry.fromMap(rows.first);
  }

  /// The most recent fill by date, used to prefill the entry form (I17).
  Future<FuelEntry?> latestForVehicle(int vehicleId) async {
    final rows = await _db.query(
      table,
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'filled_at DESC, odometer DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FuelEntry.fromMap(rows.first);
  }

  Future<int> insert(FuelEntry entry) {
    final map = Map<String, Object?>.of(entry.toMap())..remove('id');
    return _db.insert(table, map);
  }

  Future<int> update(FuelEntry entry) {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('Cannot update an entry that has no id');
    }
    final map = Map<String, Object?>.of(entry.toMap())..remove('id');
    return _db.update(table, map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) =>
      _db.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<int> deleteForVehicle(int vehicleId) =>
      _db.delete(table, where: 'vehicle_id = ?', whereArgs: [vehicleId]);

  Future<int> countForVehicle(int vehicleId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE vehicle_id = ?',
      [vehicleId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Bulk insert used by backup restore. Runs in one transaction so a partial
  /// import cannot leave half a garage behind.
  Future<void> insertMany(List<FuelEntry> entries) async {
    if (entries.isEmpty) return;
    final batch = _db.batch();
    for (final entry in entries) {
      final map = Map<String, Object?>.of(entry.toMap())..remove('id');
      batch.insert(table, map);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteAll() => _db.delete(table);
}
