import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../models/fuel_entry.dart';
import '../../models/fuel_stats.dart';
import 'app_card.dart';

/// One refuelling record in the history list.
///
/// Shows the average for the stretch this fill *closed*, when there is one —
/// which is why [point] is separate from [entry]: not every entry produces a
/// figure, and pretending otherwise is how fuel apps mislead people.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.point,
    required this.issues,
    required this.units,
    this.onTap,
  });

  final FuelEntry entry;
  final EconomyPoint? point;
  final List<EntryIssue> issues;
  final UnitFormatter units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final economyPoint = point;
    final hasProblem = issues.any((i) => i.severity != IssueSeverity.info) ||
        (economyPoint?.isOutlier ?? false);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      border: hasProblem
          ? BorderSide(color: AppTheme.warn(context).withValues(alpha: 0.6))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDate(entry.filledAt),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${units.distance(entry.odometer)} on the clock',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    units.money(entry.totalCost),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    units.volume(entry.volume),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (economyPoint != null)
                _Chip(
                  label: units.economy(economyPoint.kmPerLitre),
                  icon: Icons.speed,
                  color: economyPoint.isOutlier
                      ? AppTheme.warn(context)
                      : theme.colorScheme.primary,
                  filled: true,
                ),
              if (entry.pricePerLitre != null)
                _Chip(
                  label: units.pricePerVolume(entry.pricePerLitre),
                  icon: Icons.local_gas_station,
                ),
              if (!entry.isFullTank)
                _Chip(
                  label: 'Partial fill',
                  icon: Icons.battery_3_bar,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              if (entry.missedFillUp)
                _Chip(
                  label: 'Missed fill-up',
                  icon: Icons.link_off,
                  color: AppTheme.warn(context),
                ),
              if (entry.tripMeter != null)
                _Chip(
                  label: 'Trip ${units.distance(entry.tripMeter)}',
                  icon: Icons.route,
                ),
              if (entry.station != null && entry.station!.trim().isNotEmpty)
                _Chip(label: entry.station!.trim(), icon: Icons.place_outlined),
            ],
          ),
          if (economyPoint != null) ...[
            const SizedBox(height: 8),
            Text(
              '${units.distance(economyPoint.distanceKm)} on '
              '${units.volume(economyPoint.fuelLitres)}'
              '${economyPoint.fillCount > 1 ? ' across ${economyPoint.fillCount} fills' : ''}'
              ' · ${units.costPerDistance(economyPoint.costPerKm)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      issue.severity == IssueSeverity.info
                          ? Icons.info_outline
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: issue.severity == IssueSeverity.info
                          ? theme.colorScheme.onSurfaceVariant
                          : AppTheme.warn(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: issue.severity == IssueSeverity.info
                              ? theme.colorScheme.onSurfaceVariant
                              : AppTheme.warn(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (entry.notes != null && entry.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.notes!.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? effective.withValues(alpha: 0.12) : null,
        border: filled
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: effective),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: effective,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
