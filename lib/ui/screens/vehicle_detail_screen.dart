import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../data/backup_service.dart';
import '../../domain/fuel_calculator.dart';
import '../../domain/service_planner.dart';
import '../../models/fuel_entry.dart';
import '../../models/fuel_stats.dart';
import '../../models/service_record.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';
import '../widgets/charts.dart';
import '../widgets/entry_tile.dart';
import '../widgets/service_tile.dart';
import '../widgets/stat_tile.dart';
import 'csv_import_screen.dart';
import 'entry_form_screen.dart';
import 'service_form_screen.dart';
import 'vehicle_form_screen.dart';

/// One vehicle: its numbers, its refuelling history, and its charts.
class VehicleDetailScreen extends StatelessWidget {
  const VehicleDetailScreen({super.key, required this.vehicleId});

  final int vehicleId;

  @override
  Widget build(BuildContext context) {
    final garage = context.watch<GarageController>();
    final units = context.watch<SettingsController>().formatter;
    final vehicle = garage.vehicleById(vehicleId);

    // The vehicle can vanish underneath us if it was deleted from the form.
    if (vehicle == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.directions_car_outlined,
          title: 'Vehicle not found',
          message: 'It may have been deleted.',
        ),
      );
    }

    final stats = garage.statsFor(vehicleId);
    final entries = garage.entriesNewestFirst(vehicleId);

    // Every economy point is attributed to the entry that closed it.
    final pointsByEntryId = <int, EconomyPoint>{
      for (final point in stats.points)
        if (point.entry.id != null) point.entry.id!: point,
    };

    final services = garage.servicesFor(vehicleId);
    final reminders = garage.remindersFor(vehicleId);
    final serviceCost = garage.serviceCostFor(vehicleId);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            vehicle.displayName,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Edit vehicle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VehicleFormScreen(existing: vehicle),
                ),
              ),
            ),
            _DataMenu(vehicle: vehicle),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'History'),
              Tab(text: 'Charts'),
              Tab(text: 'Service'),
            ],
          ),
        ),
        floatingActionButton: _Fab(vehicle: vehicle),
        body: TabBarView(
          children: [
            _OverviewTab(
              vehicle: vehicle,
              stats: stats,
              units: units,
              alerts: garage.serviceAlertsFor(vehicleId),
              serviceCost: serviceCost,
            ),
            _HistoryTab(
              vehicle: vehicle,
              entries: entries,
              stats: stats,
              pointsByEntryId: pointsByEntryId,
              units: units,
            ),
            _ChartsTab(stats: stats, units: units),
            _ServiceTab(
              vehicle: vehicle,
              records: services,
              reminders: reminders,
              totalCost: serviceCost,
              units: units,
            ),
          ],
        ),
      ),
    );
  }
}

/// The action button follows the visible tab: fill-ups on the fuel tabs,
/// maintenance on the service tab.
class _Fab extends StatelessWidget {
  const _Fab({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isService = controller.index == _serviceTabIndex;
        return FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => isService
                  ? ServiceFormScreen(vehicle: vehicle)
                  : EntryFormScreen(vehicle: vehicle),
            ),
          ),
          icon: Icon(isService ? Icons.build : Icons.local_gas_station),
          label: Text(isService ? 'Log service' : 'Log fill-up'),
        );
      },
    );
  }
}

const int _serviceTabIndex = 3;

