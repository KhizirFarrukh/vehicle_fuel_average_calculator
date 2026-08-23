/// Value objects produced by the economy engine. Pure Dart — no Flutter.
library;

import 'fuel_entry.dart';

enum IssueSeverity { info, warning, error }

/// Something worth telling the user about a specific entry, found while
/// analysing the log rather than while typing it in.
class EntryIssue {
  const EntryIssue({
    required this.entryId,
    required this.severity,
    required this.message,
  });

  final int? entryId;
  final IssueSeverity severity;
  final String message;

  @override
  String toString() => '[${severity.name}] $message';
}

/// One computed fuel average: the stretch between two consecutive full-tank
/// fills. See docs/PLAN.md §6 for why this, and not `distance / fuel`, is the
/// right unit of measurement.
class EconomyPoint {
  const EconomyPoint({
    required this.entry,
    required this.openingEntryId,
    required this.distanceKm,
    required this.fuelLitres,
    required this.cost,
    required this.fillCount,
    required this.days,
    this.isOutlier = false,
  });

  /// The full-tank entry that *closes* this window. Its date and odometer are
  /// the ones the user sees against this average.
  final FuelEntry entry;

  /// Id of the full-tank entry that opened the window.
  final int? openingEntryId;

  /// Kilometres covered between the two full tanks.
  final double distanceKm;

  /// Litres burned over that distance — the closing fill plus any partial
  /// fills in between.
  final double fuelLitres;

  /// Money spent on those litres.
  final double cost;

  /// How many refuels made up this window (1 = a clean tank-to-tank stretch).
  final int fillCount;

  /// Days between the two fills.
  final int days;

  /// Set by the engine when this point sits far from the median (I10) —
  /// usually a mis-keyed odometer or litre figure.
  final bool isOutlier;

  DateTime get date => entry.filledAt;

  double get kmPerLitre => fuelLitres > 0 ? distanceKm / fuelLitres : 0;

  double get litresPer100Km => distanceKm > 0 ? (fuelLitres / distanceKm) * 100 : 0;

  double get costPerKm => distanceKm > 0 ? cost / distanceKm : 0;

  double? get kmPerDay => days > 0 ? distanceKm / days : null;

  EconomyPoint copyWith({bool? isOutlier}) => EconomyPoint(
        entry: entry,
        openingEntryId: openingEntryId,
        distanceKm: distanceKm,
        fuelLitres: fuelLitres,
        cost: cost,
        fillCount: fillCount,
        days: days,
        isOutlier: isOutlier ?? this.isOutlier,
      );

  @override
  String toString() =>
      'EconomyPoint(${distanceKm.toStringAsFixed(1)}km / '
      '${fuelLitres.toStringAsFixed(2)}L = '
      '${kmPerLitre.toStringAsFixed(2)}km/L)';
}

/// Fuel spend bucketed by calendar month, for the spend chart.
class MonthlySpend {
  const MonthlySpend({
    required this.month,
    required this.cost,
    required this.litres,
    required this.fills,
  });

  /// First day of the month, at midnight.
  final DateTime month;
  final double cost;
  final double litres;
  final int fills;
}

/// Everything the UI needs to know about one vehicle's fuel history.
///
/// Fields prefixed `measured` cover only the stretches where economy could
/// actually be computed; fields prefixed `total` cover every logged entry.
/// The two differ, and conflating them is how fuel trackers end up lying.
class VehicleStats {
  const VehicleStats({
    required this.vehicleId,
    required this.points,
    required this.issues,
    required this.monthlySpend,
    required this.entryCount,
    required this.totalFuelLitres,
    required this.totalSpent,
    required this.measuredDistanceKm,
    required this.measuredFuelLitres,
    required this.measuredCost,
    this.firstOdometerKm,
    this.lastOdometerKm,
    this.firstDate,
    this.lastDate,
    this.lastPricePerLitre,
  });

