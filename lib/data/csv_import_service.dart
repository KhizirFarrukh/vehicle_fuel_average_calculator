/// CSV import (I23).
///
/// Reads this app's own CSV export and, as far as headers allow, exports from
/// other fuel trackers. Pure Dart — no Flutter, no I/O — so the parsing and
/// column-matching are directly unit-testable.
library;

import '../core/units.dart';
import '../core/validators.dart';
import '../models/fuel_entry.dart';

/// A column this importer knows how to use.
enum CsvField {
  date('Date'),
  odometer('Odometer'),
  trip('Trip meter'),
  volume('Volume'),
  totalCost('Total cost'),
  pricePerUnit('Price per unit'),
  fullTank('Full tank'),
  missedFillUp('Missed fill-up'),
  station('Station'),
  notes('Notes');

  const CsvField(this.label);

  final String label;

  /// Without these, a row cannot become an entry.
  static const List<CsvField> required = [
    CsvField.date,
    CsvField.odometer,
    CsvField.volume,
  ];
}

/// Header spellings seen in this app's export and in common alternatives.
/// Compared after lowercasing and stripping everything but letters and digits,
/// so `Odometer (km)` and `odometer_km` both land on `odometerkm`.
const Map<CsvField, List<String>> _headerAliases = {
  CsvField.date: [
    'date', 'filldate', 'dateoffillup', 'fillupdate', 'day', 'datetime',
    'fueldate', 'when',
  ],
  CsvField.odometer: [
    'odometer', 'odometerkm', 'odometermi', 'odometerreading', 'odo', 'odokm',
    'mileage', 'kilometers', 'kilometres', 'miles', 'totaldistance', 'reading',
  ],
  CsvField.trip: [
    'trip', 'tripkm', 'tripmi', 'tripmeter', 'tripdistance', 'distance',
    'tripodometer',
  ],
  CsvField.volume: [
    'volume', 'volumel', 'volumegal', 'volumelitres', 'volumeliters',
    'amountrefilled', 'litres', 'liters', 'gallons', 'quantity', 'fuelamount',
    'fuelvolume', 'amount', 'fuel',
  ],
  CsvField.totalCost: [
    'totalcost', 'total', 'cost', 'totalprice', 'amountpaid', 'totalspent',
    'paid',
  ],
  CsvField.pricePerUnit: [
    'priceperlitre', 'priceperliter', 'pricepergallon', 'priceperunit',
    'unitprice', 'pricepervolume', 'fuelprice', 'rate', 'ppl', 'price',
  ],
  CsvField.fullTank: [
    'fulltank', 'full', 'filledup', 'isfulltank', 'tankfull', 'fillup',
  ],
  CsvField.missedFillUp: [
    'missedfillup', 'missed', 'missedfill', 'skipped', 'previousmissed',
  ],
  CsvField.station: [
    'station', 'fuelstation', 'gasstation', 'location', 'place', 'vendor',
    'servicestation',
  ],
  CsvField.notes: [
    'notes', 'note', 'comment', 'comments', 'remarks', 'description',
  ],
};

/// One CSV line, parsed but not yet committed.
class CsvRowDraft {
  const CsvRowDraft({
    required this.lineNumber,
    required this.entry,
    required this.problems,
  });

  /// 1-based line number in the source, for error messages.
  final int lineNumber;

  /// Null when the row could not be turned into an entry at all.
  final FuelEntry? entry;

  /// Why it was skipped, or what was assumed.
  final List<String> problems;

  bool get isUsable => entry != null;
}

/// The result of reading a CSV file, before anything is written.
class CsvImportPreview {
  const CsvImportPreview({
    required this.headers,
    required this.mapping,
    required this.drafts,
    required this.fatalError,
  });

  final List<String> headers;

  /// Which column index each recognised field came from.
  final Map<CsvField, int> mapping;

  final List<CsvRowDraft> drafts;

  /// Set when the file could not be read at all; [drafts] is then empty.
  final String? fatalError;

  bool get isValid => fatalError == null && usable.isNotEmpty;

  List<CsvRowDraft> get usable =>
      drafts.where((d) => d.isUsable).toList(growable: false);

  List<CsvRowDraft> get skipped =>
      drafts.where((d) => !d.isUsable).toList(growable: false);

  List<CsvField> get missingRequired =>
      CsvField.required.where((f) => !mapping.containsKey(f)).toList();

  List<CsvField> get recognisedFields => mapping.keys.toList(growable: false);
}

/// How the numbers in the file should be interpreted.
class CsvImportOptions {
  const CsvImportOptions({
    this.distanceUnit = DistanceUnit.kilometre,
    this.volumeUnit = VolumeUnit.litre,
    this.dayFirst = true,
    this.defaultFullTank = true,
  });

