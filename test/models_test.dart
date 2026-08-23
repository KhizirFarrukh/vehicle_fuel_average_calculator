import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/core/units.dart';
import 'package:vehicle_fuel_average_calculator/models/app_settings.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_entry.dart';
import 'package:vehicle_fuel_average_calculator/models/vehicle.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(
    DateTime(2026, 8, 23, 14, 5).millisecondsSinceEpoch,
  );

  group('Vehicle', () {
    final full = Vehicle(
      id: 7,
      make: 'Toyota',
      model: 'Corolla',
      variant: 'Altis Grande',
      year: 2019,
      color: 'White',
      licensePlate: 'ABC-123',
      fuelType: FuelType.petrol,
      tankCapacity: 55,
      initialOdometer: 12000,
      notes: 'Family car',
      createdAt: now,
      updatedAt: now,
    );

    final minimal = Vehicle(
      make: 'Honda',
      model: 'Civic',
      variant: 'RS',
      createdAt: now,
      updatedAt: now,
    );

    test('required fields alone are enough', () {
      expect(minimal.year, isNull);
      expect(minimal.color, isNull);
      expect(minimal.licensePlate, isNull);
      expect(minimal.name, 'Honda Civic RS');
      expect(minimal.displayName, 'Honda Civic RS');
    });

    test('display name includes the year when there is one', () {
      expect(full.name, 'Toyota Corolla Altis Grande');
      expect(full.displayName, '2019 Toyota Corolla Altis Grande');
    });

    test('subtitle lists only the optional parts that exist', () {
      expect(full.subtitle, 'ABC-123 · White · Petrol');
      expect(minimal.subtitle, 'Petrol');
    });

    test('initials come from make and model', () {
      expect(full.initials, 'TC');
      expect(minimal.initials, 'HC');
    });

    test('map round-trip preserves everything', () {
      final restored = Vehicle.fromMap(full.toMap());
      expect(restored, full);
      expect(restored.createdAt.millisecondsSinceEpoch,
          full.createdAt.millisecondsSinceEpoch);
    });

    test('map round-trip preserves nulls', () {
      final restored = Vehicle.fromMap(minimal.toMap());
      expect(restored.year, isNull);
      expect(restored.color, isNull);
      expect(restored.licensePlate, isNull);
      expect(restored.tankCapacity, isNull);
    });

    test('an unsaved vehicle omits its id from the map', () {
      expect(minimal.toMap().containsKey('id'), isFalse);
      expect(full.toMap()['id'], 7);
    });

    test('booleans survive the integer column', () {
      final archived = full.copyWith(isArchived: true);
      expect(archived.toMap()['is_archived'], 1);
      expect(Vehicle.fromMap(archived.toMap()).isArchived, isTrue);
    });

    test('an unknown fuel type falls back rather than throwing', () {
      final map = Map<String, Object?>.of(full.toMap())
        ..['fuel_type'] = 'plutonium';
      expect(Vehicle.fromMap(map).fuelType, FuelType.petrol);
    });

    test('copyWith can clear an optional field, not just replace it', () {
      expect(full.copyWith().year, 2019);
      expect(full.copyWith(year: null).year, isNull);
      expect(full.copyWith(color: null).color, isNull);
      // Unrelated fields are untouched by a clear.
      expect(full.copyWith(year: null).make, 'Toyota');
    });
  });

  group('FuelEntry', () {
    final entry = FuelEntry(
      id: 3,
      vehicleId: 7,
      filledAt: now,
      odometer: 14500,
      tripMeter: 412,
      volume: 32.5,
      totalCost: 8125,
      isFullTank: true,
      station: 'Shell',
      notes: 'Motorway run',
      createdAt: now,
      updatedAt: now,
    );

    test('price per litre is derived, not stored', () {
      expect(entry.pricePerLitre, closeTo(8125 / 32.5, 1e-9));
      expect(entry.toMap().containsKey('price_per_litre'), isFalse);
    });

    test('a zero-volume entry yields no price rather than infinity', () {
      expect(entry.copyWith(volume: 0).pricePerLitre, isNull);
    });

    test('map round-trip preserves everything', () {
      expect(FuelEntry.fromMap(entry.toMap()), entry);
    });

    test('flags survive the integer columns', () {
      final partial = entry.copyWith(isFullTank: false, missedFillUp: true);
      expect(partial.toMap()['is_full_tank'], 0);
      expect(partial.toMap()['missed_fill_up'], 1);

      final restored = FuelEntry.fromMap(partial.toMap());
      expect(restored.isFullTank, isFalse);
      expect(restored.missedFillUp, isTrue);
    });

    test('copyWith can clear the optional trip meter', () {
      expect(entry.copyWith().tripMeter, 412);
      expect(entry.copyWith(tripMeter: null).tripMeter, isNull);
    });

    test('sorting is by odometer, with dates breaking ties', () {
      final a = entry.copyWith(id: 1, odometer: 100);
      final b = entry.copyWith(id: 2, odometer: 50);
      final list = [a, b]..sort(FuelEntry.compareByOdometer);
      expect(list.first.id, 2);

      final desc = [b, a]..sort(FuelEntry.compareByDateDesc);
      expect(desc.first.id, 1);
    });
  });

  group('AppSettings', () {
    test('defaults are metric with a neutral currency', () {
      const settings = AppSettings();
      expect(settings.distanceUnit, DistanceUnit.kilometre);
      expect(settings.volumeUnit, VolumeUnit.litre);
      expect(settings.economyUnit, EconomyUnit.kmPerLitre);
      expect(settings.themeMode, AppThemeMode.system);
    });

    test('key/value round-trip', () {
      const settings = AppSettings(
        distanceUnit: DistanceUnit.mile,
        volumeUnit: VolumeUnit.impGallon,
        economyUnit: EconomyUnit.milesPerImpGallon,
        currencySymbol: '£',
        themeMode: AppThemeMode.dark,
        lastVehicleId: 4,
      );

      expect(AppSettings.fromMap(settings.toMap()), settings);
    });

    test('unknown stored values fall back to the defaults', () {
      final settings = AppSettings.fromMap({
        AppSettings.keyDistanceUnit: 'furlongs',
        AppSettings.keyThemeMode: 'neon',
      });
      expect(settings.distanceUnit, DistanceUnit.kilometre);
      expect(settings.themeMode, AppThemeMode.system);
    });

    test('a missing last vehicle stays null', () {
      final settings = AppSettings.fromMap({});
      expect(settings.lastVehicleId, isNull);
      expect(
        AppSettings.fromMap(const AppSettings().toMap()).lastVehicleId,
        isNull,
      );
    });

    test('copyWith can clear the last vehicle', () {
      const settings = AppSettings(lastVehicleId: 4);
      expect(settings.copyWith().lastVehicleId, 4);
      expect(settings.copyWith(lastVehicleId: null).lastVehicleId, isNull);
    });
  });
}
