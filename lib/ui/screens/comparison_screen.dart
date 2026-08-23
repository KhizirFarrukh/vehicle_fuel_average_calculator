import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../models/fuel_stats.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';
import '../widgets/stat_tile.dart';
import 'vehicle_detail_screen.dart';

/// What the vehicles are being ranked by (I20).
enum ComparisonMetric {
  economy('Fuel economy', _Direction.higherIsBetter),
  costPerDistance('Running cost', _Direction.lowerIsBetter),
  fuelPrice('Fuel price paid', _Direction.lowerIsBetter),
  totalSpent('Total spent', _Direction.neutral),
  distance('Distance tracked', _Direction.neutral),
  fills('Fill-ups logged', _Direction.neutral);

  const ComparisonMetric(this.label, this.direction);

  final String label;
  final _Direction direction;
}

enum _Direction { higherIsBetter, lowerIsBetter, neutral }

/// Ranks every vehicle in the garage side by side on one measure.
///
/// Bars are drawn from the **canonical** value, so "longer" always means the
/// same thing no matter which display unit is selected. Without that, someone
/// reading L/100 km would see the longest bar on their thirstiest car while
/// the header claimed longer was better.
class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  ComparisonMetric _metric = ComparisonMetric.economy;
  bool _includeArchived = false;

  @override
  Widget build(BuildContext context) {
    final garage = context.watch<GarageController>();
    final units = context.watch<SettingsController>().formatter;

    final vehicles = _includeArchived
        ? garage.allVehicles
        : garage.activeVehicles;

    if (vehicles.length < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compare')),
        body: const EmptyState(
          icon: Icons.compare_arrows,
          title: 'Nothing to compare yet',
          message: 'Add a second vehicle and this screen will rank them side '
              'by side on economy, running cost and spend.',
        ),
      );
    }

    final rows = _buildRows(garage, vehicles, units);
    final ranked = rows.where((r) => r.value != null).toList();
    final unranked = rows.where((r) => r.value == null).toList();
    final maxValue = ranked.isEmpty
        ? 0.0
        : ranked.map((r) => r.value!).reduce(math.max);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare'),
        actions: [
          if (garage.archivedCount > 0)
            IconButton(
              tooltip: _includeArchived
                  ? 'Hide archived vehicles'
                  : 'Include archived vehicles',
              icon: Icon(
                _includeArchived
                    ? Icons.inventory_2
                    : Icons.inventory_2_outlined,
              ),
              onPressed: () =>
                  setState(() => _includeArchived = !_includeArchived),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _MetricPicker(
            metric: _metric,
            onChanged: (value) => setState(() => _metric = value),
          ),
          const SizedBox(height: 8),
          Text(
            _captionFor(_metric),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (ranked.isEmpty)
            AppCard(
              child: Text(
                'None of these vehicles has enough logged data for this '
                'measure yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            for (var i = 0; i < ranked.length; i++) ...[
              _ComparisonRow(
                row: ranked[i],
                rank: i + 1,
                fraction: maxValue > 0 ? ranked[i].value! / maxValue : 0,
                isBest: i == 0 && _metric.direction != _Direction.neutral,
                onTap: () => _open(context, ranked[i].vehicle),
              ),
              const SizedBox(height: 10),
            ],
          if (unranked.isNotEmpty) ...[
            const SectionHeader(
              'Not enough data',
              padding: EdgeInsets.fromLTRB(4, 16, 4, 12),
            ),
            for (final row in unranked) ...[
              _ComparisonRow(
                row: row,
                rank: null,
                fraction: 0,
                isBest: false,
                onTap: () => _open(context, row.vehicle),
              ),
              const SizedBox(height: 10),
            ],
          ],
          const SectionHeader('Across the whole garage'),
          _FleetSummary(rows: rows, units: units),
        ],
      ),
    );
  }

  void _open(BuildContext context, Vehicle vehicle) {
    final id = vehicle.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleDetailScreen(vehicleId: id),
      ),
    );
  }

  String _captionFor(ComparisonMetric metric) {
    switch (metric.direction) {
      case _Direction.higherIsBetter:
        return 'Ranked best first. A longer bar is a more efficient vehicle.';
      case _Direction.lowerIsBetter:
        return 'Ranked best first. A shorter bar is the cheaper vehicle.';
      case _Direction.neutral:
        return 'Ranked highest first. A longer bar is simply a larger figure.';
    }
  }

  List<_Row> _buildRows(
    GarageController garage,
    List<Vehicle> vehicles,
    UnitFormatter units,
  ) {
    final rows = <_Row>[];

    for (final vehicle in vehicles) {
      final stats = garage.statsFor(vehicle.id);

      // Switch *expressions* rather than a switch statement assigning `final`
      // locals: the latter leans on exhaustiveness analysis for definite
      // assignment, and this form needs no such argument.
      final value = switch (_metric) {
        ComparisonMetric.economy => stats.lifetimeKmPerLitre,
        ComparisonMetric.costPerDistance => stats.costPerKm,
        ComparisonMetric.fuelPrice => stats.averagePricePerLitre,
        ComparisonMetric.totalSpent =>
          stats.totalSpent > 0 ? stats.totalSpent : null,
        ComparisonMetric.distance => stats.trackedDistanceKm,
        ComparisonMetric.fills =>
          stats.entryCount > 0 ? stats.entryCount.toDouble() : null,
      };

      final display = switch (_metric) {
        ComparisonMetric.economy => units.economy(value),
        ComparisonMetric.costPerDistance => units.costPerDistance(value),
        ComparisonMetric.fuelPrice => units.pricePerVolume(value),
        ComparisonMetric.totalSpent => units.money(value),
        ComparisonMetric.distance => units.distance(value),
        ComparisonMetric.fills => stats.entryCount.toString(),
      };

      rows.add(_Row(
        vehicle: vehicle,
        stats: stats,
        value: value,
        display: display,
      ));
    }

    rows.sort((a, b) {
      if (a.value == null && b.value == null) return 0;
      if (a.value == null) return 1;
      if (b.value == null) return -1;
      return _metric.direction == _Direction.lowerIsBetter
          ? a.value!.compareTo(b.value!)
          : b.value!.compareTo(a.value!);
    });

    return rows;
  }
}

