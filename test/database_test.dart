import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vehicle_fuel_average_calculator/data/app_database.dart';
import 'package:vehicle_fuel_average_calculator/data/backup_service.dart';
import 'package:vehicle_fuel_average_calculator/data/fuel_entry_dao.dart';
import 'package:vehicle_fuel_average_calculator/data/settings_dao.dart';
import 'package:vehicle_fuel_average_calculator/data/vehicle_dao.dart';
import 'package:vehicle_fuel_average_calculator/models/app_settings.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_entry.dart';
import 'package:vehicle_fuel_average_calculator/models/vehicle.dart';

/// Exercises the real schema against an in-memory SQLite database.
///
/// Runs on the Dart VM through `sqflite_common_ffi`, so no device is needed.
void main() {
  late AppDatabase database;
  late VehicleDao vehicles;
  late FuelEntryDao entries;
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
    settings = SettingsDao(database.db);
    backup = BackupService(
      vehicles: vehicles,
      entries: entries,
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