  /// The units the *file* is written in — not the reader's display units. An
  /// export from a US app is in miles and gallons whatever this app shows.
  final DistanceUnit distanceUnit;
  final VolumeUnit volumeUnit;

  /// Whether `03/04/2026` means 3 April or 4 March. There is no way to detect
  /// this reliably, so it is asked rather than guessed.
  final bool dayFirst;

  /// Applied to rows with no full-tank column. Most logs are full-tank fills,
  /// and the alternative — treating everything as partial — would yield no
  /// averages at all.
  final bool defaultFullTank;
}

class CsvImportService {
  const CsvImportService._();

  /// Reads [source] and reports what would be imported, writing nothing.
  static CsvImportPreview preview(
    String source,
    int vehicleId, {
    CsvImportOptions options = const CsvImportOptions(),
  }) {
    final rows = parseCsv(source);

    if (rows.isEmpty) {
      return const CsvImportPreview(
        headers: [],
        mapping: {},
        drafts: [],
        fatalError: 'The file is empty.',
      );
    }

    final headers = rows.first;
    final mapping = matchHeaders(headers);

    final missing = CsvField.required.where((f) => !mapping.containsKey(f));
    if (missing.isNotEmpty) {
      return CsvImportPreview(
        headers: headers,
        mapping: mapping,
        drafts: const [],
        fatalError: 'No column found for '
            '${missing.map((f) => f.label.toLowerCase()).join(', ')}. '
            'The first line of the file must be a header row.',
      );
    }

    final drafts = <CsvRowDraft>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      // A trailing blank line is not worth complaining about.
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      drafts.add(_readRow(row, i + 1, mapping, vehicleId, options));
    }

