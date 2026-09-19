import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/formatters.dart';
import '../models/app_settings.dart';
import '../models/fuel_entry.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';
import 'fuel_entry_dao.dart';
import 'service_dao.dart';
import 'settings_dao.dart';
import 'vehicle_dao.dart';

/// How a restore should treat data that is already in the database.
enum RestoreMode {
  /// Wipe the garage, then load the backup. The backup becomes the truth.
  replace,

  /// Keep what is there and add the backup's vehicles alongside it.
  merge,
}

class RestoreResult {
  const RestoreResult({
    required this.vehiclesAdded,
    required this.entriesAdded,
    required this.servicesAdded,
    required this.settingsRestored,
  });

  final int vehiclesAdded;
  final int entriesAdded;
  final int servicesAdded;
  final bool settingsRestored;
}

/// One vehicle's worth of a backup, parsed but not yet written.
class _ParsedVehicle {
  const _ParsedVehicle({
    required this.vehicle,
    required this.entries,
    required this.services,
  });

  final Vehicle vehicle;
  final List<FuelEntry> entries;
  final List<ServiceRecord> services;
}

/// JSON backup/restore and CSV export (I14).
///
/// No cloud, no account: the file lands in the app's documents directory and
/// the user is shown the path. Everything the app knows is in that one file.
class BackupService {
  const BackupService({
    required VehicleDao vehicles,
    required FuelEntryDao entries,
    required ServiceDao services,
    required SettingsDao settings,
  })  : _vehicles = vehicles,
        _entries = entries,
        _services = services,
        _settings = settings;

  final VehicleDao _vehicles;
  final FuelEntryDao _entries;
  final ServiceDao _services;
  final SettingsDao _settings;

  /// Identifies our own backups, so a stray JSON file is rejected with a clear
  /// message rather than a cast error.
  static const String formatId = 'vehicle_fuel_average_calculator.backup';

  /// v2 added the per-vehicle `services` array. v1 backups still restore —
  /// they simply carry no maintenance history.
  static const int formatVersion = 2;

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  Future<Map<String, Object?>> buildBackup() async {
    final vehicles = await _vehicles.getAll(includeArchived: true);
    final allEntries = await _entries.getAll();
    final allServices = await _services.getAll();
    final settings = await _settings.readAll();

    final grouped = <int, List<FuelEntry>>{};
    for (final entry in allEntries) {
      grouped.putIfAbsent(entry.vehicleId, () => <FuelEntry>[]).add(entry);
    }

    final groupedServices = <int, List<ServiceRecord>>{};
    for (final record in allServices) {
      groupedServices
          .putIfAbsent(record.vehicleId, () => <ServiceRecord>[])
          .add(record);
    }

    return {
      'format': formatId,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'units': 'Distances in kilometres, volumes in litres.',
      'settings': settings,
      'vehicles': [
        for (final vehicle in vehicles)
          {
            ...vehicle.toMap(),
            'entries': [
              for (final entry in grouped[vehicle.id] ?? const <FuelEntry>[])
                entry.toMap(),
            ],
            'services': [
              for (final record
                  in groupedServices[vehicle.id] ?? const <ServiceRecord>[])
                record.toMap(),
            ],
          },
      ],
    };
  }