  /// An empty result, for a vehicle with no entries yet.
  factory VehicleStats.empty(int vehicleId) => VehicleStats(
        vehicleId: vehicleId,
        points: const [],
        issues: const [],
        monthlySpend: const [],
        entryCount: 0,
        totalFuelLitres: 0,
        totalSpent: 0,
        measuredDistanceKm: 0,
        measuredFuelLitres: 0,
        measuredCost: 0,
      );

  final int vehicleId;

  /// Chronological (odometer ascending).
  final List<EconomyPoint> points;
  final List<EntryIssue> issues;
  final List<MonthlySpend> monthlySpend;

  final int entryCount;
  final double totalFuelLitres;
  final double totalSpent;

  final double measuredDistanceKm;
  final double measuredFuelLitres;
  final double measuredCost;

  final double? firstOdometerKm;
  final double? lastOdometerKm;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final double? lastPricePerLitre;

  bool get hasEntries => entryCount > 0;

  /// True once at least one complete full-tank-to-full-tank window exists.
  bool get hasEconomy => points.isNotEmpty;

  /// Distance-weighted lifetime average — the honest one. Averaging the
  /// per-window figures instead would over-weight short tanks (I4).
  double? get lifetimeKmPerLitre =>
      measuredFuelLitres > 0 ? measuredDistanceKm / measuredFuelLitres : null;

  /// The unweighted mean of the window averages. Exposed only so the UI can
  /// show it as a secondary figure; never use it as *the* average.
  double? get meanOfWindowsKmPerLitre {
    if (points.isEmpty) return null;
    final sum = points.fold<double>(0, (a, p) => a + p.kmPerLitre);
    return sum / points.length;
  }

  EconomyPoint? get latest => points.isEmpty ? null : points.last;

  EconomyPoint? get best {
    if (points.isEmpty) return null;
    return points.reduce((a, b) => b.kmPerLitre > a.kmPerLitre ? b : a);
  }

  EconomyPoint? get worst {
    if (points.isEmpty) return null;
    return points.reduce((a, b) => b.kmPerLitre < a.kmPerLitre ? b : a);
  }

  /// Across every logged litre, not just measured windows.
  double? get averagePricePerLitre =>
      totalFuelLitres > 0 ? totalSpent / totalFuelLitres : null;

  /// Fuel cost per kilometre over the measured stretches.
  double? get costPerKm =>
      measuredDistanceKm > 0 ? measuredCost / measuredDistanceKm : null;

  /// Odometer span from first to last entry — includes stretches where
  /// economy could not be computed.
  double? get trackedDistanceKm {
    final first = firstOdometerKm;
    final last = lastOdometerKm;
    if (first == null || last == null) return null;
    final span = last - first;
    return span > 0 ? span : null;
  }

  int? get trackedDays {
    final first = firstDate;
    final last = lastDate;
    if (first == null || last == null) return null;
    final days = last.difference(first).inDays;
    return days > 0 ? days : null;
  }

  double? get averageDaysBetweenFills {
    final days = trackedDays;
    if (days == null || entryCount < 2) return null;
    return days / (entryCount - 1);
  }

  double? get kmPerDay {
    final distance = trackedDistanceKm;
    final days = trackedDays;
    if (distance == null || days == null) return null;
    return distance / days;
  }

  /// How far a full tank should go at the lifetime average.
  double? estimatedRangeKm(double? tankCapacityLitres) {
    final economy = lifetimeKmPerLitre;
    if (economy == null || tankCapacityLitres == null || tankCapacityLitres <= 0) {
      return null;
    }
    return economy * tankCapacityLitres;
  }

  /// Latest window against the mean of everything before it, as a percentage.
  /// Positive means the car is doing better than usual. Null with fewer than
  /// two points, where a trend would be meaningless.
  double? get trendPercent {
    if (points.length < 2) return null;
    final previous = points.sublist(0, points.length - 1);
    final baseline =
        previous.fold<double>(0, (a, p) => a + p.kmPerLitre) / previous.length;
    if (baseline <= 0) return null;
    return ((points.last.kmPerLitre - baseline) / baseline) * 100;
  }

  List<EntryIssue> issuesFor(int? entryId) {
    if (entryId == null) return const [];
    return issues.where((i) => i.entryId == entryId).toList(growable: false);
  }
}
