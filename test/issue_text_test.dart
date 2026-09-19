import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/core/issue_text.dart';
import 'package:vehicle_fuel_average_calculator/core/unit_formatter.dart';
import 'package:vehicle_fuel_average_calculator/core/units.dart';
import 'package:vehicle_fuel_average_calculator/domain/fuel_calculator.dart';
import 'package:vehicle_fuel_average_calculator/models/app_settings.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_entry.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_stats.dart';

const metric = UnitFormatter(AppSettings());
const imperial = UnitFormatter(AppSettings(
  distanceUnit: DistanceUnit.mile,
  volumeUnit: VolumeUnit.usGallon,
  economyUnit: EconomyUnit.milesPerUsGallon,
));

EntryIssue issue(
  IssueKind kind, {
  double? distanceKm,
  double? odometerKm,
  double? tripKm,
  String message = 'fallback sentence',
}) {
  return EntryIssue(
    entryId: 1,
    severity: IssueSeverity.warning,
    kind: kind,
    message: message,
    distanceKm: distanceKm,
    odometerKm: odometerKm,
    tripKm: tripKm,
  );
}

void main() {
  group('unit awareness', () {
    test('renders a trip mismatch in the reader\'s units', () {
      final mismatch = issue(
        IssueKind.tripMismatch,
        tripKm: 250,
        distanceKm: 400,
      );

      expect(describeIssue(mismatch, metric), contains('250 km'));
      expect(describeIssue(mismatch, metric), contains('400 km'));

      // 400 km is ~249 mi. The point of the whole change: a miles reader must
      // never be shown a kilometre figure labelled km.
      final text = describeIssue(mismatch, imperial);
      expect(text, contains('mi'));
      expect(text, isNot(contains('km')));
      expect(text, contains('249'));
    });

    test('renders a duplicate odometer in the reader\'s units', () {
      final duplicate = issue(IssueKind.duplicateOdometer, odometerKm: 1000);
      expect(describeIssue(duplicate, metric), contains('1,000 km'));
      expect(describeIssue(duplicate, imperial), isNot(contains('km')));
    });

    test('renders a too-short window in the reader\'s units', () {
      final short = issue(IssueKind.windowTooShort, distanceKm: 0.5);
      expect(describeIssue(short, metric), contains('0.5 km'));
      expect(describeIssue(short, imperial), isNot(contains('km')));
    });
  });

  group('fallbacks', () {
    test('kinds with no figures use the engine sentence unchanged', () {
      for (final kind in [IssueKind.missedFillUp, IssueKind.dateOutOfOrder]) {
        expect(describeIssue(issue(kind), metric), 'fallback sentence');
      }
    });

    test('a missing figure falls back rather than printing null', () {
      // Defensive: should not happen, but must not render "null km".
      expect(
        describeIssue(issue(IssueKind.tripMismatch), metric),
        'fallback sentence',
      );
      expect(
        describeIssue(issue(IssueKind.duplicateOdometer), metric),
        'fallback sentence',
      );
    });
  });

  group('the engine emits unit-free sentences', () {
    // Guards the layering rule: lib/domain/ has no UnitFormatter and stores
    // canonical kilometres, so its own text must never name a unit.
    test('no issue message from a real analysis mentions km', () {
      final stats = FuelCalculator.analyze(1, [
        FuelEntry(
          id: 1,
          vehicleId: 1,
          filledAt: DateTime(2026, 1, 1),
          odometer: 1000,
          volume: 40,
          totalCost: 100,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        // Same odometer -> duplicate warning and a zero-length window.
        FuelEntry(
          id: 2,
          vehicleId: 1,
          filledAt: DateTime(2026, 1, 10),
          odometer: 1000,
          volume: 30,
          totalCost: 90,
          tripMeter: 250,
          createdAt: DateTime(2026, 1, 10),
          updatedAt: DateTime(2026, 1, 10),
        ),
      ]);

      expect(stats.issues, isNotEmpty);
      for (final raised in stats.issues) {
        expect(
          raised.message,
          isNot(contains('km')),
          reason: 'engine text must be unit-free: ${raised.message}',
        );
      }
    });
  });
}
