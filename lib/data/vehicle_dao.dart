import 'package:sqflite/sqflite.dart';

import '../models/vehicle.dart';

/// CRUD for the `vehicles` table.
class VehicleDao {
  const VehicleDao(this._db);

  final Database _db;

  static const String table = 'vehicles';

  /// Active vehicles first, newest last-updated first within each group.
  Future<List<Vehicle>> getAll({bool includeArchived = false}) async {
    final rows = await _db.query(
      table,
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'is_archived ASC, updated_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList(growable: false);
  }

  Future<Vehicle?> getById(int id) async {
    final rows = await _db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Vehicle.fromMap(rows.first);
  }

  /// Returns the new row id.
  Future<int> insert(Vehicle vehicle) {
    final map = Map<String, Object?>.of(vehicle.toMap())..remove('id');
    return _db.insert(table, map);
  }

  /// Returns the number of rows changed.
  Future<int> update(Vehicle vehicle) {
    final id = vehicle.id;
    if (id == null) {
      throw ArgumentError('Cannot update a vehicle that has no id');
    }
    final map = Map<String, Object?>.of(vehicle.toMap())..remove('id');
    return _db.update(table, map, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes the vehicle **and every entry belonging to it**, via the
  /// `ON DELETE CASCADE` foreign key. Callers must confirm with the user first.
  Future<int> delete(int id) =>
      _db.delete(table, where: 'id = ?', whereArgs: [id]);

  Future<int> setArchived(int id, bool archived) => _db.update(
        table,
        {
          'is_archived': archived ? 1 : 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Bumps `updated_at`, so the garage list reorders when entries are added.
  Future<int> touch(int id) => _db.update(
        table,
        {'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> count({bool includeArchived = false}) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table'
      '${includeArchived ? '' : ' WHERE is_archived = 0'}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteAll() => _db.delete(table);
}