  Future<String> exportJsonString() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(await buildBackup());
  }

  /// Writes the backup and returns the file path.
  Future<String> exportJsonFile() async {
    final content = await exportJsonString();
    final name = 'fuel-backup-${formatFileStamp(DateTime.now())}.json';
    return _write(name, content);
  }

  /// Every entry, one row each, with the vehicle spelled out.
  ///
  /// Values are in canonical units regardless of display settings — a CSV that
  /// silently changed units between exports would be worthless.
  Future<String> exportCsvString({int? vehicleId}) async {
    final vehicles = await _vehicles.getAll(includeArchived: true);
    final byId = {for (final v in vehicles) v.id: v};
    final entries = vehicleId == null
        ? await _entries.getAll()
        : await _entries.getForVehicle(vehicleId);

    final buffer = StringBuffer()
      ..writeln(_csvRow(const [
        'Vehicle',
        'Make',
        'Model',
        'Variant',
        'Year',
        'Licence plate',
        'Date',
        'Odometer (km)',
        'Trip (km)',
        'Volume (L)',
        'Total cost',
        'Price per litre',
        'Full tank',
        'Missed fill-up',
        'Station',
        'Notes',
      ]));

    for (final entry in entries) {
      final vehicle = byId[entry.vehicleId];
      buffer.writeln(_csvRow([
        vehicle?.displayName ?? 'Unknown',
        vehicle?.make ?? '',
        vehicle?.model ?? '',
        vehicle?.variant ?? '',
        vehicle?.year?.toString() ?? '',
        vehicle?.licensePlate ?? '',
        formatIsoDate(entry.filledAt),
        formatCompactNumber(entry.odometer),
        formatCompactNumber(entry.tripMeter),
        formatCompactNumber(entry.volume),
        formatCompactNumber(entry.totalCost),
        formatCompactNumber(entry.pricePerLitre, maxDecimals: 3),
        entry.isFullTank ? 'yes' : 'no',
        entry.missedFillUp ? 'yes' : 'no',
        entry.station ?? '',
        entry.notes ?? '',
      ]));
    }

    return buffer.toString();
  }

  Future<String> exportCsvFile({int? vehicleId}) async {
    final content = await exportCsvString(vehicleId: vehicleId);
    final name = 'fuel-log-${formatFileStamp(DateTime.now())}.csv';
    return _write(name, content);
  }

  static String _csvRow(List<String> cells) =>
      cells.map(_csvCell).join(',');

  static String _csvCell(String value) {
    final needsQuotes = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<String> _write(String fileName, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content);
    return file.path;
  }

  // -------------------------------------------------------------------------
  // Restore
  // -------------------------------------------------------------------------

  /// Reads a backup produced by [exportJsonString].
  ///
  /// Throws [FormatException] with a readable message when the payload is not
  /// one of ours. Vehicle ids are **remapped** on the way in, so a merge can
  /// never collide with an existing row.
  Future<RestoreResult> restoreFromJson(
    String source, {
    RestoreMode mode = RestoreMode.replace,
    bool restoreSettings = true,
  }) async {
    // Not `final`: a nullable local without an initialiser is implicitly null,
    // which sidesteps any definite-assignment question around the try block.
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('That does not look like JSON.');
    }

    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a backup object at the top level.');
    }
    if (decoded['format'] != formatId) {
      throw const FormatException(
        'This file was not produced by this app\'s backup export.',
      );
    }

    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw FormatException(
        'This backup was written by a newer version of the app '
        '(format $version). Update the app and try again.',
      );
    }

    final rawVehicles = decoded['vehicles'];
    if (rawVehicles is! List) {
      throw const FormatException('The backup has no vehicles list.');
    }

    // Parse the WHOLE payload before touching the database.
    //
    // The three checks above only prove the file is shaped like one of ours.
    // A truncated write, a disk error or a hand-edited field still gets past
    // them, and the `as String?` / `as num?` casts in the model parsers throw
    // on the wrong type. Deleting first and parsing as we went meant a
    // half-readable backup wiped the garage and then failed — the worst
    // outcome the app can produce. Nothing is destroyed until every row here
    // is known to be readable.
    final parsed = <_ParsedVehicle>[];
    try {
      for (final raw in rawVehicles) {
        if (raw is! Map) continue;
        final map = Map<String, Object?>.from(raw);

        parsed.add(_ParsedVehicle(
          vehicle: Vehicle.fromMap(map),
          entries: _parseList(map['entries'], FuelEntry.fromMap),
          // Absent in v1 backups, which is not an error.
          services: _parseList(map['services'], ServiceRecord.fromMap),
        ));
      }
    } catch (error) {
      // Deliberately broad: the model parsers throw TypeError, not
      // FormatException, and to the user a file we cannot read is one
      // problem with one answer.
      throw FormatException(
        'The backup could be read as JSON but some of its records are '
        'damaged, so nothing was changed. ($error)',
      );
    }

    if (mode == RestoreMode.replace) {
      // Children first: the cascade would take them anyway, but being explicit
      // keeps this correct even if foreign keys are ever off.
      await _entries.deleteAll();
      await _services.deleteAll();
      await _vehicles.deleteAll();
    }

    var vehiclesAdded = 0;
    var entriesAdded = 0;
    var servicesAdded = 0;

    for (final item in parsed) {
      final newId = await _vehicles.insert(item.vehicle);
      vehiclesAdded++;

      // Re-point at the id the vehicle actually received, which is what makes
      // a merge safe against existing rows.
      await _entries.insertMany([
        for (final entry in item.entries) entry.copyWith(vehicleId: newId),
      ]);
      entriesAdded += item.entries.length;

      await _services.insertMany([
        for (final record in item.services) record.copyWith(vehicleId: newId),
      ]);
      servicesAdded += item.services.length;
    }

    var settingsRestored = false;
    final rawSettings = decoded['settings'];
    if (restoreSettings && rawSettings is Map) {
      final values = <String, String>{};
      rawSettings.forEach((key, value) {
        // Interpolation rather than `value.toString()`: `value` is dynamic, so
        // the latter is a dynamic invocation returning dynamic, which
        // `strict-casts` will not silently narrow to String.
        if (key is String && value != null) values[key] = '$value';
      });
      // The restored garage has new ids, so the remembered vehicle is stale.
      values.remove(AppSettings.keyLastVehicleId);
      if (values.isNotEmpty) {
        await _settings.writeAll(values);
        settingsRestored = true;
      }
    }

    return RestoreResult(
      vehiclesAdded: vehiclesAdded,
      entriesAdded: entriesAdded,
      servicesAdded: servicesAdded,
      settingsRestored: settingsRestored,
    );
  }

  /// Parses a JSON array of rows with [fromMap], skipping anything that is not
  /// an object. A null or non-list value yields an empty list, which is how a
  /// v1 backup's missing `services` array is tolerated.
  static List<T> _parseList<T>(
    Object? raw,
    T Function(Map<String, Object?>) fromMap,
  ) {
    // `<T>[]` not `const []`: a const expression cannot reference a type
    // parameter, so the inferred form would be illegal here.
    if (raw is! List) return <T>[];
    return [
      for (final row in raw)
        if (row is Map) fromMap(Map<String, Object?>.from(row)),
    ];
  }

  Future<RestoreResult> restoreFromFile(
    String path, {
    RestoreMode mode = RestoreMode.replace,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FormatException('No file at $path');
    }
    return restoreFromJson(await file.readAsString(), mode: mode);
  }
}
