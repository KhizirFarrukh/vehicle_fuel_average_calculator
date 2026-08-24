import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vehicle_fuel_average_calculator/data/app_database.dart';
import 'package:vehicle_fuel_average_calculator/data/backup_service.dart';
import 'package:vehicle_fuel_average_calculator/data/fuel_entry_dao.dart';
import 'package:vehicle_fuel_average_calculator/data/service_dao.dart';
import 'package:vehicle_fuel_average_calculator/data/settings_dao.dart';
import 'package:vehicle_fuel_average_calculator/data/vehicle_dao.dart';
import 'package:vehicle_fuel_average_calculator/models/app_settings.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_entry.dart';
import 'package:vehicle_fuel_average_calculator/models/service_record.dart';
import 'package:vehicle_fuel_average_calculator/models/vehicle.dart';

/// Exercises the real schema against an in-memory SQLite database.
///
/// Runs on the Dart VM through `sqflite_common_ffi`, so no device is needed.
void main() {
  late AppDatabase database;
  late VehicleDao vehicles;
  late FuelEntryDao entries;
  late ServiceDao services;
  late SettingsDao settings;
  late BackupService backup;

  final now = DateTime.fromMillisecondsSinceEpoch(
    DateTime(2026, 8, 23).millisecondsSinceEpoch,
  );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await AppDatabase.openInMemory();
    vehicles = VehicleDao(database.db);
    entries = FuelEntryDao(database.db);
    services = ServiceDao(database.db);
    settings = SettingsDao(database.db);
    backup = BackupService(
      vehicles: vehicles,
      entries: entries,
      services: services,
      settings: settings,
    );
  });

  tearDown(() async => database.close());

  Vehicle sampleVehicle({String make = 'Toyota', bool minimal = false}) {
    return Vehicle(
      make: make,
      model: 'Corolla',
      variant: 'Altis',
      year: minimal ? null : 2019,
      color: minimal ? null : 'White',
      licensePlate: minimal ? null : 'ABC-123',
      tankCapacity: minimal ? null : 55,
      createdAt: now,
      updatedAt: now,
    );
  }

  FuelEntry sampleEntry(int vehicleId, double odometer, double volume) {
    return FuelEntry(
      vehicleId: vehicleId,
      filledAt: now,
      odometer: odometer,
      volume: volume,
      totalCost: volume * 250,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('schema and vehicle CRUD', () {
    test('a vehicle round-trips through the database', () async {
      final id = await vehicles.insert(sampleVehicle());
      final loaded = await vehicles.getById(id);

      expect(loaded, isNotNull);
      expect(loaded!.make, 'Toyota');
      expect(loaded.variant, 'Altis');
      expect(loaded.year, 2019);
      expect(loaded.licensePlate, 'ABC-123');
      expect(loaded.isArchived, isFalse);
    });

    test('the optional columns accept nulls', () async {
      final id = await vehicles.insert(sampleVehicle(minimal: true));
      final loaded = await vehicles.getById(id);

      expect(loaded!.year, isNull);
      expect(loaded.color, isNull);
      expect(loaded.licensePlate, isNull);
      expect(loaded.tankCapacity, isNull);
    });

    test('archived vehicles are filtered out by default', () async {
      final keep = await vehicles.insert(sampleVehicle());
      final hide = await vehicles.insert(sampleVehicle(make: 'Honda'));
      await vehicles.setArchived(hide, true);

      final active = await vehicles.getAll();
      expect(active.map((v) => v.id), [keep]);
      expect((await vehicles.getAll(includeArchived: true)), hasLength(2));
      expect(await vehicles.count(), 1);
    });

    test('updating requires an id', () async {
      expect(
        () => vehicles.update(sampleVehicle()),
        throwsArgumentError,
      );
    });
  });

  group('entries', () {
    test('come back ordered by odometer', () async {
      final id = await vehicles.insert(sampleVehicle());
      await entries.insert(sampleEntry(id, 1400, 32));
      await entries.insert(sampleEntry(id, 1000, 40));
      await entries.insert(sampleEntry(id, 1800, 30));

      final loaded = await entries.getForVehicle(id);
      expect(loaded.map((e) => e.odometer), [1000, 1400, 1800]);
    });

    test('are scoped to their own vehicle', () async {
      final first = await vehicles.insert(sampleVehicle());
      final second = await vehicles.insert(sampleVehicle(make: 'Honda'));
      await entries.insert(sampleEntry(first, 1000, 40));
      await entries.insert(sampleEntry(second, 5000, 20));

      expect(await entries.countForVehicle(first), 1);
      expect(await entries.countForVehicle(second), 1);
      expect((await entries.getForVehicle(first)).single.odometer, 1000);
    });

    test('deleting a vehicle cascades to its entries', () async {
      final id = await vehicles.insert(sampleVehicle());
      await entries.insert(sampleEntry(id, 1000, 40));
      await entries.insert(sampleEntry(id, 1400, 32));
      expect(await entries.countForVehicle(id), 2);

      await vehicles.delete(id);

      // Proves `PRAGMA foreign_keys = ON` actually took effect.
      expect(await entries.countForVehicle(id), 0);
      expect(await entries.getAll(), isEmpty);
    });

    test('latestForVehicle picks the most recent fill', () async {
      final id = await vehicles.insert(sampleVehicle());
      await entries.insert(sampleEntry(id, 1000, 40));
      await entries.insert(
        sampleEntry(id, 1400, 32).copyWith(
          filledAt: now.add(const Duration(days: 5)),
          station: 'Shell',
        ),
      );

      final latest = await entries.latestForVehicle(id);
      expect(latest!.odometer, 1400);
      expect(latest.station, 'Shell');
    });
  });

  group('service records (schema v2)', () {
    ServiceRecord sampleService(
      int vehicleId, {
      ServiceType type = ServiceType.oilChange,
      double? odometer = 50000,
      double? nextDueOdometer,
      DateTime? nextDueAt,
    }) {
      return ServiceRecord(
        vehicleId: vehicleId,
        type: type,
        performedAt: now,
        odometer: odometer,
        cost: 4500,
        nextDueOdometer: nextDueOdometer,
        nextDueAt: nextDueAt,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('round-trips, nullable columns included', () async {
      final vehicleId = await vehicles.insert(sampleVehicle());
      await services.insert(sampleService(
        vehicleId,
        nextDueOdometer: 55000,
        nextDueAt: now,
      ));
      await services.insert(sampleService(
        vehicleId,
        type: ServiceType.insurance,
        odometer: null,
      ));

      final loaded = await services.getForVehicle(vehicleId);
      expect(loaded, hasLength(2));

      final insurance =
          loaded.firstWhere((r) => r.type == ServiceType.insurance);
      expect(insurance.odometer, isNull);
      expect(insurance.nextDueOdometer, isNull);
      expect(insurance.nextDueAt, isNull);

      final oil = loaded.firstWhere((r) => r.type == ServiceType.oilChange);
      expect(oil.nextDueOdometer, 55000);
      expect(oil.nextDueAt, now);
      expect(oil.cost, 4500);
    });

    test('are scoped to their vehicle and cascade on delete', () async {
      final first = await vehicles.insert(sampleVehicle());
      final second = await vehicles.insert(sampleVehicle(make: 'Honda'));
      await services.insert(sampleService(first));
      await services.insert(sampleService(second));

      expect(await services.countForVehicle(first), 1);

      await vehicles.delete(first);

      expect(await services.countForVehicle(first), 0);
      expect(await services.countForVehicle(second), 1);
    });

    test('updating requires an id', () async {
      expect(() => services.update(sampleService(1)), throwsArgumentError);
    });
  });

  group('migration', () {
    test('a v1 database gains service_records on upgrade', () async {
      // A real file, not `:memory:` — each in-memory open is a *new* database,
      // so a migration cannot be observed across one.
      final dir = await Directory.systemTemp.createTemp('fuel_migration');
      final path = p.join(dir.path, 'v1.db');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // A locked file on Windows is not worth failing a passing test over.
        }
      });

      // Build the v1 schema by hand, then let the real migration run over it.
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE vehicles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                make TEXT NOT NULL, model TEXT NOT NULL, variant TEXT NOT NULL,
                year INTEGER, color TEXT, license_plate TEXT,
                fuel_type TEXT NOT NULL DEFAULT 'petrol',
                tank_capacity REAL, initial_odometer REAL, notes TEXT,
                is_archived INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE fuel_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                vehicle_id INTEGER NOT NULL, filled_at INTEGER NOT NULL,
                odometer REAL NOT NULL, trip_meter REAL, volume REAL NOT NULL,
                total_cost REAL NOT NULL,
                is_full_tank INTEGER NOT NULL DEFAULT 1,
                missed_fill_up INTEGER NOT NULL DEFAULT 0,
                station TEXT, notes TEXT,
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
                FOREIGN KEY (vehicle_id) REFERENCES vehicles (id) ON DELETE CASCADE
              )
            ''');
            await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          },
        ),
      );

      await v1.insert('vehicles', {
        'make': 'Toyota',
        'model': 'Corolla',
        'variant': 'Altis',
        'fuel_type': 'petrol',
        'is_archived': 0,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });

      final tablesBefore = await v1.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type='table' AND name='service_records'",
      );
      expect(tablesBefore, isEmpty);
      await v1.close();

      // Reopening through AppDatabase runs the real _upgrade path.
      final upgraded = await AppDatabase.open(overridePath: path);
      addTearDown(upgraded.close);

      final tablesAfter = await upgraded.db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type='table' AND name='service_records'",
      );
      expect(tablesAfter, hasLength(1));

      // The v1 data must still be there — a migration that drops rows is
      // worse than no migration.
      final vehicleDao = VehicleDao(upgraded.db);
      final survivors = await vehicleDao.getAll();
      expect(survivors, hasLength(1));
      expect(survivors.single.make, 'Toyota');

      // And the new table must actually work.
      final serviceDao = ServiceDao(upgraded.db);
      await serviceDao.insert(
        ServiceRecord(
          vehicleId: survivors.single.id!,
          type: ServiceType.oilChange,
          performedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(await serviceDao.countForVehicle(survivors.single.id!), 1);
    });

    test('the schema version is the one the code expects', () {
      expect(AppDatabase.schemaVersion, 2);
    });
  });

  group('settings', () {
    test('round-trip through the key/value table', () async {
      const stored = AppSettings(
        currencySymbol: 'Rs ',
        themeMode: AppThemeMode.dark,
        lastVehicleId: 3,
      );
      await settings.save(stored);
      expect(await settings.load(), stored);
    });

    test('an empty table yields the defaults', () async {
      expect(await settings.load(), const AppSettings());
    });

    test('writing the same key twice replaces rather than fails', () async {
      await settings.put('currency_symbol', 'A');
      await settings.put('currency_symbol', 'B');
      expect(await settings.get('currency_symbol'), 'B');
    });
  });

  group('backup', () {
    Future<void> seed() async {
      final id = await vehicles.insert(sampleVehicle());
      await entries.insert(sampleEntry(id, 1000, 40));
      await entries.insert(sampleEntry(id, 1400, 32));
      await vehicles.insert(sampleVehicle(make: 'Honda', minimal: true));
      await settings.save(const AppSettings(currencySymbol: 'Rs '));
    }

    test('export then replace-restore reproduces the garage', () async {
      await seed();
      final json = await backup.exportJsonString();

      final result = await backup.restoreFromJson(json);

      expect(result.vehiclesAdded, 2);
      expect(result.entriesAdded, 2);
      expect(await vehicles.count(includeArchived: true), 2);
      expect(await entries.getAll(), hasLength(2));

      final restored = await vehicles.getAll();
      final toyota = restored.firstWhere((v) => v.make == 'Toyota');
      expect(await entries.countForVehicle(toyota.id!), 2);
      expect((await settings.load()).currencySymbol, 'Rs ');
    });

    test('merge keeps what is already there and remaps ids', () async {
      await seed();
      final json = await backup.exportJsonString();

      await backup.restoreFromJson(json, mode: RestoreMode.merge);

      expect(await vehicles.count(includeArchived: true), 4);
      expect(await entries.getAll(), hasLength(4));

      // Every entry must still point at a vehicle that exists.
      final ids =
          (await vehicles.getAll(includeArchived: true)).map((v) => v.id).toSet();
      for (final entry in await entries.getAll()) {
        expect(ids, contains(entry.vehicleId));
      }
    });

    test('service records survive an export and restore', () async {
      final vehicleId = await vehicles.insert(sampleVehicle());
      await entries.insert(sampleEntry(vehicleId, 1000, 40));
      await services.insert(ServiceRecord(
        vehicleId: vehicleId,
        type: ServiceType.oilChange,
        performedAt: now,
        odometer: 50000,
        cost: 4500,
        nextDueOdometer: 55000,
        createdAt: now,
        updatedAt: now,
      ));

      final json = await backup.exportJsonString();
      final result = await backup.restoreFromJson(json);

      expect(result.servicesAdded, 1);

      final restoredVehicle = (await vehicles.getAll()).single;
      final restored =
          (await services.getForVehicle(restoredVehicle.id!)).single;

      // Re-pointed at the id the vehicle actually received.
      expect(restored.vehicleId, restoredVehicle.id);
      expect(restored.type, ServiceType.oilChange);
      expect(restored.cost, 4500);
      expect(restored.nextDueOdometer, 55000);
    });

    test('a v1 backup with no services array still restores', () async {
      final json = '{"format": "${BackupService.formatId}", "version": 1, '
          '"vehicles": [{"make": "Toyota", "model": "Corolla", '
          '"variant": "Altis", "fuel_type": "petrol", "is_archived": 0, '
          '"created_at": 0, "updated_at": 0, "entries": []}]}';

      final result = await backup.restoreFromJson(json);

      expect(result.vehiclesAdded, 1);
      expect(result.servicesAdded, 0);
      expect(await vehicles.count(), 1);
    });

    test('a foreign JSON file is rejected with a readable message', () async {
      expect(
        () => backup.restoreFromJson('{"hello": "world"}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => backup.restoreFromJson('not json at all'),
        throwsA(isA<FormatException>()),
      );
    });

    test('a newer format version is refused rather than half-read', () async {
      final json = '{"format": "${BackupService.formatId}", '
          '"version": 999, "vehicles": []}';
      expect(
        () => backup.restoreFromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('CSV export has a header and one row per entry', () async {
      await seed();
      final csv = await backup.exportCsvString();
      final lines = csv.trim().split('\n');

      expect(lines.first, startsWith('Vehicle,Make,Model,Variant'));
      expect(lines, hasLength(3)); // header + two entries
      expect(lines[1], contains('Toyota'));
    });

    test('CSV quotes fields that contain commas', () async {
      final id = await vehicles.insert(sampleVehicle());
      await entries.insert(
        sampleEntry(id, 1000, 40).copyWith(notes: 'Long trip, motorway'),
      );

      final csv = await backup.exportCsvString();
      expect(csv, contains('"Long trip, motorway"'));
    });
  });
}
