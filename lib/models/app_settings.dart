/// User preferences. Pure Dart — the Flutter `ThemeMode` mapping lives in the
/// UI layer so this stays testable.
library;

import '../core/units.dart';

enum AppThemeMode {
  system('system', 'Follow system'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const AppThemeMode(this.key, this.label);

  final String key;
  final String label;

  static AppThemeMode fromKey(String? key) {
    for (final mode in AppThemeMode.values) {
      if (mode.key == key) return mode;
    }
    return AppThemeMode.system;
  }
}

/// Persisted as rows in the `settings` key/value table.
class AppSettings {
  const AppSettings({
    this.distanceUnit = DistanceUnit.kilometre,
    this.volumeUnit = VolumeUnit.litre,
    this.economyUnit = EconomyUnit.kmPerLitre,
    this.currencySymbol = defaultCurrencySymbol,
    this.themeMode = AppThemeMode.system,
    this.lastVehicleId,
  });

  /// Neutral default. The user sets their own in Settings; nothing in the app
  /// converts between currencies, so this is purely a display prefix.
  static const String defaultCurrencySymbol = r'$';

  static const AppSettings defaults = AppSettings();

  final DistanceUnit distanceUnit;
  final VolumeUnit volumeUnit;
  final EconomyUnit economyUnit;
  final String currencySymbol;
  final AppThemeMode themeMode;

  /// Which vehicle to reopen on launch.
  final int? lastVehicleId;

  static const Object _unset = Object();

  AppSettings copyWith({
    DistanceUnit? distanceUnit,
    VolumeUnit? volumeUnit,
    EconomyUnit? economyUnit,
    String? currencySymbol,
    AppThemeMode? themeMode,
    Object? lastVehicleId = _unset,
  }) {
    return AppSettings(
      distanceUnit: distanceUnit ?? this.distanceUnit,
      volumeUnit: volumeUnit ?? this.volumeUnit,
      economyUnit: economyUnit ?? this.economyUnit,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      themeMode: themeMode ?? this.themeMode,
      lastVehicleId: identical(lastVehicleId, _unset)
          ? this.lastVehicleId
          : lastVehicleId as int?,
    );
  }

  // --- key/value serialisation -------------------------------------------

  static const String keyDistanceUnit = 'distance_unit';
  static const String keyVolumeUnit = 'volume_unit';
  static const String keyEconomyUnit = 'economy_unit';
  static const String keyCurrencySymbol = 'currency_symbol';
  static const String keyThemeMode = 'theme_mode';
  static const String keyLastVehicleId = 'last_vehicle_id';

  Map<String, String> toMap() => {
        keyDistanceUnit: distanceUnit.name,
        keyVolumeUnit: volumeUnit.name,
        keyEconomyUnit: economyUnit.name,
        keyCurrencySymbol: currencySymbol,
        keyThemeMode: themeMode.key,
        keyLastVehicleId: lastVehicleId?.toString() ?? '',
      };

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      distanceUnit: _enumByName(
        DistanceUnit.values,
        map[keyDistanceUnit],
        DistanceUnit.kilometre,
      ),
      volumeUnit: _enumByName(
        VolumeUnit.values,
        map[keyVolumeUnit],
        VolumeUnit.litre,
      ),
      economyUnit: _enumByName(
        EconomyUnit.values,
        map[keyEconomyUnit],
        EconomyUnit.kmPerLitre,
      ),
      currencySymbol: map[keyCurrencySymbol] ?? defaultCurrencySymbol,
      themeMode: AppThemeMode.fromKey(map[keyThemeMode]),
      lastVehicleId: int.tryParse(map[keyLastVehicleId] ?? ''),
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.distanceUnit == distanceUnit &&
      other.volumeUnit == volumeUnit &&
      other.economyUnit == economyUnit &&
      other.currencySymbol == currencySymbol &&
      other.themeMode == themeMode &&
      other.lastVehicleId == lastVehicleId;

  @override
  int get hashCode => Object.hash(
        distanceUnit,
        volumeUnit,
        economyUnit,
        currencySymbol,
        themeMode,
        lastVehicleId,
      );
}
