import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/domain/service_planner.dart';
import 'package:vehicle_fuel_average_calculator/models/service_record.dart';

final DateTime _today = DateTime(2026, 8, 24);

ServiceRecord record({
  required int id,
  ServiceType type = ServiceType.oilChange,
  double? odometer = 50000,
  double? nextDueOdometer,
  DateTime? nextDueAt,
  double cost = 0,
  String? title,
}) {
  return ServiceRecord(
    id: id,
    vehicleId: 1,
    type: type,
    title: title,
    performedAt: _today.subtract(const Duration(days: 30)),
    odometer: odometer,
    cost: cost,
    nextDueOdometer: nextDueOdometer,
    nextDueAt: nextDueAt,
    createdAt: _today,
    updatedAt: _today,
  );
}

void main() {
  group('status', () {
    test('a distance reminder still far off is upcoming', () {
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1, nextDueOdometer: 55000)],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders.single.status, ServiceStatus.upcoming);
      expect(reminders.single.kilometresRemaining, 5000);
    });

    test('within 500 km is due soon', () {
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1, nextDueOdometer: 50300)],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders.single.status, ServiceStatus.dueSoon);
      expect(reminders.single.kilometresRemaining, 300);
    });

    test('past the due odometer is overdue, with a negative remainder', () {
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1, nextDueOdometer: 49000)],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders.single.status, ServiceStatus.overdue);
      expect(reminders.single.kilometresRemaining, -1000);
      expect(reminders.single.isOverdue, isTrue);
    });

    test('date reminders work the same way', () {
      final reminders = ServicePlanner.remindersFor(
        [
          record(
            id: 1,
            type: ServiceType.insurance,
            odometer: null,
            nextDueAt: _today.add(const Duration(days: 5)),
          ),
        ],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders.single.status, ServiceStatus.dueSoon);
      expect(reminders.single.daysRemaining, 5);
      expect(reminders.single.kilometresRemaining, isNull);
    });

    test('whichever limit is worse decides the status', () {
      // Distance is comfortable, but the date has already passed.
      final reminders = ServicePlanner.remindersFor(
        [
          record(
            id: 1,
            nextDueOdometer: 60000,
            nextDueAt: _today.subtract(const Duration(days: 2)),
          ),
        ],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders.single.status, ServiceStatus.overdue);
      expect(reminders.single.kilometresRemaining, 10000);
      expect(reminders.single.daysRemaining, -2);
    });

    test('due today counts as overdue rather than nearly due', () {
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1, odometer: null, nextDueAt: _today)],
        now: _today,
      );
      expect(reminders.single.status, ServiceStatus.overdue);
      expect(reminders.single.daysRemaining, 0);
    });
  });

  group('what gets included', () {
    test('records with no reminder are left out', () {
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1), record(id: 2, nextDueOdometer: 55000)],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders, hasLength(1));
      expect(reminders.single.record.id, 2);
    });

    test('a distance reminder is skipped when the odometer is unknown', () {
      // Without a current reading, "overdue" would be a guess — and assuming
      // zero would declare everything overdue.
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1, nextDueOdometer: 55000)],
        now: _today,
      );
      expect(reminders, isEmpty);
    });

    test('a date reminder still works with no odometer', () {
      final reminders = ServicePlanner.remindersFor(
        [record(id: 1, nextDueAt: _today.add(const Duration(days: 100)))],
        now: _today,
      );
      expect(reminders, hasLength(1));
      expect(reminders.single.status, ServiceStatus.upcoming);
    });

    test('attentionNeeded drops anything not yet close', () {
      final records = [
        record(id: 1, nextDueOdometer: 90000), // far off
        record(id: 2, nextDueOdometer: 50100), // due soon
        record(id: 3, nextDueOdometer: 40000), // overdue
      ];

      final alerts = ServicePlanner.attentionNeeded(
        records,
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(alerts.map((a) => a.record.id), [3, 2]);
    });
  });

  group('ordering', () {
    test('most urgent first', () {
      final reminders = ServicePlanner.remindersFor(
        [
          record(id: 1, nextDueOdometer: 55000), // 5000 km away
          record(id: 2, nextDueOdometer: 48000), // 2000 km overdue
          record(id: 3, nextDueOdometer: 50200), // 200 km away
        ],
        currentOdometerKm: 50000,
        now: _today,
      );

      expect(reminders.map((r) => r.record.id), [2, 3, 1]);
    });
  });

  group('costs', () {
    test('totalCost sums every record', () {
      expect(
        ServicePlanner.totalCost([
          record(id: 1, cost: 5000),
          record(id: 2, cost: 2500),
          record(id: 3),
        ]),
        7500,
      );
      expect(ServicePlanner.totalCost([]), 0);
    });

    test('running cost combines fuel and maintenance', () {
      expect(
        ServicePlanner.runningCostPerKm(
          fuelCost: 8000,
          serviceCost: 2000,
          distanceKm: 1000,
        ),
        closeTo(10, 1e-9),
      );
      expect(
        ServicePlanner.runningCostPerKm(
          fuelCost: 8000,
          serviceCost: 2000,
          distanceKm: 0,
        ),
        isNull,
      );
    });
  });

  group('suggested next due', () {
    test('uses the type interval when there is one', () {
      final suggestion = ServicePlanner.suggestNextDue(
        ServiceType.oilChange,
        currentOdometerKm: 50000,
        performedAt: _today,
      );

      expect(suggestion.odometer, 55000); // 5,000 km interval
      expect(suggestion.date, DateTime(2026, 8, 24 + 180));
    });

    test('date-only types suggest no odometer', () {
      final suggestion = ServicePlanner.suggestNextDue(
        ServiceType.insurance,
        currentOdometerKm: 50000,
        performedAt: _today,
      );

      expect(suggestion.odometer, isNull);
      expect(suggestion.date, DateTime(2026, 8, 24 + 365));
    });

    test('distance-only types suggest no date', () {
      final suggestion = ServicePlanner.suggestNextDue(
        ServiceType.brakes,
        currentOdometerKm: 50000,
        performedAt: _today,
      );

      expect(suggestion.odometer, 75000);
      expect(suggestion.date, isNull);
    });

    test('no current odometer means no distance suggestion', () {
      final suggestion = ServicePlanner.suggestNextDue(
        ServiceType.oilChange,
        performedAt: _today,
      );
      expect(suggestion.odometer, isNull);
      expect(suggestion.date, isNotNull);
    });
  });

  group('ServiceRecord', () {
    test('falls back to the type label when untitled', () {
      expect(record(id: 1).displayTitle, 'Oil change');
      expect(record(id: 1, title: '  ').displayTitle, 'Oil change');
      expect(record(id: 1, title: 'Rear pads').displayTitle, 'Rear pads');
    });

    test('hasReminder reflects either due field', () {
      expect(record(id: 1).hasReminder, isFalse);
      expect(record(id: 1, nextDueOdometer: 1).hasReminder, isTrue);
      expect(record(id: 1, nextDueAt: _today).hasReminder, isTrue);
    });

    test('map round-trip preserves everything, nulls included', () {
      final full = record(
        id: 3,
        cost: 4500,
        title: 'Rear pads',
        nextDueOdometer: 75000,
        nextDueAt: _today,
      );
      expect(ServiceRecord.fromMap(full.toMap()), full);

      final sparse = record(id: 4, odometer: null);
      final restored = ServiceRecord.fromMap(sparse.toMap());
      expect(restored.odometer, isNull);
      expect(restored.nextDueOdometer, isNull);
      expect(restored.nextDueAt, isNull);
    });

    test('an unknown type falls back rather than throwing', () {
      final map = Map<String, Object?>.of(record(id: 1).toMap())
        ..['type'] = 'teleportation';
      expect(ServiceRecord.fromMap(map).type, ServiceType.other);
    });

    test('copyWith can clear the optional due fields', () {
      final tracked = record(id: 1, nextDueOdometer: 60000, nextDueAt: _today);
      expect(tracked.copyWith().nextDueOdometer, 60000);
      expect(tracked.copyWith(nextDueOdometer: null).nextDueOdometer, isNull);
      expect(tracked.copyWith(nextDueAt: null).nextDueAt, isNull);
    });
  });
}