/// Per-vehicle CSV import and export.
class _DataMenu extends StatelessWidget {
  const _DataMenu({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Import or export',
      onSelected: (value) => _onSelected(context, value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'import', child: Text('Import from CSV')),
        PopupMenuItem(value: 'export', child: Text('Export this log as CSV')),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, String value) async {
    if (value == 'import') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CsvImportScreen(vehicle: vehicle),
        ),
      );
      return;
    }

    final backup = context.read<BackupService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await backup.exportCsvFile(vehicleId: vehicle.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved to $path'),
          action: SnackBarAction(
            label: 'Copy path',
            onPressed: () => Clipboard.setData(ClipboardData(text: path)),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.vehicle,
    required this.stats,
    required this.units,
    required this.alerts,
    required this.serviceCost,
  });

  final Vehicle vehicle;
  final VehicleStats stats;
  final UnitFormatter units;
  final List<ServiceReminder> alerts;
  final double serviceCost;

  @override
  Widget build(BuildContext context) {
    if (!stats.hasEntries) {
      return EmptyState(
        icon: Icons.local_gas_station_outlined,
        title: 'No fill-ups logged',
        message: 'Log a fill-up each time you refuel. After the second full '
            'tank, ${vehicle.make} ${vehicle.model} gets its first real '
            'average.',
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EntryFormScreen(vehicle: vehicle),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Log the first fill-up'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _HeadlineCard(stats: stats, units: units),
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 12),
          ServiceAlertBanner(
            alerts: alerts,
            onTap: () =>
                DefaultTabController.of(context).animateTo(_serviceTabIndex),
          ),
        ],
        const SectionHeader('Running costs'),
        StatGrid(
          children: [
            StatTile(
              label: 'Fuel spent',
              value: units.money(stats.totalSpent),
              icon: Icons.payments_outlined,
            ),
            StatTile(
              label: 'Maintenance',
              value: units.money(serviceCost),
              icon: Icons.build_outlined,
            ),
            StatTile(
              label: 'All-in per ${units.distanceSymbol}',
              value: units.costPerDistance(
                ServicePlanner.runningCostPerKm(
                  fuelCost: stats.totalSpent,
                  serviceCost: serviceCost,
                  distanceKm: stats.trackedDistanceKm ?? 0,
                ),
              ),
              caption: 'Fuel and maintenance',
              icon: Icons.receipt_long_outlined,
            ),
            StatTile(
              label: 'Cost per ${units.distanceSymbol}',
              value: units.costPerDistance(stats.costPerKm),
              caption: stats.costPerKm == null ? 'Needs one full stretch' : null,
              icon: Icons.route_outlined,
            ),
            StatTile(
              label: 'Average fuel price',
              value: units.pricePerVolume(stats.averagePricePerLitre),
              icon: Icons.local_gas_station_outlined,
            ),
            StatTile(
              label: 'Latest fuel price',
              value: units.pricePerVolume(stats.lastPricePerLitre),
              icon: Icons.trending_up,
            ),
          ],
        ),
        const SectionHeader('Usage'),
        StatGrid(
          children: [
            StatTile(
              label: 'Total fuel',
              value: units.volume(stats.totalFuelLitres),
              icon: Icons.water_drop_outlined,
            ),
            StatTile(
              label: 'Distance tracked',
              value: units.distance(stats.trackedDistanceKm),
              caption: 'First to latest fill-up',
              icon: Icons.straighten,
            ),
            StatTile(
              label: 'Fill-ups',
              value: stats.entryCount.toString(),
              caption: stats.averageDaysBetweenFills == null
                  ? null
                  : 'Every ${formatNumber(stats.averageDaysBetweenFills, decimals: 0)} days',
              icon: Icons.numbers,
            ),
            StatTile(
              label: 'Distance per day',
              value: stats.kmPerDay == null
                  ? kEmDash
                  : units.distance(stats.kmPerDay, decimals: 1),
              icon: Icons.calendar_month_outlined,
            ),
          ],
        ),
        if (stats.hasEconomy) ...[
          const SectionHeader('Best and worst stretches'),
          _BestWorstCard(stats: stats, units: units),
        ],
        const SectionHeader('Vehicle'),
        _VehicleDetailsCard(vehicle: vehicle, stats: stats, units: units),
      ],
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.stats, required this.units});

  final VehicleStats stats;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = stats.lifetimeKmPerLitre;
    final trend = stats.trendPercent;
    final latest = stats.latest;

    if (average == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No average yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              stats.entryCount == 1
                  ? 'A fuel average needs two full tanks: one to set the '
                      'starting level, one to measure against it. Log your '
                      'next full fill-up and the first figure appears here.'
                  : 'None of the logged fill-ups form a complete '
                      'full-tank-to-full-tank stretch yet. Mark a fill as '
                      '"filled to full" to close one.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // The trend is computed in km/L, so a rise is always an improvement here
    // regardless of which unit the reader has chosen — an L/100km reader would
    // see the displayed number fall for this same "improving" case.
    final improving = trend != null && trend > 0;
    final trendColour = trend == null
        ? theme.colorScheme.onSurfaceVariant
        : (improving ? AppTheme.good(context) : AppTheme.warn(context));

    return AppCard(
      color: theme.colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lifetime average',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              units.economy(average),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Across ${units.distance(stats.measuredDistanceKm)} on '
            '${units.volume(stats.measuredFuelLitres)}, over '
            '${stats.points.length} measured '
            '${stats.points.length == 1 ? 'stretch' : 'stretches'}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
            ),
          ),
          if (latest != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Latest stretch',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        units.economy(latest.kmPerLitre),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trend != null)
                  Row(
                    children: [
                      Icon(
                        improving ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: trendColour,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${formatNumber(trend.abs(), decimals: 1)}% vs usual',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: trendColour,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BestWorstCard extends StatelessWidget {
  const _BestWorstCard({required this.stats, required this.units});

  final VehicleStats stats;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final best = stats.best;
    final worst = stats.worst;

    return AppCard(
      child: Column(
        children: [
          if (best != null)
            DetailRow(
              label: 'Best · ${formatDate(best.date)}',
              value: units.economy(best.kmPerLitre),
              valueColor: AppTheme.good(context),
            ),
          if (worst != null)
            DetailRow(
              label: 'Worst · ${formatDate(worst.date)}',
              value: units.economy(worst.kmPerLitre),
              valueColor: AppTheme.warn(context),
            ),
          if (stats.meanOfWindowsKmPerLitre != null)
            DetailRow(
              label: 'Mean of stretches',
              value: units.economy(stats.meanOfWindowsKmPerLitre),
            ),
        ],
      ),
    );
  }
}

class _VehicleDetailsCard extends StatelessWidget {
  const _VehicleDetailsCard({
    required this.vehicle,
    required this.stats,
    required this.units,
  });

  final Vehicle vehicle;
  final VehicleStats stats;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    final range = stats.estimatedRangeKm(vehicle.tankCapacity);

    return AppCard(
      child: Column(
        children: [
          DetailRow(label: 'Make', value: vehicle.make),
          DetailRow(label: 'Model', value: vehicle.model),
          DetailRow(label: 'Variant', value: vehicle.variant),
          if (vehicle.year != null)
            DetailRow(label: 'Year', value: vehicle.year.toString()),
          if (vehicle.color != null && vehicle.color!.isNotEmpty)
            DetailRow(label: 'Colour', value: vehicle.color!),
          if (vehicle.licensePlate != null && vehicle.licensePlate!.isNotEmpty)
            DetailRow(label: 'Licence plate', value: vehicle.licensePlate!),
          DetailRow(label: 'Fuel', value: vehicle.fuelType.label),
          if (vehicle.tankCapacity != null)
            DetailRow(
              label: 'Tank capacity',
              value: units.volume(vehicle.tankCapacity),
            ),
          if (range != null)
            DetailRow(
              label: 'Estimated range on a full tank',
              value: units.distance(range),
            ),
          if (stats.lastOdometerKm != null)
            DetailRow(
              label: 'Last odometer',
              value: units.distance(stats.lastOdometerKm),
            ),
          if (vehicle.notes != null && vehicle.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                vehicle.notes!.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.vehicle,
    required this.entries,
    required this.stats,
    required this.pointsByEntryId,
    required this.units,
  });

  final Vehicle vehicle;
  final List<FuelEntry> entries;
  final VehicleStats stats;
  final Map<int, EconomyPoint> pointsByEntryId;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Nothing logged yet',
        message: 'Your refuelling history will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return EntryTile(
          entry: entry,
          point: entry.id == null ? null : pointsByEntryId[entry.id],
          issues: stats.issuesFor(entry.id),
          units: units,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EntryFormScreen(
                vehicle: vehicle,
                existing: entry,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Service (I19)
// ---------------------------------------------------------------------------

class _ServiceTab extends StatelessWidget {
  const _ServiceTab({
    required this.vehicle,
    required this.records,
    required this.reminders,
    required this.totalCost,
    required this.units,
  });

  final Vehicle vehicle;
  final List<ServiceRecord> records;
  final List<ServiceReminder> reminders;
  final double totalCost;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return EmptyState(
        icon: Icons.build_outlined,
        title: 'No service history',
        message: 'Log an oil change, a set of tyres or an insurance renewal, '
            'and this app will tell you when the next one is due — by '
            'distance, by date, or both.',
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ServiceFormScreen(vehicle: vehicle),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Log the first service'),
        ),
      );
    }

    void edit(ServiceRecord record) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ServiceFormScreen(vehicle: vehicle, existing: record),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        StatGrid(
          children: [
            StatTile(
              label: 'Spent on maintenance',
              value: units.money(totalCost),
              icon: Icons.payments_outlined,
            ),
            StatTile(
              label: 'Records',
              value: records.length.toString(),
              caption: reminders.isEmpty
                  ? 'None being tracked'
                  : '${reminders.length} tracked',
              icon: Icons.build_outlined,
            ),
          ],
        ),
        if (reminders.isNotEmpty) ...[
          const SectionHeader(
            'Coming up',
            subtitle: 'Whichever limit is reached first.',
          ),
          for (final reminder in reminders) ...[
            ReminderTile(
              reminder: reminder,
              units: units,
              onTap: () => edit(reminder.record),
            ),
            const SizedBox(height: 10),
          ],
        ],
        const SectionHeader('History'),
        for (final record in records) ...[
          ServiceRecordTile(
            record: record,
            units: units,
            onTap: () => edit(record),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Charts
// ---------------------------------------------------------------------------

class _ChartsTab extends StatelessWidget {
  const _ChartsTab({required this.stats, required this.units});

  final VehicleStats stats;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    if (!stats.hasEntries) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: 'No data to chart',
        message: 'Charts appear once you have logged a few fill-ups.',
      );
    }

    final economyPoints = [
      for (final point in stats.points)
        ChartPoint(
          value: units.economyValue(point.kmPerLitre),
          label: formatMonthShort(point.date),
          caption: '${units.distance(point.distanceKm)} on '
              '${units.volume(point.fuelLitres)} · '
              '${units.costPerDistance(point.costPerKm)}',
          highlight: point.isOutlier,
        ),
    ];

    final rolling = FuelCalculator.rollingAverage(stats.points, 3)
        .map(units.economyValue)
        .toList();

    final priceEntries = stats.monthlySpend;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        const SectionHeader(
          'Fuel economy over time',
          subtitle: 'One point per full-tank-to-full-tank stretch.',
          padding: EdgeInsets.fromLTRB(4, 16, 4, 12),
        ),
        AppCard(
          child: SimpleLineChart(
            points: economyPoints,
            overlay: rolling.length == economyPoints.length ? rolling : null,
            overlayLabel: '3-point average',
            formatValue: (value) => formatNumber(value, decimals: 1),
            emptyMessage: 'Two full tanks are needed before there is a line '
                'to draw.',
          ),
        ),
        const SectionHeader('Monthly fuel spend'),
        AppCard(
          child: SimpleBarChart(
            points: [
              for (final month in priceEntries)
                ChartPoint(
                  value: month.cost,
                  label: formatMonthShort(month.month),
                ),
            ],
            formatValue: (value) =>
                units.money(value, decimals: value >= 100 ? 0 : 1),
          ),
        ),
        const SectionHeader(
          'Fuel price paid',
          subtitle: 'Average price per unit each month.',
        ),
        AppCard(
          child: SimpleLineChart(
            points: [
              for (final month in priceEntries)
                if (month.litres > 0)
                  ChartPoint(
                    value: units.priceValue(month.cost / month.litres),
                    label: formatMonthShort(month.month),
                    caption: '${month.fills} '
                        '${month.fills == 1 ? 'fill' : 'fills'} · '
                        '${units.volume(month.litres)}',
                  ),
            ],
            formatValue: (value) => units.money(value),
            emptyMessage: 'Log fill-ups in two different months to see a '
                'price trend.',
          ),
        ),
      ],
    );
  }
}
