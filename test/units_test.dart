import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/core/unit_formatter.dart';
import 'package:vehicle_fuel_average_calculator/core/units.dart';
import 'package:vehicle_fuel_average_calculator/models/app_settings.dart';

void main() {
  group('distance', () {
    test('kilometres pass through untouched', () {
      expect(distanceFromKm(100, DistanceUnit.kilometre), 100);
      expect(distanceToKm(100, DistanceUnit.kilometre), 100);
    });

    test('miles convert both ways', () {
      expect(distanceFromKm(160.9344, DistanceUnit.mile), closeTo(100, 1e-9));
      expect(distanceToKm(100, DistanceUnit.mile), closeTo(160.9344, 1e-9));
    });

    test('round-trips', () {
      for (final unit in DistanceUnit.values) {
        expect(distanceToKm(distanceFromKm(1234.5, unit), unit),
            closeTo(1234.5, 1e-9));
      }
    });
  });

  group('volume', () {
    test('gallons convert both ways', () {
      expect(volumeToLitres(1, VolumeUnit.usGallon),
          closeTo(kLitresPerUsGallon, 1e-9));
      expect(volumeToLitres(1, VolumeUnit.impGallon),
          closeTo(kLitresPerImpGallon, 1e-9));
      expect(volumeFromLitres(kLitresPerUsGallon, VolumeUnit.usGallon),
          closeTo(1, 1e-9));
    });

    test('round-trips', () {
      for (final unit in VolumeUnit.values) {
        expect(volumeToLitres(volumeFromLitres(45.5, unit), unit),
            closeTo(45.5, 1e-9));
      }
    });
  });

  group('economy', () {
    test('L/100km is the reciprocal, scaled', () {
      expect(economyFromKmPerLitre(10, EconomyUnit.litrePer100Km),
          closeTo(10, 1e-9));
      expect(economyFromKmPerLitre(20, EconomyUnit.litrePer100Km),
          closeTo(5, 1e-9));
    });

    test('mpg uses the definitional factors', () {
      // 1 km/L = 3.785411784 / 1.609344 US mpg
      expect(
        economyFromKmPerLitre(1, EconomyUnit.milesPerUsGallon),
        closeTo(2.352145833, 1e-6),
      );
      expect(
        economyFromKmPerLitre(1, EconomyUnit.milesPerImpGallon),
        closeTo(2.824809363, 1e-6),
      );
    });

    test('round-trips through every unit', () {
      for (final unit in EconomyUnit.values) {
        final converted = economyFromKmPerLitre(14.7, unit);
        expect(economyToKmPerLitre(converted, unit), closeTo(14.7, 1e-9));
      }
    });

    test('zero km/L does not blow up L/100km', () {
      expect(
        economyFromKmPerLitre(0, EconomyUnit.litrePer100Km),
        double.infinity,
      );
    });

    test('only L/100km counts down', () {
      expect(EconomyUnit.litrePer100Km.lowerIsBetter, isTrue);
      expect(EconomyUnit.kmPerLitre.lowerIsBetter, isFalse);
      expect(EconomyUnit.milesPerUsGallon.lowerIsBetter, isFalse);
    });
  });

  group('cost conversions', () {
    test('cost per km becomes cost per mile', () {
      expect(
        costPerDistanceFromPerKm(1, DistanceUnit.mile),
        closeTo(kKmPerMile, 1e-9),
      );
    });

    test('cost per litre becomes cost per gallon', () {
      expect(
        costPerVolumeFromPerLitre(1, VolumeUnit.usGallon),
        closeTo(kLitresPerUsGallon, 1e-9),
      );
    });
  });

  group('suggested economy unit', () {
    test('follows the distance and volume choice', () {
      expect(
        suggestedEconomyUnit(DistanceUnit.kilometre, VolumeUnit.litre),
        EconomyUnit.kmPerLitre,
      );
      expect(
        suggestedEconomyUnit(DistanceUnit.mile, VolumeUnit.impGallon),
        EconomyUnit.milesPerImpGallon,
      );
      expect(
        suggestedEconomyUnit(DistanceUnit.mile, VolumeUnit.usGallon),
        EconomyUnit.milesPerUsGallon,
      );
    });
  });

  group('UnitFormatter', () {
    const metric = UnitFormatter(AppSettings());
    const imperial = UnitFormatter(AppSettings(
      distanceUnit: DistanceUnit.mile,
      volumeUnit: VolumeUnit.usGallon,
      economyUnit: EconomyUnit.milesPerUsGallon,
      currencySymbol: r'$',
    ));

    test('formats economy in the selected unit', () {
      expect(metric.economy(12.5), '12.50 km/L');
      expect(imperial.economy(12.5), '29.40 mpg (US)');
    });

    test('renders an em dash rather than a bogus zero', () {
      expect(metric.economy(null), '—');
      expect(metric.economy(0), '—');
      expect(metric.distance(null), '—');
    });

    test('parses input back into canonical units', () {
      expect(metric.parseDistanceToKm('1,234.5'), closeTo(1234.5, 1e-9));
      expect(imperial.parseDistanceToKm('100'), closeTo(160.9344, 1e-9));
      expect(imperial.parseVolumeToLitres('1'),
          closeTo(kLitresPerUsGallon, 1e-9));
    });

    test('field text round-trips through parsing', () {
      final text = imperial.distanceFieldText(160.9344);
      expect(imperial.parseDistanceToKm(text), closeTo(160.9344, 1e-4));
    });

    test('raw chart values skip the string formatting entirely', () {
      expect(metric.economyValue(12.5), closeTo(12.5, 1e-9));
      expect(imperial.economyValue(1), closeTo(2.352145833, 1e-6));
      expect(imperial.priceValue(1), closeTo(kLitresPerUsGallon, 1e-9));
    });

    test('price and cost strings carry the right unit', () {
      expect(metric.pricePerVolume(2.5), r'$2.50/L');
      expect(metric.costPerDistance(0.21), r'$0.21/km');
    });
  });
}
