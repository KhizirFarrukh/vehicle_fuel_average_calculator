import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../core/unit_formatter.dart';
import '../core/units.dart';
import '../data/settings_dao.dart';
import '../models/app_settings.dart';

/// Holds user preferences and hands out the [UnitFormatter] every screen uses.
class SettingsController extends ChangeNotifier {
  SettingsController(this._dao);

  final SettingsDao _dao;

  AppSettings _settings = AppSettings.defaults;
  bool _loading = true;

  AppSettings get settings => _settings;
  bool get isLoading => _loading;

  /// Rebuilt on every change, so widgets that hold one never format with
  /// stale units.
  UnitFormatter get formatter => UnitFormatter(_settings);

  ThemeMode get themeMode {
    switch (_settings.themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    try {
      _settings = await _dao.load();
    } catch (_) {
      // A settings read failure should never stop the app starting; defaults
      // are perfectly usable.
      _settings = AppSettings.defaults;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _apply(AppSettings next) async {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    await _dao.save(next);
  }

  /// Changing the distance or volume unit also moves the economy readout to
  /// the matching one, unless the user has already picked something specific.
  Future<void> setDistanceUnit(DistanceUnit unit) async {
    final suggested = suggestedEconomyUnit(unit, _settings.volumeUnit);
    await _apply(_settings.copyWith(
      distanceUnit: unit,
      economyUnit: suggested,
    ));
  }

  Future<void> setVolumeUnit(VolumeUnit unit) async {
    final suggested = suggestedEconomyUnit(_settings.distanceUnit, unit);
    await _apply(_settings.copyWith(
      volumeUnit: unit,
      economyUnit: suggested,
    ));
  }

  Future<void> setEconomyUnit(EconomyUnit unit) =>
      _apply(_settings.copyWith(economyUnit: unit));

  Future<void> setCurrencySymbol(String symbol) =>
      _apply(_settings.copyWith(currencySymbol: symbol));

  Future<void> setThemeMode(AppThemeMode mode) =>
      _apply(_settings.copyWith(themeMode: mode));

  Future<void> setLastVehicleId(int? id) =>
      _apply(_settings.copyWith(lastVehicleId: id));

  /// After a restore, settings in the database have been replaced wholesale.
  Future<void> reload() async {
    _settings = await _dao.load();
    notifyListeners();
  }
}
