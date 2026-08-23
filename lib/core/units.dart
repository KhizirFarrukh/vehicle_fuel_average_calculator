/// Unit systems and conversions.
///
/// Everything in this app is *stored* canonically as kilometres and litres.
/// Conversion happens only at the display edge, so the database never depends
/// on what the user happens to have selected in Settings today.
///
/// Pure Dart — no Flutter imports, so it is directly unit-testable.
library;

/// Exact, definitional conversion factors.
const double kKmPerMile = 1.609344;
const double kLitresPerUsGallon = 3.785411784;
const double kLitresPerImpGallon = 4.54609;

enum DistanceUnit {
  kilometre('km', 'Kilometres'),
  mile('mi', 'Miles');

  const DistanceUnit(this.symbol, this.label);

  final String symbol;
  final String label;
}

enum VolumeUnit {
  litre('L', 'Litres'),
  usGallon('gal (US)', 'US gallons'),
  impGallon('gal (imp)', 'Imperial gallons');

  const VolumeUnit(this.symbol, this.label);

  final String symbol;
  final String label;
}

enum EconomyUnit {
  kmPerLitre('km/L', 'Kilometres per litre'),
  litrePer100Km('L/100km', 'Litres per 100 km'),
  milesPerUsGallon('mpg (US)', 'Miles per US gallon'),
  milesPerImpGallon('mpg (imp)', 'Miles per imperial gallon');

  const EconomyUnit(this.symbol, this.label);

  final String symbol;
  final String label;

  /// `L/100km` is a *consumption* measure: a smaller number is a better car.
  /// Every other supported unit is an *efficiency* measure, where bigger wins.
  ///
  /// The engine always ranks internally in km/L, so this flag only ever
  /// affects wording, arrow direction and chart orientation.
  bool get lowerIsBetter => this == EconomyUnit.litrePer100Km;
}

// ---------------------------------------------------------------------------
// Distance
// ---------------------------------------------------------------------------

/// Canonical kilometres -> the user's chosen unit.
double distanceFromKm(double km, DistanceUnit unit) {
  switch (unit) {
    case DistanceUnit.kilometre:
      return km;
    case DistanceUnit.mile:
      return km / kKmPerMile;
  }
}

/// The user's chosen unit -> canonical kilometres.
double distanceToKm(double value, DistanceUnit unit) {
  switch (unit) {
    case DistanceUnit.kilometre:
      return value;
    case DistanceUnit.mile:
      return value * kKmPerMile;
  }
}

// ---------------------------------------------------------------------------
// Volume
// ---------------------------------------------------------------------------

/// Canonical litres -> the user's chosen unit.
double volumeFromLitres(double litres, VolumeUnit unit) {
  switch (unit) {
    case VolumeUnit.litre:
      return litres;
    case VolumeUnit.usGallon:
      return litres / kLitresPerUsGallon;
    case VolumeUnit.impGallon:
      return litres / kLitresPerImpGallon;
  }
}

/// The user's chosen unit -> canonical litres.
double volumeToLitres(double value, VolumeUnit unit) {
  switch (unit) {
    case VolumeUnit.litre:
      return value;
    case VolumeUnit.usGallon:
      return value * kLitresPerUsGallon;
    case VolumeUnit.impGallon:
      return value * kLitresPerImpGallon;
  }
}

// ---------------------------------------------------------------------------
// Economy
// ---------------------------------------------------------------------------

/// Canonical km/L -> the user's chosen economy unit.
///
/// Returns [double.infinity] when converting a zero km/L to [EconomyUnit.litrePer100Km],
/// which is mathematically what "burns fuel while covering no distance" means.
/// Callers that render this should check [double.isFinite] first; the shared
/// formatters already do.
double economyFromKmPerLitre(double kmPerLitre, EconomyUnit unit) {
  switch (unit) {
    case EconomyUnit.kmPerLitre:
      return kmPerLitre;
    case EconomyUnit.litrePer100Km:
      if (kmPerLitre == 0) return double.infinity;
      return 100.0 / kmPerLitre;
    case EconomyUnit.milesPerUsGallon:
      return kmPerLitre * (kLitresPerUsGallon / kKmPerMile);
    case EconomyUnit.milesPerImpGallon:
      return kmPerLitre * (kLitresPerImpGallon / kKmPerMile);
  }
}

/// The user's chosen economy unit -> canonical km/L.
double economyToKmPerLitre(double value, EconomyUnit unit) {
  switch (unit) {
    case EconomyUnit.kmPerLitre:
      return value;
    case EconomyUnit.litrePer100Km:
      if (value == 0) return double.infinity;
      return 100.0 / value;
    case EconomyUnit.milesPerUsGallon:
      return value * (kKmPerMile / kLitresPerUsGallon);
    case EconomyUnit.milesPerImpGallon:
      return value * (kKmPerMile / kLitresPerImpGallon);
  }
}

/// Cost per canonical kilometre -> cost per displayed distance unit.
double costPerDistanceFromPerKm(double costPerKm, DistanceUnit unit) {
  switch (unit) {
    case DistanceUnit.kilometre:
      return costPerKm;
    case DistanceUnit.mile:
      return costPerKm * kKmPerMile;
  }
}

/// Cost per canonical litre -> cost per displayed volume unit.
double costPerVolumeFromPerLitre(double costPerLitre, VolumeUnit unit) {
  switch (unit) {
    case VolumeUnit.litre:
      return costPerLitre;
    case VolumeUnit.usGallon:
      return costPerLitre * kLitresPerUsGallon;
    case VolumeUnit.impGallon:
      return costPerLitre * kLitresPerImpGallon;
  }
}

/// The economy unit that pairs naturally with a distance/volume choice.
///
/// Used to give a sensible default when the user flips distance to miles
/// without having thought about the economy readout yet.
EconomyUnit suggestedEconomyUnit(DistanceUnit distance, VolumeUnit volume) {
  if (distance == DistanceUnit.mile) {
    if (volume == VolumeUnit.impGallon) return EconomyUnit.milesPerImpGallon;
    return EconomyUnit.milesPerUsGallon;
  }
  return EconomyUnit.kmPerLitre;
}
