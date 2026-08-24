/// Works out what maintenance is due, and when (I19).
///
/// **Pure Dart. Do not import Flutter here** — same rule as the fuel engine,
/// for the same reason.
library;

import '../models/service_record.dart';

/// How close a reminder has to be before it is worth flagging.
const double kDueSoonDistanceKm = 500;
const int kDueSoonDays = 14;

enum ServiceStatus {
  /// Past its due odometer or due date.
  overdue,

  /// Within [kDueSoonDistanceKm] or [kDueSoonDays] of falling due.
  dueSoon,

  /// Tracked, but not close yet.
  upcoming,
}

/// A record that is watching for something, with how far off it is.
class ServiceReminder {
  const ServiceReminder({
    required this.record,
    required this.status,
    this.kilometresRemaining,
    this.daysRemaining,
  });

  final ServiceRecord record;
  final ServiceStatus status;

  /// Negative when already past the due odometer. Null when this reminder is
  /// not distance-tracked, or the vehicle's current odometer is unknown.
  final double? kilometresRemaining;

  /// Negative when already past the due date. Null when not date-tracked.
  final int? daysRemaining;

  bool get isOverdue => status == ServiceStatus.overdue;

  /// Which of the two limits will be reached first, as a 0..1 fraction of the
  /// way there. Used to order reminders against each other.
  ///
  /// Larger means more urgent; values above 1 are overdue.
  double get urgency {
    final byDistance = kilometresRemaining == null
        ? null
        : 1 - (kilometresRemaining! / kDueSoonDistanceKm).clamp(-99.0, 1.0);
    final byDate = daysRemaining == null
        ? null
        : 1 - (daysRemaining! / kDueSoonDays).clamp(-99.0, 1.0);

    if (byDistance == null) return byDate ?? 0;
    if (byDate == null) return byDistance;
    return byDistance > byDate ? byDistance : byDate;
  }
}

class ServicePlanner {
  const ServicePlanner._();

  /// Turns records into reminders, most urgent first.
  ///
  /// [currentOdometerKm] should be the highest odometer known for the vehicle
  /// — normally the latest fuel entry. When it is null, distance-based
  /// reminders simply report no distance, rather than assuming zero and
  /// declaring everything overdue.
  static List<ServiceReminder> remindersFor(
    List<ServiceRecord> records, {
    double? currentOdometerKm,
    DateTime? now,
  }) {
    final today = _midnight(now ?? DateTime.now());

    final reminders = <ServiceReminder>[];
    for (final record in records) {
      if (!record.hasReminder) continue;

      double? kilometresRemaining;
      final dueOdometer = record.nextDueOdometer;
      if (dueOdometer != null && currentOdometerKm != null) {
        kilometresRemaining = dueOdometer - currentOdometerKm;
      }

      int? daysRemaining;
      final dueAt = record.nextDueAt;
      if (dueAt != null) {
        daysRemaining = _midnight(dueAt).difference(today).inDays;
      }

      // Nothing measurable — a distance reminder on a vehicle with no
      // odometer history. Keep it out rather than show a blank row.
      if (kilometresRemaining == null && daysRemaining == null) continue;

      reminders.add(ServiceReminder(
        record: record,
        status: _statusFor(kilometresRemaining, daysRemaining),
        kilometresRemaining: kilometresRemaining,
        daysRemaining: daysRemaining,
      ));
    }

    reminders.sort((a, b) => b.urgency.compareTo(a.urgency));
    return reminders;
  }

  /// Whichever limit is worse decides the status: a service due in 3,000 km
  /// but 2 days overdue on time is overdue.
  static ServiceStatus _statusFor(double? kilometres, int? days) {
    final distanceOverdue = kilometres != null && kilometres <= 0;
    final dateOverdue = days != null && days <= 0;
    if (distanceOverdue || dateOverdue) return ServiceStatus.overdue;

    final distanceSoon = kilometres != null && kilometres <= kDueSoonDistanceKm;
    final dateSoon = days != null && days <= kDueSoonDays;
    if (distanceSoon || dateSoon) return ServiceStatus.dueSoon;

    return ServiceStatus.upcoming;
  }

  /// Reminders worth putting in front of the user unprompted.
  static List<ServiceReminder> attentionNeeded(
    List<ServiceRecord> records, {
    double? currentOdometerKm,
    DateTime? now,
  }) {
    return remindersFor(
      records,
      currentOdometerKm: currentOdometerKm,
      now: now,
    ).where((r) => r.status != ServiceStatus.upcoming).toList(growable: false);
  }

  /// Total spent on maintenance, which the fuel figures deliberately exclude.
  static double totalCost(List<ServiceRecord> records) =>
      records.fold<double>(0, (sum, record) => sum + record.cost);

  /// Cost per kilometre of ownership: fuel plus maintenance.
  ///
  /// Returns null when there is no measured distance to divide by.
  static double? runningCostPerKm({
    required double fuelCost,
    required double serviceCost,
    required double distanceKm,
  }) {
    if (distanceKm <= 0) return null;
    return (fuelCost + serviceCost) / distanceKm;
  }

  /// The next-due values to seed a form with, from the type's typical
  /// interval. Either may be null when the type is not tracked that way.
  static ({double? odometer, DateTime? date}) suggestNextDue(
    ServiceType type, {
    double? currentOdometerKm,
    DateTime? performedAt,
  }) {
    final from = performedAt ?? DateTime.now();

    final intervalKm = type.defaultIntervalKm;
    final intervalDays = type.defaultIntervalDays;

    return (
      odometer: (intervalKm != null && currentOdometerKm != null)
          ? currentOdometerKm + intervalKm
          : null,
      date: intervalDays != null
          ? DateTime(from.year, from.month, from.day + intervalDays)
          : null,
    );
  }

  static DateTime _midnight(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
