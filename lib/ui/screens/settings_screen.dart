import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/backup_service.dart';
import '../../models/app_settings.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionHeader(
            'Units',
            subtitle: 'Stored data never changes — only how it is shown.',
            padding: EdgeInsets.fromLTRB(4, 12, 4, 12),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ChoiceTile<DistanceUnit>(
                  title: 'Distance',
                  current: settings.distanceUnit,
                  options: DistanceUnit.values,
                  labelOf: (unit) => '${unit.label} (${unit.symbol})',
                  onSelected: controller.setDistanceUnit,
                ),
                const Divider(height: 1),
                _ChoiceTile<VolumeUnit>(
                  title: 'Volume',
                  current: settings.volumeUnit,
                  options: VolumeUnit.values,
                  labelOf: (unit) => '${unit.label} (${unit.symbol})',
                  onSelected: controller.setVolumeUnit,
                ),
                const Divider(height: 1),
                _ChoiceTile<EconomyUnit>(
                  title: 'Fuel economy',
                  current: settings.economyUnit,
                  options: EconomyUnit.values,
                  labelOf: (unit) => '${unit.label} (${unit.symbol})',
                  onSelected: controller.setEconomyUnit,
                ),
              ],
            ),
          ),

          const SectionHeader('Currency'),
          AppCard(
            child: _CurrencyField(
              value: settings.currencySymbol,
              onChanged: controller.setCurrencySymbol,
            ),
          ),

          const SectionHeader('Appearance'),
          AppCard(
            padding: EdgeInsets.zero,
            child: _ChoiceTile<AppThemeMode>(
              title: 'Theme',
              current: settings.themeMode,
              options: AppThemeMode.values,
              labelOf: (mode) => mode.label,
              onSelected: controller.setThemeMode,
            ),
          ),

          const SectionHeader(
            'Your data',
            subtitle: 'Everything stays on this device.',
          ),
          const _DataCard(),

          const SectionHeader('About'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fuel Log',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Averages are measured tank to tank between full fill-ups, '
                  'which is the only way to know how much fuel a given '
                  'distance actually used.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row that opens a picker. Built from plain [ListTile]s rather
/// than `RadioListTile`, whose `groupValue`/`onChanged` API is mid-deprecation
/// and differs across Flutter versions.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.current,
    required this.options,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final T current;
  final List<T> options;
  final String Function(T) labelOf;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(labelOf(current)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final chosen = await showDialog<T>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(title),
            children: [
              for (final option in options)
                ListTile(
                  title: Text(labelOf(option)),
                  trailing: option == current
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(option),
                ),
            ],
          ),
        );
        if (chosen != null) onSelected(chosen);
      },
    );
  }
}

class _CurrencyField extends StatefulWidget {
  const _CurrencyField({required this.value, required this.onChanged});

  final String value;
  final void Function(String) onChanged;

  @override
  State<_CurrencyField> createState() => _CurrencyFieldState();
}

class _CurrencyFieldState extends State<_CurrencyField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLength: 6,
      textInputAction: TextInputAction.done,
      decoration: AppTheme.inputDecoration(
        context,
        label: 'Currency symbol',
        helper: 'Shown before every amount. No conversion is performed.',
      ),
      onChanged: (value) => widget.onChanged(value.trim()),
    );
  }
}

// ---------------------------------------------------------------------------
// Backup / export (I14)
// ---------------------------------------------------------------------------

class _DataCard extends StatefulWidget {
  const _DataCard();

  @override
  State<_DataCard> createState() => _DataCardState();
}

class _DataCardState extends State<_DataCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Back up to a JSON file'),
            subtitle: const Text('Vehicles, fill-ups and settings.'),
            enabled: !_busy,
            onTap: _exportJson,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export the log as CSV'),
            subtitle: const Text('Values in kilometres and litres.'),
            enabled: !_busy,
            onTap: _exportCsv,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from a backup'),
            subtitle: const Text('Paste the contents of a backup file.'),
            enabled: !_busy,
            onTap: _restore,
          ),
        ],
      ),
    );
  }

  Future<void> _exportJson() async {
    setState(() => _busy = true);
    final backup = context.read<BackupService>();
    try {
      final path = await backup.exportJsonFile();
      if (!mounted) return;
      await _showPath('Backup saved', path);
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    final backup = context.read<BackupService>();
    try {
      final path = await backup.exportCsvFile();
      if (!mounted) return;
      await _showPath('CSV saved', path);
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPath(String title, String path) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(path),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Copy path'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore() async {
    final controller = TextEditingController();
    var mode = RestoreMode.replace;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Restore from a backup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Open your backup file, copy everything in it, and paste it '
                  'below.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '{ "format": "..." }',
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<RestoreMode>(
                  segments: const [
                    ButtonSegment(
                      value: RestoreMode.replace,
                      label: Text('Replace'),
                    ),
                    ButtonSegment(
                      value: RestoreMode.merge,
                      label: Text('Merge'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => mode = selection.first),
                ),
                const SizedBox(height: 8),
                Text(
                  mode == RestoreMode.replace
                      ? 'Deletes everything currently in the app first.'
                      : 'Adds the backup alongside what is already here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );

    final source = controller.text;
    controller.dispose();

    if (confirmed != true || source.trim().isEmpty || !mounted) return;

    setState(() => _busy = true);
    final backup = context.read<BackupService>();
    final garage = context.read<GarageController>();
    final settings = context.read<SettingsController>();

    try {
      final result = await backup.restoreFromJson(source, mode: mode);
      await garage.reloadAfterRestore();
      await settings.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${result.vehiclesAdded} '
            '${result.vehiclesAdded == 1 ? 'vehicle' : 'vehicles'}, '
            '${result.entriesAdded} fill-ups and '
            '${result.servicesAdded} service records.',
          ),
        ),
      );
    } catch (error) {
      _reportError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reportError(Object error) {
    if (!mounted) return;
    final message =
        error is FormatException ? error.message : 'Something went wrong: $error';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
