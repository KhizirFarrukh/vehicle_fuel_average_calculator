/// Turns canonical values (km, litres) into strings in the user's chosen
/// units, and turns typed input back into canonical values.
///
/// Every screen formats through this one object, so a change in Settings can
/// never leave half the app in the old units. Pure Dart.
library;

import '../models/app_settings.dart';
import 'formatters.dart';
import 'units.dart';
import 'validators.dart';

class UnitFormatter {
  const UnitFormatter(this.settings);

  final AppSettings settings;

  DistanceUnit get distanceUnit => settings.distanceUnit;
  VolumeUnit get volumeUnit => settings.volumeUnit;
  EconomyUnit get economyUnit => settings.economyUnit;
  String get currency => settings.currencySymbol;

  String get distanceSymbol => distanceUnit.symbol;
  String get volumeSymbol => volumeUnit.symbol;
  String get economySymbol => economyUnit.symbol;

  // --- display -----------------------------------------------------------

  /// Canonical km/L rendered in the chosen economy unit, e.g. `14.2 km/L`.
  String economy(double? kmPerLitre, {bool withUnit = true, int decimals = 2}) {
    if (kmPerLitre == null || kmPerLitre <= 0) return kEmDash;
    final value = economyFromKmPerLitre(kmPerLitre, economyUnit);
    if (!value.isFinite) return kEmDash;
    return withUnit
        ? formatWithUnit(value, economySymbol, decimals: decimals)
        : formatNumber(value, decimals: decimals);
  }

  String distance(double? km, {bool withUnit = true, int decimals = 0}) {
    if (km == null) return kEmDash;
    final value = distanceFromKm(km, distanceUnit);
    return withUnit
        ? formatWithUnit(value, distanceSymbol, decimals: decimals)
        : formatNumber(value, decimals: decimals);
  }

  String volume(double? litres, {bool withUnit = true, int decimals = 2}) {
    if (litres == null) return kEmDash;
    final value = volumeFromLitres(litres, volumeUnit);
    return withUnit
        ? formatWithUnit(value, volumeSymbol, decimals: decimals)
        : formatNumber(value, decimals: decimals);
  }

  String money(double? amount, {int decimals = 2}) =>
      formatCurrency(amount, currency, decimals: decimals);

  /// `$2.85/L`
  String pricePerVolume(double? perLitre, {int decimals = 2}) {
    if (perLitre == null || !perLitre.isFinite) return kEmDash;
    final value = costPerVolumeFromPerLitre(perLitre, volumeUnit);
    return '${money(value, decimals: decimals)}/$volumeSymbol';
  }

  /// `$0.21/km`
  String costPerDistance(double? perKm, {int decimals = 2}) {
    if (perKm == null || !perKm.isFinite) return kEmDash;
    final value = costPerDistanceFromPerKm(perKm, distanceUnit);
    return '${money(value, decimals: decimals)}/$distanceSymbol';
  }

  /// `$21.40/100 km` — easier to read than a fraction of a cent per km.
  String costPer100Distance(double? perKm, {int decimals = 2}) {
    if (perKm == null || !perKm.isFinite) return kEmDash;
    final value = costPerDistanceFromPerKm(perKm, distanceUnit) * 100;
    return '${money(value, decimals: decimals)}/100 $distanceSymbol';
  }

  // --- raw values ---------------------------------------------------------
  // Charts need numbers, not strings. Going through the formatted text and
  // parsing it back would lose precision and break on grouped thousands.

  /// Canonical km/L as a plain number in the chosen economy unit.
  double economyValue(double kmPerLitre) =>
      economyFromKmPerLitre(kmPerLitre, economyUnit);

  /// Canonical km as a plain number in the chosen distance unit.
  double distanceValue(double km) => distanceFromKm(km, distanceUnit);

  /// Canonical litres as a plain number in the chosen volume unit.
  double volumeValue(double litres) => volumeFromLitres(litres, volumeUnit);

  /// Canonical cost-per-litre as a plain number per chosen volume unit.
  double priceValue(double perLitre) =>
      costPerVolumeFromPerLitre(perLitre, volumeUnit);

  // --- input -------------------------------------------------------------

  /// Field text (in display units) -> canonical kilometres.
  double? parseDistanceToKm(String? text) {
    final value = parseNumber(text);
    if (value == null) return null;
    return distanceToKm(value, distanceUnit);
  }

  /// Field text (in display units) -> canonical litres.
  double? parseVolumeToLitres(String? text) {
    final value = parseNumber(text);
    if (value == null) return null;
    return volumeToLitres(value, volumeUnit);
  }

  /// Canonical km -> the text to seed a distance field with.
  String distanceFieldText(double? km) {
    if (km == null) return '';
    return formatCompactNumber(distanceFromKm(km, distanceUnit));
  }

  /// Canonical litres -> the text to seed a volume field with.
  String volumeFieldText(double? litres) {
    if (litres == null) return '';
    return formatCompactNumber(volumeFromLitres(litres, volumeUnit));
  }

  /// Shared lenient parse, so callers do not each roll their own.
  static double? parseNumber(String? text) => parseFlexibleDouble(text);
}
