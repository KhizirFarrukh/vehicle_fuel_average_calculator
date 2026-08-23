import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../core/validators.dart';
import '../../domain/fuel_calculator.dart';
import '../../models/fuel_entry.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';

/// Add or edit a refuelling record.
///
/// Captures the four requested fields — litres, cost, trip meter and odometer
/// — plus the two flags that make the resulting averages trustworthy.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({
    super.key,
    required this.vehicle,
    this.existing,
  });

  final Vehicle vehicle;
  final FuelEntry? existing;

  bool get isEditing => existing != null;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _odometer;
  late final TextEditingController _trip;
  late final TextEditingController _volume;
  late final TextEditingController _price;
  late final TextEditingController _total;
  late final TextEditingController _station;
  late final TextEditingController _notes;

  late DateTime _date;
  late bool _isFullTank;
  late bool _missedFillUp;

  /// Guards the volume/price/total cross-computation against recursion.
  bool _syncing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.existing;
    final units = context.read<SettingsController>().formatter;

    _odometer = TextEditingController(
      text: units.distanceFieldText(entry?.odometer),
    );
    _trip = TextEditingController(text: units.distanceFieldText(entry?.tripMeter));
    _volume = TextEditingController(text: units.volumeFieldText(entry?.volume));
    _total = TextEditingController(
      text: entry == null ? '' : formatCompactNumber(entry.totalCost),
    );
    _price = TextEditingController(
      text: entry?.pricePerLitre == null
          ? ''
          : formatCompactNumber(
              units.priceValue(entry!.pricePerLitre!),
              maxDecimals: 3,
            ),
    );
    _station = TextEditingController(text: entry?.station ?? '');
    _notes = TextEditingController(text: entry?.notes ?? '');

    _date = entry?.filledAt ?? DateTime.now();
    _isFullTank = entry?.isFullTank ?? true;
    _missedFillUp = entry?.missedFillUp ?? false;

    _volume.addListener(_recalculateFromVolumeOrPrice);
    _price.addListener(_recalculateFromVolumeOrPrice);
    _total.addListener(_recalculateFromTotal);
    _odometer.addListener(_onOdometerChanged);

    if (entry == null) _prefillFromLastEntry();
  }

  /// I17 — seeds the station from last time, since most people refuel in the
  /// same handful of places. Deliberately does *not* prefill numbers, which
  /// would be far too easy to save unchanged.
  void _prefillFromLastEntry() {
    final entries = context.read<GarageController>().entriesFor(widget.vehicle.id);
    if (entries.isEmpty) return;
    final last = entries.last;
    if (last.station != null && last.station!.trim().isNotEmpty) {
      _station.text = last.station!.trim();
    }
  }

  @override
  void dispose() {
    _volume.removeListener(_recalculateFromVolumeOrPrice);
    _price.removeListener(_recalculateFromVolumeOrPrice);
    _total.removeListener(_recalculateFromTotal);
    _odometer.removeListener(_onOdometerChanged);

    _odometer.dispose();
    _trip.dispose();
    _volume.dispose();
    _price.dispose();
    _total.dispose();
    _station.dispose();
    _notes.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // I18 — type any two of volume / price / total, get the third
  // -------------------------------------------------------------------------

  void _setQuietly(TextEditingController controller, String text) {
    if (controller.text == text) return;
    _syncing = true;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
  }

  void _recalculateFromVolumeOrPrice() {
    if (_syncing) return;
    final volume = UnitFormatter.parseNumber(_volume.text);
    final price = UnitFormatter.parseNumber(_price.text);
    if (volume == null || price == null) return;
    _setQuietly(_total, formatCompactNumber(volume * price));
  }

  void _recalculateFromTotal() {
    if (_syncing) return;
    final total = UnitFormatter.parseNumber(_total.text);
    if (total == null) return;

    final volume = UnitFormatter.parseNumber(_volume.text);
    if (volume != null && volume > 0) {
      _setQuietly(_price, formatCompactNumber(total / volume, maxDecimals: 3));
      return;
    }

    final price = UnitFormatter.parseNumber(_price.text);
    if (price != null && price > 0) {
      _setQuietly(_volume, formatCompactNumber(total / price, maxDecimals: 3));
    }
  }

  void _onOdometerChanged() {
    // Refreshes the "since last fill" helper under the odometer and trip
    // fields.
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final units = context.watch<SettingsController>().formatter;
    final garage = context.watch<GarageController>();
    final entries = garage.entriesFor(widget.vehicle.id);
    final lastOdometerKm = FuelCalculator.lastOdometer(
      entries,
      excludingId: widget.existing?.id,
    );

    final enteredOdometerKm = units.parseDistanceToKm(_odometer.text);
    final previous = enteredOdometerKm == null
        ? null
        : FuelCalculator.previousEntry(
            entries,
            enteredOdometerKm,
            excludingId: widget.existing?.id,
          );
    final sinceLastKm = (enteredOdometerKm != null && previous != null)
        ? enteredOdometerKm - previous.odometer
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit fill-up' : 'Log a fill-up'),
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

            _DateField(
              date: _date,
              onChanged: (value) => setState(() => _date = value),
            ),

            const SectionHeader('Readings'),
            TextFormField(
              controller: _odometer,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Odometer',
                suffix: units.distanceSymbol,
                helper: lastOdometerKm == null
                    ? 'The total distance shown on the dash.'
                    : 'Last recorded: ${units.distance(lastOdometerKm)}'
                        '${sinceLastKm != null && sinceLastKm > 0 ? ' · ${units.distance(sinceLastKm)} since then' : ''}',
              ),
              validator: (value) => _validateOdometer(value, units, entries),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _trip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Trip meter (optional)',
                suffix: units.distanceSymbol,
                helper: 'Distance since you last reset the trip.',
                suffixIcon: (sinceLastKm != null && sinceLastKm > 0)
                    ? IconButton(
                        tooltip: 'Use ${units.distance(sinceLastKm)}',
                        icon: const Icon(Icons.auto_fix_high, size: 20),
                        onPressed: () => _trip.text =
                            units.distanceFieldText(sinceLastKm),
                      )
                    : null,
              ),
              validator: (value) => validateNumber(
                value,
                'Trip meter',
                required: false,
              ),
            ),

            SectionHeader(
              'Fuel and cost',
              subtitle: 'Fill in any two — the third works itself out.',
            ),
            TextFormField(
              controller: _volume,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Amount refilled',
                suffix: units.volumeSymbol,
              ),
              validator: (value) => validateNumber(value, 'Amount refilled'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: AppTheme.inputDecoration(
                      context,
                      label: 'Price per ${units.volumeSymbol}',
                    ),
                    validator: (value) => validateNumber(
                      value,
                      'Price',
                      required: false,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _total,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: AppTheme.inputDecoration(
                      context,
                      label: 'Total cost',
                      prefix: units.currency.isEmpty
                          ? null
                          : '${units.currency} ',
                    ),
                    validator: (value) =>
                        validateNumber(value, 'Total cost', allowZero: true),
                  ),
                ),
              ],
            ),

            const SectionHeader(
              'How this fill counts',
              subtitle: 'These two switches decide whether an average can be '
                  'worked out for this stretch.',
            ),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    value: _isFullTank,
                    onChanged: (value) => setState(() => _isFullTank = value),
                    title: const Text('Filled to full'),
                    subtitle: Text(
                      _isFullTank
                          ? 'Closes the current stretch and starts a new one.'
                          : 'Partial fill — these litres roll into the next '
                              'full tank instead.',
                    ),
                    isThreeLine: !_isFullTank,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _missedFillUp,
                    onChanged: (value) => setState(() => _missedFillUp = value),
                    title: const Text('I missed logging a fill before this'),
                    subtitle: const Text(
                      'Skips the average for the stretch leading up to this '
                      'entry rather than reporting a wrong one.',
                    ),
                    isThreeLine: true,
                  ),
                ],
              ),
            ),

            const SectionHeader('Optional'),
            TextFormField(
              controller: _station,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Station',
                hint: 'Shell, Main Street',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: AppTheme.inputDecoration(context, label: 'Notes'),
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
              label: Text(widget.isEditing ? 'Save changes' : 'Save fill-up'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Validation (I9)
  // -------------------------------------------------------------------------

  String? _validateOdometer(
    String? value,
    UnitFormatter units,
    List<FuelEntry> entries,
  ) {
    final basic = validateNumber(value, 'Odometer');
    if (basic != null) return basic;

    final km = units.parseDistanceToKm(value);
    if (km == null) return 'Enter a valid odometer reading';

    for (final entry in entries) {
      if (entry.id == widget.existing?.id) continue;
      if ((entry.odometer - km).abs() < 0.001) {
        return 'Another fill-up is already recorded at this reading '
            '(${formatDate(entry.filledAt)}).';
      }
    }

    return null;
  }

  /// Non-blocking checks, raised as a confirmation rather than an error —
  /// back-filling an older receipt is legitimate, mistyping a digit is not,
  /// and only the user can tell the two apart.
  Future<bool> _confirmSuspiciousValues(
    double odometerKm,
    List<FuelEntry> entries,
  ) async {
    final highest = FuelCalculator.lastOdometer(
      entries,
      excludingId: widget.existing?.id,
    );
    final units = context.read<SettingsController>().formatter;
    final warnings = <String>[];

    if (highest != null && odometerKm < highest) {
      warnings.add(
        'The odometer reading (${units.distance(odometerKm)}) is lower than '
        'the highest one on record (${units.distance(highest)}). That is fine '
        'if you are entering an older receipt.',
      );
    }

    if (highest != null && odometerKm - highest > 5000) {
      warnings.add(
        'That is ${units.distance(odometerKm - highest)} since the last '
        'fill-up. Check the reading if that was not a long trip.',
      );
    }

    if (warnings.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Does this look right?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(warning),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final garage = context.read<GarageController>();
    final units = context.read<SettingsController>().formatter;
    final vehicleId = widget.vehicle.id;
    if (vehicleId == null) return;

    final odometerKm = units.parseDistanceToKm(_odometer.text);
    final volumeLitres = units.parseVolumeToLitres(_volume.text);
    final totalCost = UnitFormatter.parseNumber(_total.text);

    if (odometerKm == null || volumeLitres == null || totalCost == null) return;

    final proceed = await _confirmSuspiciousValues(
      odometerKm,
      garage.entriesFor(vehicleId),
    );
    if (!proceed || !mounted) return;

    setState(() => _saving = true);

    final now = DateTime.now();
    final existing = widget.existing;

    final entry = FuelEntry(
      id: existing?.id,
      vehicleId: vehicleId,
      filledAt: _date,
      odometer: odometerKm,
      tripMeter: units.parseDistanceToKm(_trip.text),
      volume: volumeLitres,
      totalCost: totalCost,
      isFullTank: _isFullTank,
      missedFillUp: _missedFillUp,
      station: _station.text.trim().isEmpty ? null : _station.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (existing == null) {
        await garage.addEntry(entry);
      } else {
        await garage.updateEntry(entry);
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
    final entry = widget.existing;
    if (entry == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this fill-up?'),
        content: Text(
          'The record from ${formatDate(entry.filledAt)} will be removed, and '
          'the averages around it recalculated.',
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

    await context.read<GarageController>().deleteEntry(entry);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: const Text('Date of fill-up'),
        subtitle: Text(formatDate(date)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(now.year - 30),
            lastDate: DateTime(now.year + 1, 12, 31),
          );
          if (picked != null) {
            // Keep the original time of day so ordering within a day is stable.
            onChanged(DateTime(
              picked.year,
              picked.month,
              picked.day,
              date.hour,
              date.minute,
            ));
          }
        },
      ),
    );
  }
}
