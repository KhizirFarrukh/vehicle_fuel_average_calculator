import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/core/units.dart';
import 'package:vehicle_fuel_average_calculator/data/csv_import_service.dart';

void main() {
  group('parseCsv', () {
    test('splits plain rows', () {
      final rows = CsvImportService.parseCsv('a,b,c\n1,2,3');
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('handles CRLF and a trailing newline', () {
      final rows = CsvImportService.parseCsv('a,b\r\n1,2\r\n');
      expect(rows, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('quoted fields may contain commas', () {
      final rows = CsvImportService.parseCsv('a,b\n"one, two",3');
      expect(rows[1], ['one, two', '3']);
    });

    test('doubled quotes become a literal quote', () {
      final rows = CsvImportService.parseCsv('a\n"He said ""hi"""');
      expect(rows[1], ['He said "hi"']);
    });

    test('quoted fields may contain newlines', () {
      final rows = CsvImportService.parseCsv('a,b\n"line one\nline two",3');
      expect(rows, hasLength(2));
      expect(rows[1], ['line one\nline two', '3']);
    });

    test('empty fields are preserved', () {
      final rows = CsvImportService.parseCsv('a,b,c\n1,,3');
      expect(rows[1], ['1', '', '3']);
    });

    test('an empty input yields nothing', () {
      expect(CsvImportService.parseCsv(''), isEmpty);
    });
  });

  group('header matching', () {
    test('ignores case, spacing and punctuation', () {
      final mapping = CsvImportService.matchHeaders([
        'Date',
        'Odometer (km)',
        'Volume (L)',
        'Total cost',
      ]);

      expect(mapping[CsvField.date], 0);
      expect(mapping[CsvField.odometer], 1);
      expect(mapping[CsvField.volume], 2);
      expect(mapping[CsvField.totalCost], 3);
    });

    test('reads this app\'s own export header', () {
      final mapping = CsvImportService.matchHeaders([
        'Vehicle', 'Make', 'Model', 'Variant', 'Year', 'Licence plate',
        'Date', 'Odometer (km)', 'Trip (km)', 'Volume (L)', 'Total cost',
        'Price per litre', 'Full tank', 'Missed fill-up', 'Station', 'Notes',
      ]);

      expect(mapping[CsvField.date], 6);
      expect(mapping[CsvField.odometer], 7);
      expect(mapping[CsvField.trip], 8);
      expect(mapping[CsvField.volume], 9);
      expect(mapping[CsvField.totalCost], 10);
      expect(mapping[CsvField.pricePerUnit], 11);
      expect(mapping[CsvField.fullTank], 12);
      expect(mapping[CsvField.missedFillUp], 13);
      expect(mapping[CsvField.station], 14);
      expect(mapping[CsvField.notes], 15);
    });

    test('recognises US-style headers', () {
      final mapping = CsvImportService.matchHeaders([
        'Date', 'Miles', 'Gallons', 'Price per gallon',
      ]);

      expect(mapping[CsvField.odometer], 1);
      expect(mapping[CsvField.volume], 2);
      expect(mapping[CsvField.pricePerUnit], 3);
    });

    test('no two fields claim the same column', () {
      final mapping = CsvImportService.matchHeaders(['Date', 'Odo', 'Fuel']);
      final indices = mapping.values.toList();
      expect(indices.toSet().length, indices.length);
    });

    test('unknown headers are simply not mapped', () {
      final mapping = CsvImportService.matchHeaders(['Alpha', 'Beta']);
      expect(mapping, isEmpty);
    });
  });

  group('parseDate', () {
    test('ISO 8601', () {
      expect(CsvImportService.parseDate('2026-08-23'), DateTime(2026, 8, 23));
      expect(
        CsvImportService.parseDate('2026-08-23 14:05:00'),
        DateTime(2026, 8, 23),
      );
    });

    test('day-first and month-first numeric forms', () {
      expect(
        CsvImportService.parseDate('03/04/2026', dayFirst: true),
        DateTime(2026, 4, 3),
      );
      expect(
        CsvImportService.parseDate('03/04/2026', dayFirst: false),
        DateTime(2026, 3, 4),
      );
    });

    test('a four-digit leading component is always the year', () {
      expect(
        CsvImportService.parseDate('2026/08/23', dayFirst: false),
        DateTime(2026, 8, 23),
      );
    });

    test('month names in either order', () {
      expect(CsvImportService.parseDate('23 Aug 2026'), DateTime(2026, 8, 23));
      expect(CsvImportService.parseDate('23 August 2026'), DateTime(2026, 8, 23));
      expect(CsvImportService.parseDate('Aug 23, 2026'), DateTime(2026, 8, 23));
    });

    test('two-digit years', () {
      expect(CsvImportService.parseDate('23/08/26'), DateTime(2026, 8, 23));
      expect(CsvImportService.parseDate('23/08/98'), DateTime(1998, 8, 23));
    });

    test('impossible dates are rejected rather than rolled over', () {
      // Month 13 must not quietly become January of the next year.
      expect(CsvImportService.parseDate('23/13/2026'), isNull);
      expect(CsvImportService.parseDate('31/02/2026'), isNull);
      expect(CsvImportService.parseDate('not a date'), isNull);
      expect(CsvImportService.parseDate(null), isNull);
    });
  });

  group('parseBoolean', () {
    test('recognises the usual spellings', () {
      expect(CsvImportService.parseBoolean('yes'), isTrue);
      expect(CsvImportService.parseBoolean('TRUE'), isTrue);
      expect(CsvImportService.parseBoolean('1'), isTrue);
      expect(CsvImportService.parseBoolean('no'), isFalse);
      expect(CsvImportService.parseBoolean('0'), isFalse);
      expect(CsvImportService.parseBoolean('partial'), isFalse);
    });

    test('returns null for anything else, so a default can apply', () {
      expect(CsvImportService.parseBoolean('maybe'), isNull);
      expect(CsvImportService.parseBoolean(null), isNull);
    });
  });

  group('preview', () {
    test('reads a straightforward metric file', () {
      const csv = 'Date,Odometer (km),Volume (L),Total cost\n'
          '2026-01-04,12500,32.5,8125\n'
          '2026-01-19,12930,30,7500\n';

      final preview = CsvImportService.preview(csv, 7);

      expect(preview.fatalError, isNull);
      expect(preview.isValid, isTrue);
      expect(preview.usable, hasLength(2));
      expect(preview.skipped, isEmpty);

      final first = preview.usable.first.entry!;
      expect(first.vehicleId, 7);
      expect(first.filledAt, DateTime(2026, 1, 4));
      expect(first.odometer, 12500);
      expect(first.volume, 32.5);
      expect(first.totalCost, 8125);
      expect(first.isFullTank, isTrue);
    });

    test('converts from the units the file is written in', () {
      const csv = 'Date,Odometer,Volume,Total cost\n'
          '2026-01-04,100,10,40\n';

      final preview = CsvImportService.preview(
        csv,
        1,
        options: const CsvImportOptions(
          distanceUnit: DistanceUnit.mile,
          volumeUnit: VolumeUnit.usGallon,
        ),
      );

      final entry = preview.usable.single.entry!;
      expect(entry.odometer, closeTo(160.9344, 1e-6));
      expect(entry.volume, closeTo(37.85411784, 1e-6));
      // Money is never converted.
      expect(entry.totalCost, 40);
    });

    test('derives the total from a unit price when there is no total', () {
      const csv = 'Date,Odometer,Volume,Price per litre\n'
          '2026-01-04,12500,30,250\n';

      final preview = CsvImportService.preview(csv, 1);
      expect(preview.usable.single.entry!.totalCost, closeTo(7500, 1e-9));
    });

    test('records zero cost, with a note, when no cost column exists', () {
      const csv = 'Date,Odometer,Volume\n2026-01-04,12500,30\n';

      final draft = CsvImportService.preview(csv, 1).usable.single;
      expect(draft.entry!.totalCost, 0);
      expect(draft.problems.single, contains('No cost column'));
    });

    test('reads the full-tank and missed-fill columns', () {
      const csv = 'Date,Odometer,Volume,Total cost,Full tank,Missed fill-up\n'
          '2026-01-04,12500,30,7500,yes,no\n'
          '2026-01-10,12700,10,2500,no,yes\n';

      final entries =
          CsvImportService.preview(csv, 1).usable.map((d) => d.entry!).toList();

      expect(entries[0].isFullTank, isTrue);
      expect(entries[0].missedFillUp, isFalse);
      expect(entries[1].isFullTank, isFalse);
      expect(entries[1].missedFillUp, isTrue);
    });

    test('the full-tank default applies only where the column is absent', () {
      const csv = 'Date,Odometer,Volume,Total cost\n2026-01-04,12500,30,7500\n';

      final asPartial = CsvImportService.preview(
        csv,
        1,
        options: const CsvImportOptions(defaultFullTank: false),
      );
      expect(asPartial.usable.single.entry!.isFullTank, isFalse);
    });

    test('bad rows are skipped with a reason, good rows still import', () {
      const csv = 'Date,Odometer,Volume,Total cost\n'
          '2026-01-04,12500,32.5,8125\n'
          'rubbish,also rubbish,,\n'
          '2026-01-19,12930,30,7500\n';

      final preview = CsvImportService.preview(csv, 1);

      expect(preview.usable, hasLength(2));
      expect(preview.skipped, hasLength(1));
      expect(preview.skipped.single.lineNumber, 3);
      expect(preview.skipped.single.problems, isNotEmpty);
      expect(preview.isValid, isTrue);
    });

    test('a zero or negative volume is not importable', () {
      const csv = 'Date,Odometer,Volume,Total cost\n2026-01-04,12500,0,0\n';
      final preview = CsvImportService.preview(csv, 1);
      expect(preview.usable, isEmpty);
      expect(preview.skipped.single.problems.first, contains('fuel amount'));
    });

    test('blank lines are ignored rather than reported as errors', () {
      const csv = 'Date,Odometer,Volume,Total cost\n'
          '2026-01-04,12500,32.5,8125\n'
          '\n'
          ',,,\n';

      final preview = CsvImportService.preview(csv, 1);
      expect(preview.usable, hasLength(1));
      expect(preview.skipped, isEmpty);
    });

    test('a missing required column fails before anything is read', () {
      const csv = 'Date,Volume,Total cost\n2026-01-04,32.5,8125\n';

      final preview = CsvImportService.preview(csv, 1);
      expect(preview.isValid, isFalse);
      expect(preview.fatalError, contains('odometer'));
      expect(preview.missingRequired, contains(CsvField.odometer));
      expect(preview.drafts, isEmpty);
    });

    test('an empty file reports so', () {
      final preview = CsvImportService.preview('', 1);
      expect(preview.fatalError, 'The file is empty.');
    });

    test('a header with no data rows reports so', () {
      final preview =
          CsvImportService.preview('Date,Odometer,Volume\n', 1);
      expect(preview.fatalError, contains('No data rows'));
    });

    test('quoted notes survive the round trip from our own export', () {
      const csv = 'Date,Odometer (km),Volume (L),Total cost,Station,Notes\n'
          '2026-01-04,12500,32.5,8125,Shell,"Long trip, motorway"\n';

      final entry = CsvImportService.preview(csv, 1).usable.single.entry!;
      expect(entry.station, 'Shell');
      expect(entry.notes, 'Long trip, motorway');
    });
  });
}
