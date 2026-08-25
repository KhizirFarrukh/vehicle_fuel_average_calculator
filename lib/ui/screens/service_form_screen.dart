import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../core/validators.dart';
import '../../domain/service_planner.dart';
import '../../models/service_record.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';

/// Add or edit a maintenance record (I19).
class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({
    super.key,
    required this.vehicle,
    this.existing,
  });

  final Vehicle vehicle;
  final ServiceRecord? existing;

  bool get isEditing => existing != null;

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _odometer;
  late final TextEditingController _cost;
  late final TextEditingController _notes;
  late final TextEditingController _nextDueOdometer;

  late ServiceType _type;
  late DateTime _performedAt;
  DateTime? _nextDueAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final record = widget.existing;
    final units = context.read<SettingsController>().formatter;

    _type = record?.type ?? ServiceType.oilChange;
    _performedAt = record?.performedAt ?? DateTime.now();
    _nextDueAt = record?.nextDueAt;

    _title = TextEditingController(text: record?.title ?? '');
    _odometer = TextEditingController(
      text: units.distanceFieldText(
        record?.odometer ?? _currentOdometer(),
      ),
    );
    _cost = TextEditingController(
      text: record == null ? '' : formatCompactNumber(record.cost),
    );
    _notes = TextEditingController(text: record?.notes ?? '');
    _nextDueOdometer = TextEditingController(
      text: units.distanceFieldText(record?.nextDueOdometer),
    );

    // A new record starts with the type's typical interval already filled in.
    if (record == null) _applySuggestion();
  }

  double? _currentOdometer() =>
      context.read<GarageController>().currentOdometerFor(widget.vehicle.id);

  @override
  void dispose() {
    _title.dispose();
    _odometer.dispose();
    _cost.dispose();
    _notes.dispose();
    _nextDueOdometer.dispose();
    super.dispose();
  }

  /// Fills the next-due fields from the selected type's typical interval,
  /// measured from the odometer actually typed in rather than the vehicle's
  /// latest — the two differ when back-filling an old receipt.
  void _applySuggestion() {
    final units = context.read<SettingsController>().formatter;
    final typedOdometer = units.parseDistanceToKm(_odometer.text);

    final suggestion = ServicePlanner.suggestNextDue(
      _type,
      currentOdometerKm: typedOdometer ?? _currentOdometer(),
      performedAt: _performedAt,
    );

    _nextDueOdometer.text = units.distanceFieldText(suggestion.odometer);
    _nextDueAt = suggestion.date;
  }

  @override
  Widget build(BuildContext context) {
    final units = context.watch<SettingsController>().formatter;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit service' : 'Log service'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              widget.vehicle.displayName,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<ServiceType>(
              value: _type,
              decoration: AppTheme.inputDecoration(context, label: 'What was done'),
              items: [
                for (final type in ServiceType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _type = value;
                  // The old suggestion belonged to the old type.
                  _applySuggestion();
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Description (optional)',
                hint: 'Rear pads and discs',
                helper: 'Leave blank to just show "${_type.label}".',
              ),
            ),

            const SectionHeader('When'),
            _DateTile(
              icon: Icons.event_outlined,
              label: 'Date',
              value: formatDate(_performedAt),
              onTap: () async {
                final picked = await _pickDate(_performedAt);
                if (picked != null) setState(() => _performedAt = picked);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _odometer,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Odometer (optional)',
                suffix: units.distanceSymbol,
                helper: 'Leave blank for things with no mileage, like '
                    'insurance renewal.',
              ),
              validator: (value) => validateNumber(
                value,
                'Odometer',
                required: false,
                allowZero: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Cost',
                prefix: units.currency.isEmpty ? null : '${units.currency} ',
              ),
              validator: (value) => validateNumber(
                value,
                'Cost',
                required: false,
                allowZero: true,
              ),
            ),

            SectionHeader(
              'Next due',
              subtitle: 'Fill in either, both, or neither. Whichever comes '
                  'first is what you get reminded about.',
              action: TextButton(
                onPressed: () => setState(_applySuggestion),
                child: const Text('Suggest'),
              ),
            ),
            TextFormField(
              controller: _nextDueOdometer,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Next due at odometer',
                suffix: units.distanceSymbol,
              ),
              validator: (value) => validateNumber(
                value,
                'Next due odometer',
                required: false,
              ),
            ),
            const SizedBox(height: 12),
            _DateTile(
              icon: Icons.notifications_outlined,
              label: 'Next due date',
              value: _nextDueAt == null ? 'Not set' : formatDate(_nextDueAt),
              trailing: _nextDueAt == null
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _nextDueAt = null),
                    ),
              onTap: () async {
                final picked = await _pickDate(
                  _nextDueAt ?? DateTime.now(),
                  allowFuture: true,
                );
                if (picked != null) setState(() => _nextDueAt = picked);
              },
            ),

            const SectionHeader('Notes'),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Notes',
                hint: 'Garage, parts used, anything worth remembering',
              ),
            ),

            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(widget.isEditing ? 'Save changes' : 'Save service'),
            ),
          ],
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(DateTime initial, {bool allowFuture = false}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 30),
      // A next-due date is by definition ahead; a service date is not.
      lastDate: allowFuture
          ? DateTime(now.year + 10, 12, 31)
          : DateTime(now.year + 1, 12, 31),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final vehicleId = widget.vehicle.id;
    if (vehicleId == null) return;

    setState(() => _saving = true);

    final garage = context.read<GarageController>();
    final units = context.read<SettingsController>().formatter;
    final now = DateTime.now();
    final existing = widget.existing;

    final record = ServiceRecord(
      id: existing?.id,
      vehicleId: vehicleId,
      type: _type,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      performedAt: _performedAt,
      odometer: units.parseDistanceToKm(_odometer.text),
      cost: UnitFormatter.parseNumber(_cost.text) ?? 0,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      nextDueOdometer: units.parseDistanceToKm(_nextDueOdometer.text),
      nextDueAt: _nextDueAt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (existing == null) {
        await garage.addService(record);
      } else {
        await garage.updateService(record);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $error')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final record = widget.existing;
    if (record == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(
          '${record.displayTitle} from ${formatDate(record.performedAt)} '
          'will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await context.read<GarageController>().deleteService(record);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
        trailing: trailing ?? const Icon(Icons.edit_calendar_outlined),
        onTap: onTap,
      ),
    );
  }
}
