import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';

/// Add or edit a vehicle.
///
/// Make, model and variant are required; year, colour and licence plate are
/// optional, exactly as specified. Fuel type, tank capacity and the starting
/// odometer are additions (I7).
class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({super.key, this.existing});

  final Vehicle? existing;

  bool get isEditing => existing != null;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _variant;
  late final TextEditingController _year;
  late final TextEditingController _color;
  late final TextEditingController _plate;
  late final TextEditingController _tank;
  late final TextEditingController _odometer;
  late final TextEditingController _notes;

  late FuelType _fuelType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.existing;
    final units = context.read<SettingsController>().formatter;

    _make = TextEditingController(text: vehicle?.make ?? '');
    _model = TextEditingController(text: vehicle?.model ?? '');
    _variant = TextEditingController(text: vehicle?.variant ?? '');
    _year = TextEditingController(text: vehicle?.year?.toString() ?? '');
    _color = TextEditingController(text: vehicle?.color ?? '');
    _plate = TextEditingController(text: vehicle?.licensePlate ?? '');
    _tank = TextEditingController(
      text: units.volumeFieldText(vehicle?.tankCapacity),
    );
    _odometer = TextEditingController(
      text: units.distanceFieldText(vehicle?.initialOdometer),
    );
    _notes = TextEditingController(text: vehicle?.notes ?? '');
    _fuelType = vehicle?.fuelType ?? FuelType.petrol;
  }

  @override
  void dispose() {
    // The original screen leaked its controllers; these are all disposed.
    _make.dispose();
    _model.dispose();
    _variant.dispose();
    _year.dispose();
    _color.dispose();
    _plate.dispose();
    _tank.dispose();
    _odometer.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = context.watch<SettingsController>().formatter;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit vehicle' : 'Add vehicle'),
        actions: [
          if (widget.isEditing)
            PopupMenuButton<String>(
              onSelected: _onMenuSelected,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    widget.existing!.isArchived ? 'Unarchive' : 'Archive',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete vehicle'),
                ),
              ],
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const SectionHeader(
              'Identity',
              subtitle: 'Make, model and variant are required.',
              padding: EdgeInsets.only(bottom: 12),
            ),
            TextFormField(
              controller: _make,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Make',
                hint: 'Toyota',
              ),
              validator: (value) => validateRequired(value, 'Make'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Model',
                hint: 'Corolla',
              ),
              validator: (value) => validateRequired(value, 'Model'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _variant,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Variant',
                hint: 'Altis Grande 1.8',
              ),
              validator: (value) => validateRequired(value, 'Variant'),
            ),

            const SectionHeader(
              'Optional details',
              subtitle: 'Leave any of these blank.',
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: AppTheme.inputDecoration(
                      context,
                      label: 'Year',
                      hint: '2019',
                    ),
                    validator: validateYear,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _color,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: AppTheme.inputDecoration(
                      context,
                      label: 'Colour',
                      hint: 'White',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Licence plate',
                hint: 'ABC-123',
              ),
            ),

            const SectionHeader(
              'Fuel',
              subtitle: 'Tank capacity unlocks the range estimate.',
            ),
            // `value:` rather than the newer `initialValue:` — the latter does
            // not exist on older Flutter versions, while `value:` compiles on
            // both.
            DropdownButtonFormField<FuelType>(
              value: _fuelType,
              decoration: AppTheme.inputDecoration(context, label: 'Fuel type'),
              items: [
                for (final type in FuelType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _fuelType = value);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tank,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: AppTheme.inputDecoration(
                      context,
                      label: 'Tank capacity',
                      suffix: units.volumeSymbol,
                    ),
                    validator: (value) => validateNumber(
                      value,
                      'Tank capacity',
                      required: false,
                      max: 1000,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _odometer,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: AppTheme.inputDecoration(
                      context,
                      label: 'Odometer now',
                      suffix: units.distanceSymbol,
                    ),
                    validator: (value) => validateNumber(
                      value,
                      'Odometer',
                      required: false,
                      allowZero: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Notes',
                hint: 'Anything worth remembering about this vehicle',
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
              label: Text(widget.isEditing ? 'Save changes' : 'Add vehicle'),
            ),
          ],
        ),
      ),
    );
  }

  String? _trimmedOrNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final garage = context.read<GarageController>();
    final units = context.read<SettingsController>().formatter;
    final now = DateTime.now();
    final existing = widget.existing;

    final vehicle = Vehicle(
      id: existing?.id,
      make: _make.text.trim(),
      model: _model.text.trim(),
      variant: _variant.text.trim(),
      year: parseFlexibleInt(_year.text),
      color: _trimmedOrNull(_color),
      licensePlate: _trimmedOrNull(_plate),
      fuelType: _fuelType,
      tankCapacity: units.parseVolumeToLitres(_tank.text),
      initialOdometer: units.parseDistanceToKm(_odometer.text),
      notes: _trimmedOrNull(_notes),
      isArchived: existing?.isArchived ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (existing == null) {
        await garage.addVehicle(vehicle);
      } else {
        await garage.updateVehicle(vehicle);
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

  Future<void> _onMenuSelected(String value) async {
    final vehicle = widget.existing;
    final id = vehicle?.id;
    if (vehicle == null || id == null) return;

    final garage = context.read<GarageController>();
    final navigator = Navigator.of(context);

    if (value == 'archive') {
      await garage.setArchived(id, !vehicle.isArchived);
      if (!mounted) return;
      navigator.pop();
      return;
    }

    if (value == 'delete') {
      final confirmed = await _confirmDelete(vehicle);
      if (!confirmed) return;
      await garage.deleteVehicle(id);
      if (!mounted) return;
      // Pop the form and the detail screen behind it.
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Future<bool> _confirmDelete(Vehicle vehicle) async {
    final entryCount =
        context.read<GarageController>().entriesFor(vehicle.id).length;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this vehicle?'),
        content: Text(
          entryCount == 0
              ? 'This removes ${vehicle.displayName} from your garage.'
              : 'This permanently deletes ${vehicle.displayName} and all '
                  '$entryCount of its fill-up records. This cannot be undone.\n\n'
                  'If you only want it out of the way, archive it instead.',
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

    return result ?? false;
  }
}
