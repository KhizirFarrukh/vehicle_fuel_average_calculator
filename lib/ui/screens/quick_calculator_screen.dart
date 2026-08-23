import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/unit_formatter.dart';
import '../../core/validators.dart';
import '../../domain/fuel_calculator.dart';
import '../../state/settings_controller.dart';
import '../widgets/app_card.dart';
import '../widgets/stat_tile.dart';

/// The original one-shot calculator, kept intact (I15).
///
/// Distance divided by fuel is the right answer to *this* question — "I drove
/// this far on this much fuel, what was the average?" — and it stays available
/// for the times someone just wants the sum done. What it cannot do is track a
/// vehicle over time, which is what the rest of the app is for.
class QuickCalculatorScreen extends StatefulWidget {
  const QuickCalculatorScreen({super.key});

  @override
  State<QuickCalculatorScreen> createState() => _QuickCalculatorScreenState();
}

class _QuickCalculatorScreenState extends State<QuickCalculatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _distance = TextEditingController();
  final _fuel = TextEditingController();
  final _cost = TextEditingController();

  double? _kmPerLitre;
  double? _costPerKm;

  @override
  void dispose() {
    // The version this screen replaces never disposed its controllers.
    _distance.dispose();
    _fuel.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _calculate() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final units = context.read<SettingsController>().formatter;
    final km = units.parseDistanceToKm(_distance.text);
    final litres = units.parseVolumeToLitres(_fuel.text);
    final cost = UnitFormatter.parseNumber(_cost.text);

    if (km == null || litres == null) return;

    setState(() {
      _kmPerLitre = FuelCalculator.simpleAverage(km, litres);
      _costPerKm = (cost != null && km > 0) ? cost / km : null;
    });
  }

  void _reset() {
    _distance.clear();
    _fuel.clear();
    _cost.clear();
    setState(() {
      _kmPerLitre = null;
      _costPerKm = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final units = context.watch<SettingsController>().formatter;
    final theme = Theme.of(context);
    final average = _kmPerLitre;

    return Scaffold(
      appBar: AppBar(title: const Text('Quick calculator')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'A one-off sum. Nothing here is saved — use a vehicle\'s log if '
              'you want the figure tracked over time.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Distance travelled',
                suffix: units.distanceSymbol,
              ),
              validator: (value) => validateNumber(value, 'Distance'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fuel,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Fuel used',
                suffix: units.volumeSymbol,
              ),
              validator: (value) => validateNumber(value, 'Fuel used'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _calculate(),
              decoration: AppTheme.inputDecoration(
                context,
                label: 'Cost of that fuel (optional)',
                prefix: units.currency.isEmpty ? null : '${units.currency} ',
              ),
              validator: (value) =>
                  validateNumber(value, 'Cost', required: false),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _calculate,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Calculate'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
            if (average != null) ...[
              const SizedBox(height: 24),
              StatGrid(
                children: [
                  StatTile(
                    label: 'Fuel average',
                    value: units.economy(average),
                    emphasis: StatEmphasis.primary,
                    icon: Icons.speed,
                  ),
                  if (_costPerKm != null)
                    StatTile(
                      label: 'Cost per ${units.distanceSymbol}',
                      value: units.costPerDistance(_costPerKm),
                      icon: Icons.payments_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'At this rate',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    DetailRow(
                      label: '100 ${units.distanceSymbol} would need',
                      value: units.volume(
                        FuelCalculator.fuelNeeded(
                          units.parseDistanceToKm('100') ?? 100,
                          average,
                        ),
                      ),
                    ),
                    DetailRow(
                      label: '10 ${units.volumeSymbol} would cover',
                      value: units.distance(
                        FuelCalculator.rangeFor(
                          units.parseVolumeToLitres('10') ?? 10,
                          average,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tracking a vehicle instead measures tank to tank, which is '
                'more accurate than a single estimate of fuel used.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              Text(
                kEmDash,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
