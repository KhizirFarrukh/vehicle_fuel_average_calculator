import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/domain/fuel_calculator.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_entry.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_stats.dart';

/// Day 1 of the log, so dates in the fixtures read as "day N".
final DateTime _start = DateTime(2026, 1, 1);

FuelEntry entry({
  required int id,
  required double odometer,
  required double volume,
  double cost = 100,
  bool full = true,
  bool missed = false,
  double? trip,
  int day = 0,
}) {
  final when = _start.add(Duration(days: day));
  return FuelEntry(
    id: id,
    vehicleId: 1,
    filledAt: when,
    odometer: odometer,
    tripMeter: trip,
    volume: volume,
    totalCost: cost,
    isFullTank: full,
    missedFillUp: missed,
    createdAt: when,
    updatedAt: when,
  );
}

void main() {
  group('no data', () {
    test('an empty log produces empty stats', () {
      final stats = FuelCalculator.analyze(1, []);
      expect(stats.hasEntries, isFalse);
      expect(stats.hasEconomy, isFalse);
      expect(stats.lifetimeKmPerLitre, isNull);
      expect(stats.points, isEmpty);
    });

    test('a single full tank cannot produce an average', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
      ]);
      expect(stats.hasEntries, isTrue);
      expect(stats.hasEconomy, isFalse);
      expect(stats.entryCount, 1);
      expect(stats.totalFuelLitres, 40);
    });
  });

  group('tank-to-tank windows', () {
    test('two full tanks give one point using the closing volume', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40, day: 0),
        entry(id: 2, odometer: 1400, volume: 32, day: 10),
      ]);

      expect(stats.points, hasLength(1));
      final point = stats.points.single;

      expect(point.distanceKm, 400);
      // The *opening* fill's 40 L must not be counted.
      expect(point.fuelLitres, 32);
      expect(point.kmPerLitre, closeTo(12.5, 1e-9));
      expect(point.fillCount, 1);
      expect(point.days, 10);
      expect(point.openingEntryId, 1);
      expect(point.entry.id, 2);
    });

    test('a partial fill rolls into the next full-tank window', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1200, volume: 15, full: false),
        entry(id: 3, odometer: 1400, volume: 20),
      ]);

      expect(stats.points, hasLength(1));
      final point = stats.points.single;

      expect(point.distanceKm, 400);
      expect(point.fuelLitres, 35); // 15 partial + 20 closing
      expect(point.fillCount, 2);
      expect(point.kmPerLitre, closeTo(400 / 35, 1e-9));
    });

    test('entries before the first full tank are skipped', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 20, full: false),
        entry(id: 2, odometer: 1400, volume: 30),
        entry(id: 3, odometer: 1800, volume: 25),
      ]);

      expect(stats.points, hasLength(1));
      expect(stats.points.single.openingEntryId, 2);
      expect(stats.points.single.fuelLitres, 25);
    });

    test('input order does not matter', () {
      final ordered = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1400, volume: 32),
        entry(id: 3, odometer: 1800, volume: 30),
      ]);
      final shuffled = FuelCalculator.analyze(1, [
        entry(id: 3, odometer: 1800, volume: 30),
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1400, volume: 32),
      ]);

      expect(shuffled.points.length, ordered.points.length);
      expect(
        shuffled.lifetimeKmPerLitre,
        closeTo(ordered.lifetimeKmPerLitre!, 1e-9),
      );
    });
  });

  group('missed fill-ups', () {
    test('a missed fill voids the window it closes and restarts the chain', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1400, volume: 32),
        entry(id: 3, odometer: 1800, volume: 30, missed: true),
        entry(id: 4, odometer: 2200, volume: 35),
      ]);

      expect(stats.points, hasLength(2));
      expect(stats.points[0].entry.id, 2);
      expect(stats.points[1].entry.id, 4);
      // The window that would have spanned the gap is gone, not merged.
      expect(stats.points[1].distanceKm, 400);
      expect(stats.points[1].fuelLitres, 35);
    });

    test('the missed litres still count towards total fuel and spend', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40, cost: 100),
        entry(id: 2, odometer: 1400, volume: 30, cost: 90, missed: true),
      ]);

      expect(stats.totalFuelLitres, 70);
      expect(stats.totalSpent, 190);
      expect(stats.hasEconomy, isFalse);
    });
  });

  group('lifetime average', () {
    test('is distance-weighted, not the mean of the windows', () {
      // Deliberately lopsided: a short, thirsty tank and a long, frugal one.
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40),
        entry(id: 2, odometer: 100, volume: 20), //  5 km/L over 100 km
        entry(id: 3, odometer: 1100, volume: 50), // 20 km/L over 1000 km
      ]);

      expect(stats.points, hasLength(2));

      // Weighted: 1100 km on 70 L.
      expect(stats.lifetimeKmPerLitre, closeTo(1100 / 70, 1e-9));
      // Unweighted mean of 5 and 20 would be 12.5 — much too optimistic.
      expect(stats.meanOfWindowsKmPerLitre, closeTo(12.5, 1e-9));
      expect(stats.lifetimeKmPerLitre, isNot(closeTo(12.5, 0.1)));
    });

    test('measured totals exclude unmeasurable stretches', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40, cost: 100),
        entry(id: 2, odometer: 1400, volume: 32, cost: 80),
      ]);

      expect(stats.totalFuelLitres, 72); // both fills
      expect(stats.measuredFuelLitres, 32); // only the closing fill
      expect(stats.totalSpent, 180);
      expect(stats.measuredCost, 80);
      expect(stats.costPerKm, closeTo(80 / 400, 1e-9));
    });
  });

  group('derived figures', () {
    test('best, worst and latest pick the right windows', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40, day: 0),
        entry(id: 2, odometer: 400, volume: 40, day: 10), // 10 km/L
        entry(id: 3, odometer: 800, volume: 25, day: 20), // 16 km/L
        entry(id: 4, odometer: 1200, volume: 32, day: 30), // 12.5 km/L
      ]);

      expect(stats.best!.entry.id, 3);
      expect(stats.worst!.entry.id, 2);
      expect(stats.latest!.entry.id, 4);
    });

    test('average price per litre spans every logged litre', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 10, cost: 30),
        entry(id: 2, odometer: 200, volume: 10, cost: 50),
      ]);
      expect(stats.averagePricePerLitre, closeTo(80 / 20, 1e-9));
    });

    test('range estimate needs both an average and a tank size', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40),
        entry(id: 2, odometer: 500, volume: 40), // 12.5 km/L
      ]);

      expect(stats.estimatedRangeKm(50), closeTo(625, 1e-9));
      expect(stats.estimatedRangeKm(null), isNull);
      expect(stats.estimatedRangeKm(0), isNull);
    });

    test('monthly spend buckets by calendar month in order', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 10, cost: 30, day: 0), // Jan
        entry(id: 2, odometer: 200, volume: 10, cost: 40, day: 10), // Jan
        entry(id: 3, odometer: 400, volume: 10, cost: 50, day: 40), // Feb
      ]);

      expect(stats.monthlySpend, hasLength(2));
      expect(stats.monthlySpend[0].month, DateTime(2026, 1));
      expect(stats.monthlySpend[0].cost, 70);
      expect(stats.monthlySpend[0].fills, 2);
      expect(stats.monthlySpend[1].month, DateTime(2026, 2));
      expect(stats.monthlySpend[1].cost, 50);
    });

    test('trend compares the latest window with the ones before it', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40),
        entry(id: 2, odometer: 400, volume: 40), // 10 km/L
        entry(id: 3, odometer: 800, volume: 40), // 10 km/L
        entry(id: 4, odometer: 1300, volume: 40), // 12.5 km/L
      ]);

      // Baseline is 10, latest is 12.5 -> +25 %.
      expect(stats.trendPercent, closeTo(25, 1e-9));
    });
  });

  group('quality checks', () {
    test('a wildly different window is flagged as an outlier', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40),
        entry(id: 2, odometer: 400, volume: 40), // 10 km/L
        entry(id: 3, odometer: 800, volume: 40), // 10 km/L
        entry(id: 4, odometer: 1200, volume: 40), // 10 km/L
        entry(id: 5, odometer: 2400, volume: 40), // 30 km/L — a typo
      ]);

      final flagged = stats.points.where((p) => p.isOutlier).toList();
      expect(flagged, hasLength(1));
      expect(flagged.single.entry.id, 5);
    });

    test('fewer than three windows are never flagged', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40),
        entry(id: 2, odometer: 400, volume: 40),
        entry(id: 3, odometer: 2000, volume: 40),
      ]);
      expect(stats.points.any((p) => p.isOutlier), isFalse);
    });

    test('two fills at the same odometer warn instead of dividing by zero', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1000, volume: 30),
      ]);

      expect(stats.points, isEmpty);
      expect(
        stats.issues.any((i) => i.severity == IssueSeverity.warning),
        isTrue,
      );
    });

    test('a trip meter that disagrees with the odometer is reported', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1400, volume: 32, trip: 250),
      ]);

      expect(
        stats.issuesFor(2).any((i) => i.kind == IssueKind.tripMismatch),
        isTrue,
      );

      // The engine's own sentence must not name a unit: it holds canonical
      // kilometres and cannot know the reader wants miles. The figures travel
      // as numbers for the UI to format.
      final issue =
          stats.issuesFor(2).firstWhere((i) => i.kind == IssueKind.tripMismatch);
      expect(issue.message, isNot(contains('km')));
      expect(issue.tripKm, 250);
      expect(issue.distanceKm, 400);
    });

    test('a trip meter that agrees is not reported', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 1000, volume: 40),
        entry(id: 2, odometer: 1400, volume: 32, trip: 402),
      ]);

      expect(stats.issuesFor(2).any((i) => i.kind == IssueKind.tripMismatch),
          isFalse);
    });
  });

  group('entry-form helpers', () {
    final entries = [
      entry(id: 1, odometer: 1000, volume: 40),
      entry(id: 2, odometer: 1400, volume: 32),
      entry(id: 3, odometer: 1800, volume: 30),
    ];

    test('lastOdometer finds the highest reading', () {
      expect(FuelCalculator.lastOdometer(entries), 1800);
      expect(FuelCalculator.lastOdometer(entries, excludingId: 3), 1400);
      expect(FuelCalculator.lastOdometer([]), isNull);
    });

    test('previousEntry finds the one just below a reading', () {
      expect(FuelCalculator.previousEntry(entries, 1500)?.id, 2);
      expect(FuelCalculator.previousEntry(entries, 1000), isNull);
      expect(
        FuelCalculator.previousEntry(entries, 1500, excludingId: 2)?.id,
        1,
      );
    });

    test('simpleAverage keeps the original behaviour and guards zero', () {
      expect(FuelCalculator.simpleAverage(400, 32), closeTo(12.5, 1e-9));
      expect(FuelCalculator.simpleAverage(400, 0), isNull);
      expect(FuelCalculator.simpleAverage(-1, 10), isNull);
    });

    test('fuelNeeded and rangeFor invert each other', () {
      final litres = FuelCalculator.fuelNeeded(500, 12.5)!;
      expect(litres, closeTo(40, 1e-9));
      expect(FuelCalculator.rangeFor(litres, 12.5), closeTo(500, 1e-9));
      expect(FuelCalculator.fuelNeeded(500, 0), isNull);
    });

    test('rollingAverage smooths over the requested window', () {
      final stats = FuelCalculator.analyze(1, [
        entry(id: 1, odometer: 0, volume: 40),
        entry(id: 2, odometer: 400, volume: 40), // 10
        entry(id: 3, odometer: 1200, volume: 40), // 20
      ]);

      final rolling = FuelCalculator.rollingAverage(stats.points, 2);
      expect(rolling, hasLength(2));
      expect(rolling[0], closeTo(10, 1e-9));
      expect(rolling[1], closeTo(15, 1e-9));
    });
  });
}
