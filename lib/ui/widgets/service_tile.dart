import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../domain/service_planner.dart';
import '../../models/service_record.dart';
import 'app_card.dart';

/// Colour and icon for a reminder's urgency.
({Color colour, IconData icon, String label}) _statusStyle(
  BuildContext context,
  ServiceStatus status,
) {
  switch (status) {
    case ServiceStatus.overdue:
      return (
        colour: Theme.of(context).colorScheme.error,
        icon: Icons.error_outline,
        label: 'Overdue',
      );
    case ServiceStatus.dueSoon:
      return (
        colour: AppTheme.warn(context),
        icon: Icons.schedule,
        label: 'Due soon',
      );
    case ServiceStatus.upcoming:
      return (
        colour: Theme.of(context).colorScheme.onSurfaceVariant,
        icon: Icons.event_available_outlined,
        label: 'Upcoming',
      );
  }
}

/// One maintenance record in the history list.
class ServiceRecordTile extends StatelessWidget {
  const ServiceRecordTile({
    super.key,
    required this.record,
    required this.units,
    this.onTap,
  });

  final ServiceRecord record;
  final UnitFormatter units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                      record.displayTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDate(record.performedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (record.cost > 0)
                Text(
                  units.money(record.cost),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pill(
                label: record.type.label,
                icon: Icons.build_outlined,
              ),
              if (record.odometer != null)
                _Pill(
                  label: units.distance(record.odometer),
                  icon: Icons.speed,
                ),
              if (record.nextDueOdometer != null)
                _Pill(
                  label: 'Next at ${units.distance(record.nextDueOdometer)}',
                  icon: Icons.event_repeat,
                ),
              if (record.nextDueAt != null)
                _Pill(
                  label: 'Next ${formatDate(record.nextDueAt)}',
                  icon: Icons.notifications_outlined,
                ),
            ],
          ),
          if (record.notes != null && record.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              record.notes!.trim(),
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

/// A due or overdue item, with how far off it is.
class ReminderTile extends StatelessWidget {
  const ReminderTile({
    super.key,
    required this.reminder,
    required this.units,
    this.onTap,
  });

  final ServiceReminder reminder;
  final UnitFormatter units;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _statusStyle(context, reminder.status);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      border: reminder.status == ServiceStatus.upcoming
          ? null
          : BorderSide(color: style.colour.withValues(alpha: 0.6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.colour, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.record.displayTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _describe(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: style.colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reads the two limits out in plain words. Both are shown when both exist,
  /// because which one bites first is exactly what the user wants to know.
  String _describe() {
    final parts = <String>[];

    final km = reminder.kilometresRemaining;
    if (km != null) {
      parts.add(km < 0
          ? '${units.distance(-km)} past due'
          : '${units.distance(km)} to go');
    }

    final days = reminder.daysRemaining;
    if (days != null) {
      if (days < 0) {
        parts.add('${formatDuration(-days)} overdue');
      } else if (days == 0) {
        parts.add('due today');
      } else {
        parts.add('in ${formatDuration(days)}');
      }
    }

    return parts.isEmpty ? 'Tracked' : parts.join(' · ');
  }
}

/// The compact "something needs attention" strip, for the overview tab and
/// the garage card.
class ServiceAlertBanner extends StatelessWidget {
  const ServiceAlertBanner({
    super.key,
    required this.alerts,
    this.onTap,
  });

  final List<ServiceReminder> alerts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final overdue = alerts.where((a) => a.isOverdue).length;
    final style = _statusStyle(
      context,
      overdue > 0 ? ServiceStatus.overdue : ServiceStatus.dueSoon,
    );

    final text = overdue > 0
        ? '$overdue ${overdue == 1 ? 'item is' : 'items are'} overdue'
        : '${alerts.length} ${alerts.length == 1 ? 'item is' : 'items are'} due soon';

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: style.colour.withValues(alpha: 0.10),
      border: BorderSide(color: style.colour.withValues(alpha: 0.4)),
      child: Row(
        children: [
          Icon(style.icon, color: style.colour, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: style.colour,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: style.colour, size: 20),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