class _Row {
  const _Row({
    required this.vehicle,
    required this.stats,
    required this.value,
    required this.display,
  });

  final Vehicle vehicle;
  final VehicleStats stats;

  /// Canonical value used for ranking and bar length. Null when this vehicle
  /// has no figure for the selected metric.
  final double? value;

  /// The same value formatted in the reader's units.
  final String display;
}

class _MetricPicker extends StatelessWidget {
  const _MetricPicker({required this.metric, required this.onChanged});

  final ComparisonMetric metric;
  final ValueChanged<ComparisonMetric> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in ComparisonMetric.values)
          ChoiceChip(
            label: Text(option.label),
            selected: option == metric,
            onSelected: (selected) {
              if (selected) onChanged(option);
            },
          ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.row,
    required this.rank,
    required this.fraction,
    required this.isBest,
    required this.onTap,
  });

  final _Row row;
  final int? rank;
  final double fraction;
  final bool isBest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColour = isBest ? AppTheme.good(context) : theme.colorScheme.primary;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (rank != null) ...[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    rank.toString(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  row.vehicle.displayName,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                row.display,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isBest ? AppTheme.good(context) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColour),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            row.stats.hasEntries
                ? '${row.stats.entryCount} fill-ups · last '
                    '${formatRelativeDate(row.stats.lastDate)}'
                : 'Nothing logged yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FleetSummary extends StatelessWidget {
  const _FleetSummary({required this.rows, required this.units});

  final List<_Row> rows;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    var spent = 0.0;
    var litres = 0.0;
    var fills = 0;
    var measuredDistance = 0.0;
    var measuredFuel = 0.0;

    for (final row in rows) {
      spent += row.stats.totalSpent;
      litres += row.stats.totalFuelLitres;
      fills += row.stats.entryCount;
      measuredDistance += row.stats.measuredDistanceKm;
      measuredFuel += row.stats.measuredFuelLitres;
    }

    // Weighted across the whole garage, for the same reason the per-vehicle
    // figure is weighted: averaging the vehicles' averages would give a
    // motorcycle the same say as a van.
    final fleetEconomy = measuredFuel > 0 ? measuredDistance / measuredFuel : null;

    return StatGrid(
      children: [
        StatTile(
          label: 'Total spent',
          value: units.money(spent),
          icon: Icons.payments_outlined,
        ),
        StatTile(
          label: 'Total fuel',
          value: units.volume(litres),
          icon: Icons.water_drop_outlined,
        ),
        StatTile(
          label: 'Fill-ups',
          value: fills.toString(),
          icon: Icons.numbers,
        ),
        StatTile(
          label: 'Combined economy',
          value: units.economy(fleetEconomy),
          caption: 'Weighted by distance',
          icon: Icons.speed,
        ),
      ],
    );
  }
}
