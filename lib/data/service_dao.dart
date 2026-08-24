import 'package:sqflite/sqflite.dart';

import '../models/service_record.dart';

/// CRUD for the `service_records` table (schema v2).
class ServiceDao {
  const ServiceDao(this._db);

  final Database _db;

  static const String table = 'service_records';

  /// Newest first — the order the history list wants.
  Future<List<ServiceRecord>> getForVehicle(int vehicleId) async {
    final rows = await _db.query(
      table,
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'performed_at DESC, id DESC',
    );
    return rows.map(ServiceRecord.fromMap).toList(growable: false);
  }

  Future<List<ServiceRecord>> getAll() async {
    final rows = await _db.query(
      table,
      orderBy: 'vehicle_id ASC, performed_at DESC, id DESC',
    );
    return rows.map(ServiceRecord.fromMap).toList(growable: false);
  }

  Future<ServiceRecord?> getById(int id) async {
    final rows = await _db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ServiceRecord.fromMap(rows.first);
  }

  Future<int> insert(ServiceRecord record) {
    final map = Map<String, Object?>.of(record.toMap())..remove('id');
    return _db.insert(table, map);
  }

  Future<int> update(ServiceRecord record) {
    final id = record.id;
    if (id == null) {
      throw ArgumentError('Cannot update a service record that has no id');
    }
    final map = Map<String, Object?>.of(record.toMap())..remove('id');
    return _db.update(table, map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> delete(int id) =>
      _db.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<int> countForVehicle(int vehicleId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE vehicle_id = ?',
      [vehicleId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Bulk insert used by backup restore.
  Future<void> insertMany(List<ServiceRecord> records) async {
    if (records.isEmpty) return;
    final batch = _db.batch();
    for (final record in records) {
      final map = Map<String, Object?>.of(record.toMap())..remove('id');
      batch.insert(table, map);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteAll() => _db.delete(table);
}
