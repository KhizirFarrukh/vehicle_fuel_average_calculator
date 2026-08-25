/// Where the fuel was bought, and what it cost there (I22).
///
/// **Pure Dart. Do not import Flutter here** — same rule as the other two
/// engines.
///
/// ## A warning about comparing stations
///
/// Fuel prices move. A station visited mostly in 2024 will look cheaper than
/// one visited mostly in 2026 no matter how it actually prices, so an all-time
/// average price per station compares the calendar as much as the forecourt.
///
/// [StationAnalyzer.cheapest] therefore takes a time window and applies a
/// minimum number of visits, and the UI states the window it used. It is still
/// a rough guide, not a verdict.
library;

import '../models/fuel_entry.dart';

/// What one station is worth remembering for.
class StationStats {
  const StationStats({
    required this.name,
    required this.fills,
    required this.totalVolume,
    required this.totalCost,
    required this.firstVisit,
    required this.lastVisit,
    required this.lastPricePerLitre,
  });

  /// The spelling the user typed most often.
  final String name;

  final int fills;
  final double totalVolume;
  final double totalCost;
  final DateTime firstVisit;
  final DateTime lastVisit;
  final double? lastPricePerLitre;

  double? get averagePricePerLitre =>
      totalVolume > 0 ? totalCost / totalVolume : null;
}

class StationAnalyzer {
  const StationAnalyzer._();

  /// How far back [cheapest] looks by default. Long enough to gather visits,
  /// short enough that pump prices are roughly comparable.
  static const int defaultWindowDays = 180;

  /// Below this, an average price is one lucky day rather than a pattern.
  static const int minimumFillsToCompare = 2;

  /// Case- and spacing-insensitive key, so `Shell` and `  shell ` are one
  /// station.
  static String normalise(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Every station in the log, most-visited first.
  static List<StationStats> analyze(List<FuelEntry> entries) {
    final buckets = <String, List<FuelEntry>>{};

    for (final entry in entries) {
      final raw = entry.station?.trim();
      if (raw == null || raw.isEmpty) continue;
      buckets.putIfAbsent(normalise(raw), () => <FuelEntry>[]).add(entry);
    }

    final result = <StationStats>[];
    for (final group in buckets.values) {
      final sorted = List<FuelEntry>.of(group)
        ..sort((a, b) => a.filledAt.compareTo(b.filledAt));

      result.add(StationStats(
        name: _preferredSpelling(sorted),
        fills: sorted.length,
        totalVolume: sorted.fold<double>(0, (sum, e) => sum + e.volume),
        totalCost: sorted.fold<double>(0, (sum, e) => sum + e.totalCost),
        firstVisit: sorted.first.filledAt,
        lastVisit: sorted.last.filledAt,
        lastPricePerLitre: sorted.last.pricePerLitre,
      ));
    }

    result.sort((a, b) {
      final byFills = b.fills.compareTo(a.fills);
      if (byFills != 0) return byFills;
      return b.lastVisit.compareTo(a.lastVisit);
    });
    return result;
  }

  /// Stations ranked by average price paid, cheapest first.
  ///
  /// Only counts fills within [windowDays] of [now], and only stations with at
  /// least [minimumFills] of them. Returns an empty list when that leaves
  /// fewer than two stations to compare — a ranking of one is not a ranking.
  static List<StationStats> cheapest(
    List<FuelEntry> entries, {
    int windowDays = defaultWindowDays,
    int minimumFills = minimumFillsToCompare,
    DateTime? now,
  }) {
    final cutoff =
        (now ?? DateTime.now()).subtract(Duration(days: windowDays));

    final recent = entries
        .where((e) => e.filledAt.isAfter(cutoff))
        .toList(growable: false);

    final ranked = analyze(recent)
        .where((s) => s.fills >= minimumFills)
        .where((s) => s.averagePricePerLitre != null)
        .toList();

    if (ranked.length < 2) return const [];

    ranked.sort(
      (a, b) => a.averagePricePerLitre!.compareTo(b.averagePricePerLitre!),
    );
    return ranked;
  }

  /// Station names for the entry form's autocomplete, most recently used
  /// first — the next fill is usually at the last place, or the one before it.
  static List<String> knownNames(List<FuelEntry> entries) {
    final lastSeen = <String, DateTime>{};
    final spelling = <String, String>{};

    for (final entry in entries) {
      final raw = entry.station?.trim();
      if (raw == null || raw.isEmpty) continue;

      final key = normalise(raw);
      final seen = lastSeen[key];
      if (seen == null || entry.filledAt.isAfter(seen)) {
        lastSeen[key] = entry.filledAt;
      }
      spelling.putIfAbsent(key, () => raw);
    }

    final keys = lastSeen.keys.toList()
      ..sort((a, b) => lastSeen[b]!.compareTo(lastSeen[a]!));

    return [for (final key in keys) spelling[key] ?? key];
  }

  /// How much the fills at [name] cost against every other station over the
  /// same window, as a percentage. Negative means cheaper.
  ///
  /// Null when there is nothing to compare against.
  static double? relativePrice(
    List<FuelEntry> entries,
    String name, {
    int windowDays = defaultWindowDays,
    DateTime? now,
  }) {
    final cutoff =
        (now ?? DateTime.now()).subtract(Duration(days: windowDays));
    final key = normalise(name);

    var mineVolume = 0.0;
    var mineCost = 0.0;
    var othersVolume = 0.0;
    var othersCost = 0.0;

    for (final entry in entries) {
      if (!entry.filledAt.isAfter(cutoff)) continue;
      final raw = entry.station?.trim();
      if (raw == null || raw.isEmpty) continue;

      if (normalise(raw) == key) {
        mineVolume += entry.volume;
        mineCost += entry.totalCost;
      } else {
        othersVolume += entry.volume;
        othersCost += entry.totalCost;
      }
    }

    if (mineVolume <= 0 || othersVolume <= 0) return null;

    final mine = mineCost / mineVolume;
    final others = othersCost / othersVolume;
    if (others <= 0) return null;

    return ((mine - others) / others) * 100;
  }

  /// The spelling used most often; ties go to the most recent.
  static String _preferredSpelling(List<FuelEntry> sortedByDate) {
    final counts = <String, int>{};
    for (final entry in sortedByDate) {
      final raw = entry.station?.trim();
      if (raw == null || raw.isEmpty) continue;
      counts[raw] = (counts[raw] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';

    // `>=` so a tie goes to the later spelling: keys are in first-seen order,
    // and someone who has recently changed how they type it means the new one.
    var best = counts.keys.first;
    for (final candidate in counts.keys) {
      if (counts[candidate]! >= counts[best]!) best = candidate;
    }
    return best;
  }
}
