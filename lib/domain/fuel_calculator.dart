/// The fuel-economy engine.
///
/// **Pure Dart. Do not import Flutter here** — this file is the one piece of
/// the app whose correctness actually matters, and keeping it framework-free
/// keeps it unit-testable without a widget binding.
///
/// ## Why not `distance / fuel`?
///
/// The original app computed `distance / fuel` from two numbers typed by hand.
/// That answers "what average did this one tank give, assuming I know exactly
/// how much fuel that distance consumed?" — and a driver almost never knows
/// that, because the tank is never empty at either end of a journey.
///
/// The standard correct method is **tank-to-tank between full fills**:
///
/// > Fill to full at odometer O2, having last filled to full at O1. The fuel
/// > just pumped in is *exactly* the fuel burned over `O2 - O1`, because the
/// > tank has been returned to the same reference level.
///
/// So, for a window closing at a full-tank entry:
///
/// ```text
/// distance = odometer(close) - odometer(previous full-tank entry)
/// fuel     = volume(close) + volume of every partial fill in between
/// economy  = distance / fuel
/// ```
///
/// The *closing* fill's volume counts; the *opening* fill's does not. This is
/// the part people get wrong.
library;

import 'dart:math' as math;

import '../models/fuel_entry.dart';
import '../models/fuel_stats.dart';

/// Fraction by which a window average may differ from the median before it is
/// flagged as suspicious (I10).
const double kOutlierThreshold = 0.40;

/// Fraction by which the trip meter may disagree with the odometer delta
/// before it is worth mentioning (I11).
const double kTripMismatchThreshold = 0.05;

/// Below this many kilometres a "window" is almost certainly a data-entry
/// artefact (two fills logged at the same reading) rather than real driving.
const double kMinWindowDistanceKm = 1.0;

/// Stateless analysis over a vehicle's refuelling log.
class FuelCalculator {
  const FuelCalculator._();

  /// The single entry point. Returns every derived figure the UI needs.
  ///
  /// [entries] may arrive in any order and may contain entries for one vehicle
  /// only; it is copied and sorted internally, so the caller's list is not
  /// mutated.
  static VehicleStats analyze(int vehicleId, List<FuelEntry> entries) {
    if (entries.isEmpty) return VehicleStats.empty(vehicleId);

    final sorted = List<FuelEntry>.of(entries)
      ..sort(FuelEntry.compareByOdometer);

    final issues = <EntryIssue>[];
    final rawPoints = _buildPoints(sorted, issues);
    final points = _flagOutliers(rawPoints);

    // Totals across *every* entry, measured stretches or not.
    var totalFuel = 0.0;
    var totalSpent = 0.0;
    for (final entry in sorted) {
      totalFuel += entry.volume;
      totalSpent += entry.totalCost;
    }

    // Totals across the stretches where economy was actually computable.
    var measuredDistance = 0.0;
    var measuredFuel = 0.0;
    var measuredCost = 0.0;
    for (final point in points) {
      measuredDistance += point.distanceKm;
      measuredFuel += point.fuelLitres;
      measuredCost += point.cost;
    }

    _checkOdometerMonotonic(sorted, issues);
    _checkTripMeters(points, issues);

    final byDate = List<FuelEntry>.of(sorted)
      ..sort((a, b) => a.filledAt.compareTo(b.filledAt));

    return VehicleStats(
      vehicleId: vehicleId,
      points: points,
      issues: issues,
      monthlySpend: _monthlySpend(byDate),
      entryCount: sorted.length,
      totalFuelLitres: totalFuel,
      totalSpent: totalSpent,
      measuredDistanceKm: measuredDistance,
      measuredFuelLitres: measuredFuel,
      measuredCost: measuredCost,
      firstOdometerKm: sorted.first.odometer,
      lastOdometerKm: sorted.last.odometer,
      firstDate: byDate.first.filledAt,
      lastDate: byDate.last.filledAt,
      lastPricePerLitre: byDate.last.pricePerLitre,
    );
  }

  // -------------------------------------------------------------------------
  // The window walk
  // -------------------------------------------------------------------------

