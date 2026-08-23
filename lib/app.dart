import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'state/settings_controller.dart';
import 'ui/screens/home_screen.dart';

class FuelApp extends StatelessWidget {
  const FuelApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Only the theme mode needs to rebuild MaterialApp; screens read the rest
    // of the settings where they use them.
    final themeMode = context.select<SettingsController, ThemeMode>(
      (controller) => controller.themeMode,
    );

    return MaterialApp(
      title: 'Fuel Log',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
