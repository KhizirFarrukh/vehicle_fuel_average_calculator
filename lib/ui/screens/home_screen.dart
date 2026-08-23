import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/unit_formatter.dart';
import '../../models/vehicle.dart';
import '../../state/garage_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';
import '../widgets/vehicle_card.dart';
import 'quick_calculator_screen.dart';
import 'settings_screen.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_form_screen.dart';

/// The garage: every vehicle, each with its current average.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final garage = context.watch<GarageController>();
    final units = context.watch<SettingsController>().formatter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Garage'),
        actions: [
          IconButton(
            tooltip: 'Quick calculator',
            icon: const Icon(Icons.calculate_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QuickCalculatorScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: garage.hasAnyVehicle
          ? FloatingActionButton.extended(
              onPressed: () => _addVehicle(context),
              icon: const Icon(Icons.add),
              label: const Text('Add vehicle'),
            )
          : null,
      body: _Body(garage: garage, units: units),
    );
  }

  static Future<void> _addVehicle(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VehicleFormScreen()),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.garage, required this.units});

  final GarageController garage;
  final UnitFormatter units;

  @override
  Widget build(BuildContext context) {
    if (garage.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = garage.error;
    if (error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Something went wrong',
        message: error,
        action: FilledButton(
          onPressed: garage.load,
          child: const Text('Try again'),
        ),
      );
    }

    if (!garage.hasAnyVehicle) {
      return EmptyState(
        icon: Icons.directions_car_outlined,
        title: 'No vehicles yet',
        message: 'Add your first vehicle, then log a fill-up each time you '
            'visit the pump. Two full tanks is all it takes to get an average.',
        action: FilledButton.icon(
          onPressed: () => HomeScreen._addVehicle(context),
          icon: const Icon(Icons.add),
          label: const Text('Add a vehicle'),
        ),
      );
    }

    final vehicles = garage.vehicles;

    return RefreshIndicator(
      onRefresh: garage.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          for (final vehicle in vehicles) ...[
            VehicleCard(
              vehicle: vehicle,
              stats: garage.statsFor(vehicle.id),
              units: units,
              onTap: () => _openVehicle(context, vehicle),
            ),
            const SizedBox(height: 12),
          ],
          if (vehicles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Every vehicle is archived.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          if (garage.archivedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => garage.setShowArchived(!garage.showArchived),
                  icon: Icon(
                    garage.showArchived
                        ? Icons.visibility_off_outlined
                        : Icons.inventory_2_outlined,
                  ),
                  label: Text(
                    garage.showArchived
                        ? 'Hide archived'
                        : 'Show ${garage.archivedCount} archived',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openVehicle(BuildContext context, Vehicle vehicle) {
    final id = vehicle.id;
    if (id == null) return;
    context.read<SettingsController>().setLastVehicleId(id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleDetailScreen(vehicleId: id),
      ),
    );
  }
}
