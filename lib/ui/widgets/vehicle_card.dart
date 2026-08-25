import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/unit_formatter.dart';
import '../../domain/service_planner.dart';
import '../../models/fuel_stats.dart';
import '../../models/vehicle.dart';
import 'app_card.dart';
import 'service_tile.dart';

/// A vehicle in the garage list, with its headline average.
class VehicleCard extends StatelessWidget {
  const VehicleCard({
    super.key,
    required this.vehicle,
    required this.stats,
    required this.units,
    required this.onTap,
    this.serviceAlerts = const [],
    this.onLongPress,
  });

  final Vehicle vehicle;
  final VehicleStats stats;
  final UnitFormatter units;
  final VoidCallback onTap;

  /// Overdue or nearly-due maintenance, surfaced here so it is visible without
  /// opening the vehicle.
  final List<ServiceReminder> serviceAlerts;

  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = stats.lifetimeKmPerLitre;

    return AppCard(
      onTap: onTap,
      border: vehicle.isArchived
          ? BorderSide(color: theme.colorScheme.outlineVariant)
          : null,
      color: vehicle.isArchived ? theme.colorScheme.surface : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(vehicle: vehicle),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vehicle.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (vehicle.isArchived) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: 'Archived',
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicle.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Average',
                  value: average == null
                      ? kEmDash
                      : units.economy(average),
                  emphasise: true,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Fill-ups',
                  value: stats.entryCount.toString(),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Last fill',
                  value: stats.lastDate == null
                      ? kEmDash
                      : formatRelativeDate(stats.lastDate),
                ),
              ),
            ],
          ),
          if (serviceAlerts.isNotEmpty) ...[
            const SizedBox(height: 12),
            ServiceAlertBanner(alerts: serviceAlerts),
          ],
          if (!stats.hasEconomy && stats.hasEntries) ...[
            const SizedBox(height: 10),
            Text(
              stats.entryCount == 1
                  ? 'Log one more full tank to get your first average.'
                  : 'No full-tank-to-full-tank stretch yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        vehicle.initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasise ? theme.colorScheme.primary : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