  static List<EconomyPoint> _buildPoints(
    List<FuelEntry> sorted,
    List<EntryIssue> issues,
  ) {
    final points = <EconomyPoint>[];

    // The last full-tank entry, which opens the window in progress. Null means
    // no usable reference level yet: either we are before the first full tank,
    // or a missed fill has just broken the chain.
    FuelEntry? anchor;

    // Fuel and money accumulated since [anchor], including partial fills.
    var pendingFuel = 0.0;
    var pendingCost = 0.0;
    var pendingFills = 0;

    void reset(FuelEntry? newAnchor) {
      anchor = newAnchor;
      pendingFuel = 0;
      pendingCost = 0;
      pendingFills = 0;
    }

    for (final entry in sorted) {
      // A missed fill means fuel went in that was never logged, so any window
      // spanning it would understate consumption and overstate the average.
      // Throw the window away and start again from here.
      if (entry.missedFillUp) {
        if (anchor != null) {
          issues.add(EntryIssue(
            entryId: entry.id,
            severity: IssueSeverity.info,
            message: 'Marked as a missed fill-up, so no average is calculated '
                'for the stretch leading up to it.',
          ));
        }
        reset(entry.isFullTank ? entry : null);
        continue;
      }

      if (anchor == null) {
        // Nothing to measure from yet. Only a full tank can start the chain.
        if (entry.isFullTank) reset(entry);
        continue;
      }

      pendingFuel += entry.volume;
      pendingCost += entry.totalCost;
      pendingFills += 1;

      // A partial fill cannot close a window — the tank is at an unknown
      // level. Its litres stay pending and roll into the next full tank.
      if (!entry.isFullTank) continue;

      final distance = entry.odometer - anchor!.odometer;

      if (distance < kMinWindowDistanceKm) {
        issues.add(EntryIssue(
          entryId: entry.id,
          severity: IssueSeverity.warning,
          message: 'Odometer has barely moved since the last full tank '
              '(${distance.toStringAsFixed(1)} km), so no average could be '
              'calculated. Check the odometer reading.',
        ));
        reset(entry);
        continue;
      }

      if (pendingFuel <= 0) {
        reset(entry);
        continue;
      }

      points.add(EconomyPoint(
        entry: entry,
        openingEntryId: anchor!.id,
        distanceKm: distance,
        fuelLitres: pendingFuel,
        cost: pendingCost,
        fillCount: pendingFills,
        days: entry.filledAt.difference(anchor!.filledAt).inDays.abs(),
      ));

      reset(entry);
    }

    return points;
  }

  // -------------------------------------------------------------------------
  // Quality checks
  // -------------------------------------------------------------------------

  /// Flags windows whose average sits far from the median. The median, not the
  /// mean, so that one bad point cannot hide itself by dragging the reference.
  static List<EconomyPoint> _flagOutliers(List<EconomyPoint> points) {
    if (points.length < 3) return points; // too few to have a "normal"

    final values = points.map((p) => p.kmPerLitre).toList()..sort();
    final median = _median(values);
    if (median <= 0) return points;

    return points.map((point) {
      final deviation = (point.kmPerLitre - median).abs() / median;
      return deviation > kOutlierThreshold
          ? point.copyWith(isOutlier: true)
          : point;
    }).toList(growable: false);
  }

  static double _median(List<double> sortedValues) {
    if (sortedValues.isEmpty) return 0;
    final middle = sortedValues.length ~/ 2;
    if (sortedValues.length.isOdd) return sortedValues[middle];
    return (sortedValues[middle - 1] + sortedValues[middle]) / 2;
  }

  /// The odometer only ever goes up. Anything else is a typo or a replaced
  /// cluster, and either way the distances downstream are wrong.
  static void _checkOdometerMonotonic(
    List<FuelEntry> sorted,
    List<EntryIssue> issues,
  ) {
    for (var i = 1; i < sorted.length; i++) {
      final previous = sorted[i - 1];
      final current = sorted[i];

      if (current.odometer == previous.odometer) {
        issues.add(EntryIssue(
          entryId: current.id,
          severity: IssueSeverity.warning,
          message: 'Two entries share the odometer reading '
              '${current.odometer.toStringAsFixed(0)} km.',
        ));
        continue;
      }

      // Sorting is by odometer, so a later entry cannot read lower. What can
      // happen is that the dates run backwards against the readings.
      if (current.filledAt.isBefore(previous.filledAt)) {
        issues.add(EntryIssue(
          entryId: current.id,
          severity: IssueSeverity.warning,
          message: 'This entry has a higher odometer reading but an earlier '
              'date than the one before it. Check the date.',
        ));
      }
    }
  }

