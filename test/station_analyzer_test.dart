import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/domain/station_analyzer.dart';
import 'package:vehicle_fuel_average_calculator/models/fuel_entry.dart';

final DateTime _now = DateTime(2026, 8, 25);

FuelEntry entry({
  required int id,
  String? station,
  double volume = 40,
  double cost = 10000,
  int daysAgo = 0,
}) {
  final when = _now.subtract(Duration(days: daysAgo));
  return FuelEntry(
    id: id,
    vehicleId: 1,
    filledAt: when,
    odometer: 1000.0 * id,
    volume: volume,
    totalCost: cost,
    station: station,
    createdAt: when,
    updatedAt: when,
  );
}

void main() {
  group('normalise', () {
    test('folds case and collapses whitespace', () {
      expect(StationAnalyzer.normalise('  Shell  '), 'shell');
      expect(StationAnalyzer.normalise('SHELL'), 'shell');
      expect(StationAnalyzer.normalise('Shell   Main  Street'),
          'shell main street');
    });
  });

  group('analyze', () {
    test('groups spellings of the same station together', () {
      final stations = StationAnalyzer.analyze([
        entry(id: 1, station: 'Shell'),
        entry(id: 2, station: '  shell '),
        entry(id: 3, station: 'SHELL'),
      ]);

      expect(stations, hasLength(1));
      expect(stations.single.fills, 3);
    });

    test('ignores entries with no station', () {
      final stations = StationAnalyzer.analyze([
        entry(id: 1, station: 'Shell'),
        entry(id: 2),
        entry(id: 3, station: '   '),
      ]);

      expect(stations, hasLength(1));
      expect(stations.single.fills, 1);
    });

    test('totals volume, cost and dates per station', () {
      final stations = StationAnalyzer.analyze([
        entry(id: 1, station: 'Shell', volume: 30, cost: 7500, daysAgo: 20),
        entry(id: 2, station: 'Shell', volume: 10, cost: 2500, daysAgo: 5),
      ]);

      final shell = stations.single;
      expect(shell.totalVolume, 40);
      expect(shell.totalCost, 10000);
      expect(shell.averagePricePerLitre, closeTo(250, 1e-9));
      expect(shell.firstVisit, _now.subtract(const Duration(days: 20)));
      expect(shell.lastVisit, _now.subtract(const Duration(days: 5)));
      expect(shell.lastPricePerLitre, closeTo(250, 1e-9));
    });

    test('most-visited first', () {
      final stations = StationAnalyzer.analyze([
        entry(id: 1, station: 'Total'),
        entry(id: 2, station: 'Shell'),
        entry(id: 3, station: 'Shell'),
        entry(id: 4, station: 'Shell'),
      ]);

      expect(stations.map((s) => s.name), ['Shell', 'Total']);
    });

    test('an empty log gives no stations', () {
      expect(StationAnalyzer.analyze([]), isEmpty);
    });
  });

  group('knownNames', () {
    test('most recently used first', () {
      final names = StationAnalyzer.knownNames([
        entry(id: 1, station: 'Total', daysAgo: 50),
        entry(id: 2, station: 'Shell', daysAgo: 2),
        entry(id: 3, station: 'Caltex', daysAgo: 20),
      ]);

      expect(names, ['Shell', 'Caltex', 'Total']);
    });

    test('one entry per station regardless of spelling', () {
      final names = StationAnalyzer.knownNames([
        entry(id: 1, station: 'Shell', daysAgo: 10),
        entry(id: 2, station: 'shell', daysAgo: 1),
      ]);

      expect(names, hasLength(1));
    });

    test('an empty log gives no suggestions', () {
      expect(StationAnalyzer.knownNames([entry(id: 1)]), isEmpty);
    });
  });

  group('cheapest', () {
    test('ranks by average price, cheapest first', () {
      final ranked = StationAnalyzer.cheapest(
        [
          entry(id: 1, station: 'Shell', volume: 10, cost: 2600, daysAgo: 10),
          entry(id: 2, station: 'Shell', volume: 10, cost: 2600, daysAgo: 5),
          entry(id: 3, station: 'Total', volume: 10, cost: 2400, daysAgo: 10),
          entry(id: 4, station: 'Total', volume: 10, cost: 2400, daysAgo: 5),
        ],
        now: _now,
      );

      expect(ranked.map((s) => s.name), ['Total', 'Shell']);
      expect(ranked.first.averagePricePerLitre, closeTo(240, 1e-9));
    });

    test('ignores fills outside the window', () {
      // Total is cheaper, but only on visits from two years ago.
      final ranked = StationAnalyzer.cheapest(
        [
          entry(id: 1, station: 'Shell', volume: 10, cost: 2600, daysAgo: 10),
          entry(id: 2, station: 'Shell', volume: 10, cost: 2600, daysAgo: 5),
          entry(id: 3, station: 'Total', volume: 10, cost: 1000, daysAgo: 700),
          entry(id: 4, station: 'Total', volume: 10, cost: 1000, daysAgo: 690),
        ],
        now: _now,
      );

      // Only one station left inside the window, so no ranking is offered.
      expect(ranked, isEmpty);
    });

    test('a station with too few visits is not ranked', () {
      final ranked = StationAnalyzer.cheapest(
        [
          entry(id: 1, station: 'Shell', volume: 10, cost: 2600, daysAgo: 10),
          entry(id: 2, station: 'Shell', volume: 10, cost: 2600, daysAgo: 5),
          entry(id: 3, station: 'Total', volume: 10, cost: 1000, daysAgo: 3),
        ],
        now: _now,
      );

      expect(ranked, isEmpty);
    });

    test('a single station is never presented as a ranking', () {
      final ranked = StationAnalyzer.cheapest(
        [
          entry(id: 1, station: 'Shell', volume: 10, cost: 2600, daysAgo: 10),
          entry(id: 2, station: 'Shell', volume: 10, cost: 2600, daysAgo: 5),
        ],
        now: _now,
      );

      expect(ranked, isEmpty);
    });
  });

  group('relativePrice', () {
    test('reports how a station compares with everywhere else', () {
      final entries = [
        entry(id: 1, station: 'Shell', volume: 10, cost: 2200, daysAgo: 5),
        entry(id: 2, station: 'Total', volume: 10, cost: 2000, daysAgo: 5),
      ];

      // 220 against 200 is 10% dearer.
      expect(
        StationAnalyzer.relativePrice(entries, 'Shell', now: _now),
        closeTo(10, 1e-9),
      );
      // And the other way round.
      expect(
        StationAnalyzer.relativePrice(entries, 'Total', now: _now),
        closeTo(-9.0909, 1e-3),
      );
    });

    test('null when there is nothing to compare against', () {
      final entries = [
        entry(id: 1, station: 'Shell', volume: 10, cost: 2200, daysAgo: 5),
      ];
      expect(StationAnalyzer.relativePrice(entries, 'Shell', now: _now), isNull);
      expect(StationAnalyzer.relativePrice(entries, 'Total', now: _now), isNull);
    });

    test('matches regardless of spelling', () {
      final entries = [
        entry(id: 1, station: 'SHELL', volume: 10, cost: 2200, daysAgo: 5),
        entry(id: 2, station: 'Total', volume: 10, cost: 2000, daysAgo: 5),
      ];
      expect(
        StationAnalyzer.relativePrice(entries, '  shell ', now: _now),
        closeTo(10, 1e-9),
      );
    });
  });
}
