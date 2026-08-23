import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/fuel_entry_dao.dart';
import 'data/settings_dao.dart';
import 'data/vehicle_dao.dart';
import 'state/garage_controller.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop needs the FFI sqlite backend registered before the first open.
  AppDatabase.registerPlatformFactory();

  final database = await _openDatabase();
  if (database == null) return; // _openDatabase has already shown the failure.

  final vehicleDao = VehicleDao(database.db);
  final entryDao = FuelEntryDao(database.db);
  final settingsDao = SettingsDao(database.db);

  final settingsController = SettingsController(settingsDao);
  final garageController = GarageController(
    vehicleDao: vehicleDao,
    entryDao: entryDao,
  );

  // Load before the first frame, so the app never flashes an empty garage at
  // someone who has fifty entries.
  await settingsController.load();
  await garageController.load();

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<BackupService>(
          create: (_) => BackupService(
            vehicles: vehicleDao,
            entries: entryDao,
            settings: settingsDao,
          ),
        ),
        ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
        ),
        ChangeNotifierProvider<GarageController>.value(
          value: garageController,
        ),
      ],
      child: const FuelApp(),
    ),
  );
}

/// Returns null after showing [_StartupFailureApp], so [main] can simply stop.
Future<AppDatabase?> _openDatabase() async {
  try {
    return await AppDatabase.open();
  } catch (error, stack) {
    debugPrint('Database failed to open: $error\n$stack');
    runApp(_StartupFailureApp(error: error.toString()));
    return null;
  }
}

/// Shown when the database cannot be opened at all. Rare, but the alternative
/// is a blank screen with no explanation.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Could not open the local database',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