  /// When the driver resets the trip meter at every fill, the trip reading and
  /// the odometer delta should agree. When they do not, one of the two was
  /// mistyped — and the odometer one silently corrupts the average.
  static void _checkTripMeters(
    List<EconomyPoint> points,
    List<EntryIssue> issues,
  ) {
    for (final point in points) {
      final trip = point.entry.tripMeter;
      if (trip == null || trip <= 0) continue;
      if (point.fillCount != 1) continue; // trip spans more than this window

      final difference = (trip - point.distanceKm).abs();
      if (difference / point.distanceKm > kTripMismatchThreshold) {
        issues.add(EntryIssue(
          entryId: point.entry.id,
          severity: IssueSeverity.info,
          message: 'Trip meter says ${trip.toStringAsFixed(0)} km but the '
              'odometer moved ${point.distanceKm.toStringAsFixed(0)} km since '
              'the last full tank.',
        ));
      }
    }
  }

  // -------------------------------------------------------------------------
  // Aggregation
  // -------------------------------------------------------------------------

  static List<MonthlySpend> _monthlySpend(List<FuelEntry> byDate) {
    if (byDate.isEmpty) return const [];

    final buckets = <DateTime, List<FuelEntry>>{};
    for (final entry in byDate) {
      final key = DateTime(entry.filledAt.year, entry.filledAt.month);
      buckets.putIfAbsent(key, () => <FuelEntry>[]).add(entry);
    }

    final months = buckets.keys.toList()..sort();
    return months.map((month) {
      final entries = buckets[month]!;
      return MonthlySpend(
        month: month,
        cost: entries.fold<double>(0, (a, e) => a + e.totalCost),
        litres: entries.fold<double>(0, (a, e) => a + e.volume),
        fills: entries.length,
      );
    }).toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // Entry-time helpers
  // -------------------------------------------------------------------------

  /// The entry immediately before [odometer], used by the entry form to
  /// validate a new reading and to prefill the trip meter.
  static FuelEntry? previousEntry(List<FuelEntry> entries, double odometer,
      {int? excludingId}) {
    FuelEntry? best;
    for (final entry in entries) {
      if (excludingId != null && entry.id == excludingId) continue;
      if (entry.odometer >= odometer) continue;
      if (best == null || entry.odometer > best.odometer) best = entry;
    }
    return best;
  }

  /// The highest odometer reading on record, for the "must be greater than"
  /// hint on the entry form.
  static double? lastOdometer(List<FuelEntry> entries, {int? excludingId}) {
    double? highest;
    for (final entry in entries) {
      if (excludingId != null && entry.id == excludingId) continue;
      if (highest == null || entry.odometer > highest) highest = entry.odometer;
    }
    return highest;
  }

  /// One-off average for the Quick Calculator (I15): the original
  /// `distance / fuel`, kept intact and given an honest name.
  ///
  /// Returns null rather than infinity when [litres] is zero.
  static double? simpleAverage(double km, double litres) {
    if (litres <= 0 || km < 0) return null;
    return km / litres;
  }

  /// Litres needed to cover [km] at [kmPerLitre].
  static double? fuelNeeded(double km, double kmPerLitre) {
    if (kmPerLitre <= 0 || km < 0) return null;
    return km / kmPerLitre;
  }

  /// How far [litres] should go at [kmPerLitre].
  static double? rangeFor(double litres, double kmPerLitre) {
    if (kmPerLitre <= 0 || litres < 0) return null;
    return litres * kmPerLitre;
  }

  /// Rolling average of the last [window] points, for a smoothed chart line.
  static List<double> rollingAverage(List<EconomyPoint> points, int window) {
    if (points.isEmpty || window < 1) return const [];
    final result = <double>[];
    for (var i = 0; i < points.length; i++) {
      final start = math.max(0, i - window + 1);
      var sum = 0.0;
      for (var j = start; j <= i; j++) {
        sum += points[j].kmPerLitre;
      }
      result.add(sum / (i - start + 1));
    }
    return result;
  }
}