    return CsvImportPreview(
      headers: headers,
      mapping: mapping,
      drafts: drafts,
      fatalError: drafts.isEmpty ? 'No data rows found below the header.' : null,
    );
  }

  static CsvRowDraft _readRow(
    List<String> row,
    int lineNumber,
    Map<CsvField, int> mapping,
    int vehicleId,
    CsvImportOptions options,
  ) {
    final problems = <String>[];

    String? cell(CsvField field) {
      final index = mapping[field];
      if (index == null || index >= row.length) return null;
      final value = row[index].trim();
      return value.isEmpty ? null : value;
    }

    final date = parseDate(cell(CsvField.date), dayFirst: options.dayFirst);
    if (date == null) {
      problems.add('Could not read the date.');
    }

    final odometerRaw = parseFlexibleDouble(cell(CsvField.odometer));
    if (odometerRaw == null) {
      problems.add('Could not read the odometer reading.');
    }

    final volumeRaw = parseFlexibleDouble(cell(CsvField.volume));
    if (volumeRaw == null || volumeRaw <= 0) {
      problems.add('Could not read a positive fuel amount.');
    }

    if (date == null || odometerRaw == null || volumeRaw == null || volumeRaw <= 0) {
      return CsvRowDraft(
        lineNumber: lineNumber,
        entry: null,
        problems: problems,
      );
    }

    final odometerKm = distanceToKm(odometerRaw, options.distanceUnit);
    final volumeLitres = volumeToLitres(volumeRaw, options.volumeUnit);

    // Cost may be given as a total, as a unit price, or not at all.
    var totalCost = parseFlexibleDouble(cell(CsvField.totalCost));
    final unitPrice = parseFlexibleDouble(cell(CsvField.pricePerUnit));
    if (totalCost == null && unitPrice != null) {
      totalCost = unitPrice * volumeRaw;
    }
    if (totalCost == null) {
      totalCost = 0;
      problems.add('No cost column; recorded as zero.');
    }

    final tripRaw = parseFlexibleDouble(cell(CsvField.trip));

    return CsvRowDraft(
      lineNumber: lineNumber,
      entry: FuelEntry(
        vehicleId: vehicleId,
        filledAt: date,
        odometer: odometerKm,
        tripMeter:
            tripRaw == null ? null : distanceToKm(tripRaw, options.distanceUnit),
        volume: volumeLitres,
        totalCost: totalCost,
        isFullTank:
            parseBoolean(cell(CsvField.fullTank)) ?? options.defaultFullTank,
        missedFillUp: parseBoolean(cell(CsvField.missedFillUp)) ?? false,
        station: cell(CsvField.station),
        notes: cell(CsvField.notes),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      problems: problems,
    );
  }

  // -------------------------------------------------------------------------
  // Parsing primitives
  // -------------------------------------------------------------------------

  /// RFC 4180-style CSV: quoted fields may contain commas, newlines and
  /// doubled quotes.
  static List<List<String>> parseCsv(String input) {
    final normalised = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var index = 0;

    while (index < normalised.length) {
      final char = normalised[index];

      if (inQuotes) {
        if (char == '"') {
          // A doubled quote inside a quoted field is a literal quote.
          if (index + 1 < normalised.length && normalised[index + 1] == '"') {
            field.write('"');
            index += 2;
            continue;
          }
          inQuotes = false;
          index++;
          continue;
        }
        field.write(char);
        index++;
        continue;
      }

      if (char == '"') {
        inQuotes = true;
        index++;
        continue;
      }
      if (char == ',') {
        row.add(field.toString());
        field.clear();
        index++;
        continue;
      }
      if (char == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
        index++;
        continue;
      }

      field.write(char);
      index++;
    }

    // Whatever is left after the final newline, if anything.
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }

    return rows;
  }

  /// Lowercases and drops everything that is not a letter or digit, so header
  /// punctuation and spacing stop mattering.
  static String normaliseHeader(String header) =>
      header.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// Maps recognised header columns to their index. The first match wins, so a
  /// file with both `Price` and `Price per litre` keeps the more specific one
  /// only if it appears first — which is why the alias lists put specific
  /// spellings ahead of vague ones.
  static Map<CsvField, int> matchHeaders(List<String> headers) {
    final mapping = <CsvField, int>{};
    final normalised = headers.map(normaliseHeader).toList();

    for (final entry in _headerAliases.entries) {
      for (final alias in entry.value) {
        final index = normalised.indexOf(alias);
        if (index != -1 && !mapping.containsValue(index)) {
          mapping[entry.key] = index;
          break;
        }
      }
    }

    return mapping;
  }

  /// `yes`, `y`, `true`, `1`, `full` are true; `no`, `n`, `false`, `0`,
  /// `partial` are false; anything else is null so a default can apply.
  static bool? parseBoolean(String? raw) {
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case 'yes':
      case 'y':
      case 'true':
      case 't':
      case '1':
      case 'full':
        return true;
      case 'no':
      case 'n':
      case 'false':
      case 'f':
      case '0':
      case 'partial':
        return false;
      default:
        return null;
    }
  }

  static const List<String> _monthNames = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// Accepts ISO 8601, `23 Aug 2026`, `Aug 23 2026`, and numeric forms with
  /// `/`, `-` or `.` separators.
  ///
  /// [dayFirst] resolves the `03/04/2026` ambiguity. A four-digit first
  /// component is always read as a year regardless.
  static DateTime? parseDate(String? raw, {bool dayFirst = true}) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    // ISO 8601 and anything else DateTime understands natively.
    final iso = DateTime.tryParse(text);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    // Month-name forms, in either order.
    final named = RegExp(
      r'^(\d{1,2})[\s\-/]+([a-zA-Z]{3,})[\s\-/]+(\d{2,4})$',
    ).firstMatch(text);
    if (named != null) {
      final month = _monthFromName(named.group(2)!);
      if (month != null) {
        return _build(
          int.parse(named.group(3)!),
          month,
          int.parse(named.group(1)!),
        );
      }
    }

    final namedFirst = RegExp(
      r'^([a-zA-Z]{3,})[\s\-/]+(\d{1,2}),?[\s\-/]+(\d{2,4})$',
    ).firstMatch(text);
    if (namedFirst != null) {
      final month = _monthFromName(namedFirst.group(1)!);
      if (month != null) {
        return _build(
          int.parse(namedFirst.group(3)!),
          month,
          int.parse(namedFirst.group(2)!),
        );
      }
    }

    // Purely numeric, three components. Strip any trailing time.
    final numeric = RegExp(
      r'^(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{1,4})',
    ).firstMatch(text);
    if (numeric == null) return null;

    final first = int.parse(numeric.group(1)!);
    final second = int.parse(numeric.group(2)!);
    final third = int.parse(numeric.group(3)!);

    // A four-digit leading component can only be a year.
    if (numeric.group(1)!.length == 4) return _build(first, second, third);

    return dayFirst
        ? _build(third, second, first)
        : _build(third, first, second);
  }

  static int? _monthFromName(String name) {
    final key = name.toLowerCase();
    for (var i = 0; i < _monthNames.length; i++) {
      if (key.startsWith(_monthNames[i])) return i + 1;
    }
    return null;
  }

  /// Rejects impossible components rather than letting [DateTime] roll them
  /// over — month 13 silently becoming January of the next year would turn a
  /// misread column into plausible-looking data.
  static DateTime? _build(int year, int month, int day) {
    var fullYear = year;
    if (fullYear < 100) fullYear += fullYear < 70 ? 2000 : 1900;

    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;

    final date = DateTime(fullYear, month, day);
    if (date.month != month || date.day != day) return null; // e.g. 31 Feb
    return date;
  }
}
