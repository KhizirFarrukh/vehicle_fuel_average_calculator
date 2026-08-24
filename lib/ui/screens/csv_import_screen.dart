import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/csv_import_service.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';

/// Imports a CSV fuel log into one vehicle (I23).
///
/// Nothing is written until the file has been read and the result shown, so a
/// mismatched column or a misread date order is caught before it lands in the
/// database rather than after.
class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  final _source = TextEditingController();

  late DistanceUnit _distanceUnit;
  late VolumeUnit _volumeUnit;
  bool _dayFirst = true;
  bool _defaultFullTank = true;

  CsvImportPreview? _preview;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // Default to what the reader uses, which is usually what their file is in.
    final settings = context.read<SettingsController>().settings;
    _distanceUnit = settings.distanceUnit;
    _volumeUnit = settings.volumeUnit;
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  CsvImportOptions get _options => CsvImportOptions(
        distanceUnit: _distanceUnit,
        volumeUnit: _volumeUnit,
        dayFirst: _dayFirst,
        defaultFullTank: _defaultFullTank,
      );

  void _check() {
    final vehicleId = widget.vehicle.id;
    if (vehicleId == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _preview = CsvImportService.preview(
        _source.text,
        vehicleId,
        options: _options,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('Import CSV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Importing into ${widget.vehicle.displayName}.',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Open your CSV file, copy everything in it, and paste it below. '
            'The first line must be a header row. Columns are matched by name, '
            'so exports from other fuel apps usually work as they are.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _source,
            maxLines: 8,
            minLines: 5,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: AppTheme.inputDecoration(
              context,
              label: 'CSV contents',
              hint: 'Date,Odometer,Volume,Total cost\n2026-01-04,12500,32.5,8125',
            ),
            // Always rebuilds: any edit invalidates a preview taken from the
            // old text, and the Check button's enabled state depends on
            // whether the field is empty.
            onChanged: (_) => setState(() => _preview = null),
          ),

          const SectionHeader(
            'How to read the file',
            subtitle: 'These describe the file, not your display settings.',
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Distances are in'),
                  subtitle: Text(_distanceUnit.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickDistanceUnit(),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Volumes are in'),
                  subtitle: Text(_volumeUnit.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickVolumeUnit(),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _dayFirst,
                  onChanged: (value) => setState(() {
                    _dayFirst = value;
                    _preview = null;
                  }),
                  title: const Text('Dates are day first'),
                  subtitle: Text(
                    _dayFirst
                        ? '03/04/2026 means 3 April.'
                        : '03/04/2026 means 4 March.',
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _defaultFullTank,
                  onChanged: (value) => setState(() {
                    _defaultFullTank = value;
                    _preview = null;
                  }),
                  title: const Text('Assume full tanks'),
                  subtitle: const Text(
                    'Applied only to rows with no full-tank column.',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _source.text.trim().isEmpty ? null : _check,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Check the file'),
          ),

          if (preview != null) ...[
            const SectionHeader('What was found'),
            _PreviewCard(preview: preview),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: (!preview.isValid || _importing) ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(
                preview.isValid
                    ? 'Import ${preview.usable.length} fill-ups'
                    : 'Nothing to import',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDistanceUnit() async {
    final chosen = await _pick<DistanceUnit>(
      'Distances are in',
      DistanceUnit.values,
      _distanceUnit,
      (unit) => unit.label,
    );
    if (chosen != null) {
      setState(() {
        _distanceUnit = chosen;
        _preview = null;
      });
    }
  }

  Future<void> _pickVolumeUnit() async {
    final chosen = await _pick<VolumeUnit>(
      'Volumes are in',
      VolumeUnit.values,
      _volumeUnit,
      (unit) => unit.label,
    );
    if (chosen != null) {
      setState(() {
        _volumeUnit = chosen;
        _preview = null;
      });
    }
  }

  Future<T?> _pick<T>(
    String title,
    List<T> options,
    T current,
    String Function(T) labelOf,
  ) {
    return showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          for (final option in options)
            ListTile(
              title: Text(labelOf(option)),
              trailing: option == current
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final preview = _preview;
    final vehicleId = widget.vehicle.id;
    if (preview == null || vehicleId == null || !preview.isValid) return;

    setState(() => _importing = true);

    final garage = context.read<GarageController>();
    // Captured before the pop: afterwards this screen's context is defunct and
    // the snack bar would have nowhere to go.
    final messenger = ScaffoldMessenger.of(context);
    final entries = [
      for (final draft in preview.usable) draft.entry!,
    ];

    try {
      final count = await garage.addEntries(vehicleId, entries);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Imported $count fill-ups.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final CsvImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fatal = preview.fatalError;

    if (fatal != null) {
      return AppCard(
        border: BorderSide(color: theme.colorScheme.error),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fatal,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (preview.headers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Header row read as: ${preview.headers.join(' | ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final skipped = preview.skipped;
    final usable = preview.usable;
    final sample = usable.take(5).toList();
    final assumptions = usable.where((d) => d.problems.isNotEmpty).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${usable.length} rows ready to import',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.good(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Columns recognised: '
                '${preview.recognisedFields.map((f) => f.label).join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (assumptions > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '$assumptions of them needed an assumption — see below.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.warn(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (usable.isNotEmpty) ...[
          const SectionHeader(
            'First few rows',
            padding: EdgeInsets.fromLTRB(4, 20, 4, 12),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < sample.length; i++)
                  _DraftRow(draft: sample[i], isLast: i == sample.length - 1),
              ],
            ),
          ),
        ],
        if (skipped.isNotEmpty) ...[
          const SectionHeader(
            'Rows that will be skipped',
            padding: EdgeInsets.fromLTRB(4, 20, 4, 12),
          ),
          AppCard(
            border: BorderSide(
              color: AppTheme.warn(context).withValues(alpha: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final draft in skipped.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'Line ${draft.lineNumber}: ${draft.problems.join(' ')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (skipped.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '...and ${skipped.length - 8} more.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.draft, required this.isLast});

  final CsvRowDraft draft;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = draft.entry;
    if (entry == null) return const SizedBox.shrink();

    // Values are shown in canonical units here on purpose: this is a check
    // that the file was read correctly, so it should show what will be stored.
    return Column(
      children: [
        ListTile(
          dense: true,
          title: Text(formatDate(entry.filledAt)),
          subtitle: Text(
            '${formatNumber(entry.odometer, decimals: 0)} km · '
            '${formatNumber(entry.volume)} L · '
            '${formatNumber(entry.totalCost)}'
            '${entry.isFullTank ? '' : ' · partial'}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: draft.problems.isEmpty
              ? null
              : Tooltip(
                  message: draft.problems.join(' '),
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppTheme.warn(context),
                  ),
                ),
        ),
        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}
