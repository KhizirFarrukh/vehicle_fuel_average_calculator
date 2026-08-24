import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens and migrates the local SQLite database.
///
/// Imports `dart:io`, so this file — and therefore the app's storage layer —
/// does not build for web. That is a deliberate, documented trade (see
/// docs/PLAN.md §4); the fix when web is wanted is `sqflite_common_ffi_web`,
/// and it is contained to this file plus [registerPlatformFactory].
class AppDatabase {
  AppDatabase._(this.db);

  /// Bump this and add a case to [_upgrade] whenever the schema changes.
  ///
  /// v2 added `service_records`.
  static const int schemaVersion = 2;
  static const String fileName = 'fuel_tracker.db';

  final Database db;

  static AppDatabase? _instance;

  /// Registers the FFI backend on desktop. Must be called before [open], and
  /// after `WidgetsFlutterBinding.ensureInitialized()`.
  static void registerPlatformFactory() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    // Android, iOS and macOS use the default sqflite factory.
  }

  static Future<AppDatabase> open({String? overridePath}) async {
    final existing = _instance;
    if (existing != null) return existing;

    final path = overridePath ?? await _resolvePath();

    final database = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _configure,
      onCreate: _create,
      onUpgrade: _upgrade,
    );

    final instance = AppDatabase._(database);
    _instance = instance;
    return instance;
  }

  /// For tests: open an in-memory database with the real schema.
  static Future<AppDatabase> openInMemory() async {
    final database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: _configure,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<String> _resolvePath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, fileName);
    }
    return p.join(await getDatabasesPath(), fileName);
  }

  static Future<void> _configure(Database db) async {
    // sqflite leaves foreign keys off by default, which would quietly turn
    // ON DELETE CASCADE into a no-op and orphan every entry of a deleted
    // vehicle.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE vehicles (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        make              TEXT    NOT NULL,
        model             TEXT    NOT NULL,
        variant           TEXT    NOT NULL,
        year              INTEGER,
        color             TEXT,
        license_plate     TEXT,
        fuel_type         TEXT    NOT NULL DEFAULT 'petrol',
        tank_capacity     REAL,
        initial_odometer  REAL,
        notes             TEXT,
        is_archived       INTEGER NOT NULL DEFAULT 0,
        created_at        INTEGER NOT NULL,
        updated_at        INTEGER NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE fuel_entries (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id     INTEGER NOT NULL,
        filled_at      INTEGER NOT NULL,
        odometer       REAL    NOT NULL,
        trip_meter     REAL,
        volume         REAL    NOT NULL,
        total_cost     REAL    NOT NULL,
        is_full_tank   INTEGER NOT NULL DEFAULT 1,
        missed_fill_up INTEGER NOT NULL DEFAULT 0,
        station        TEXT,
        notes          TEXT,
        created_at     INTEGER NOT NULL,
        updated_at     INTEGER NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE INDEX idx_entries_vehicle_odometer
        ON fuel_entries (vehicle_id, odometer)
    ''');

    batch.execute('''
      CREATE INDEX idx_entries_vehicle_date
        ON fuel_entries (vehicle_id, filled_at)
    ''');

    batch.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // v2. Shared with _upgrade so a fresh install and a migrated one cannot
    // end up with different schemas — the classic way migrations rot.
    for (final statement in _serviceRecordsV2) {
      batch.execute(statement);
    }

    await batch.commit(noResult: true);
  }

  /// Added in schema v2 (I19).
  static const List<String> _serviceRecordsV2 = [
    '''
      CREATE TABLE service_records (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        vehicle_id        INTEGER NOT NULL,
        type              TEXT    NOT NULL DEFAULT 'other',
        title             TEXT,
        performed_at      INTEGER NOT NULL,
        odometer          REAL,
        cost              REAL    NOT NULL DEFAULT 0,
        notes             TEXT,
        next_due_odometer REAL,
        next_due_at       INTEGER,
        created_at        INTEGER NOT NULL,
        updated_at        INTEGER NOT NULL,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
      )
    ''',
    '''
      CREATE INDEX idx_service_vehicle_date
        ON service_records (vehicle_id, performed_at)
    ''',
  ];

  static Future<void> _upgrade(Database db, int from, int to) async {
    // Migrations run in order; each case moves the schema forward by exactly
    // one version, so a database at any older version arrives intact.
    for (var version = from + 1; version <= to; version++) {
      switch (version) {
        case 2:
          for (final statement in _serviceRecordsV2) {
            await db.execute(statement);
          }
        default:
          break;
      }
    }
  }

  Future<void> close() async {
    await db.close();
    if (identical(_instance, this)) _instance = null;
  }
}
