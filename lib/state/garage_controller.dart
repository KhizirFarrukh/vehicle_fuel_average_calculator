import 'package:flutter/foundation.dart';

import '../data/fuel_entry_dao.dart';
import '../data/service_dao.dart';
import '../data/vehicle_dao.dart';
import '../domain/fuel_calculator.dart';
import '../domain/service_planner.dart';
import '../models/fuel_entry.dart';
import '../models/fuel_stats.dart';
import '../models/service_record.dart';
import '../models/vehicle.dart';

/// Owns the garage: every vehicle, every refuelling entry, and the statistics
/// derived from them.
///
/// The whole log is held in memory. A heavy user logs perhaps 30 entries a
/// year per vehicle, so this is kilobytes, and it means the home screen can
/// show each vehicle's current average without a query per card.
class GarageController extends ChangeNotifier {
  GarageController({
    required VehicleDao vehicleDao,
    required FuelEntryDao entryDao,
    required ServiceDao serviceDao,
  })  : _vehicleDao = vehicleDao,
        _entryDao = entryDao,
        _serviceDao = serviceDao;

  final VehicleDao _vehicleDao;
  final FuelEntryDao _entryDao;
  final ServiceDao _serviceDao;

  bool _loading = true;
  String? _error;
  bool _showArchived = false;

  List<Vehicle> _vehicles = const [];
  final Map<int, List<FuelEntry>> _entriesByVehicle = {};
  final Map<int, VehicleStats> _statsByVehicle = {};
  final Map<int, List<ServiceRecord>> _servicesByVehicle = {};

  bool get isLoading => _loading;
  String? get error => _error;
  bool get showArchived => _showArchived;

  /// Vehicles matching the current archived filter.
  List<Vehicle> get vehicles => _showArchived
      ? _vehicles
      : _vehicles.where((v) => !v.isArchived).toList(growable: false);

  /// Every vehicle, archived or not.
  List<Vehicle> get allVehicles => _vehicles;

  List<Vehicle> get activeVehicles =>
      _vehicles.where((v) => !v.isArchived).toList(growable: false);

  bool get hasAnyVehicle => _vehicles.isNotEmpty;
  int get archivedCount => _vehicles.where((v) => v.isArchived).length;

  Vehicle? vehicleById(int? id) {
    if (id == null) return null;
    for (final vehicle in _vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return null;
  }

  /// Entries for a vehicle, ordered by odometer ascending.
  List<FuelEntry> entriesFor(int? vehicleId) {
    if (vehicleId == null) return const [];
    return _entriesByVehicle[vehicleId] ?? const [];
  }

  /// Newest first, for the history list.
  List<FuelEntry> entriesNewestFirst(int? vehicleId) {
    final entries = List<FuelEntry>.of(entriesFor(vehicleId))
      ..sort(FuelEntry.compareByDateDesc);
    return entries;
  }

  VehicleStats statsFor(int? vehicleId) {
    if (vehicleId == null) return VehicleStats.empty(0);
    return _statsByVehicle[vehicleId] ?? VehicleStats.empty(vehicleId);
  }

  // -------------------------------------------------------------------------
  // Loading
  // -------------------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final vehicles = await _vehicleDao.getAll(includeArchived: true);
      final entries = await _entryDao.getAll();
      final services = await _serviceDao.getAll();

      _vehicles = vehicles;
      _entriesByVehicle
        ..clear()
        ..addAll(_group(entries, vehicles));
      _servicesByVehicle
        ..clear()
        ..addAll(_groupServices(services, vehicles));
      _recomputeAll();
      _error = null;
    } catch (e) {
      _error = 'Could not load your garage: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Map<int, List<FuelEntry>> _group(
    List<FuelEntry> entries,
    List<Vehicle> vehicles,
  ) {
    final grouped = <int, List<FuelEntry>>{
      // Seed with every vehicle so one with no entries still gets an entry.
      for (final vehicle in vehicles)
        if (vehicle.id != null) vehicle.id!: <FuelEntry>[],
    };
    for (final entry in entries) {
      grouped.putIfAbsent(entry.vehicleId, () => <FuelEntry>[]).add(entry);
    }
    for (final list in grouped.values) {
      list.sort(FuelEntry.compareByOdometer);
    }
    return grouped;
  }

  Map<int, List<ServiceRecord>> _groupServices(
    List<ServiceRecord> records,
    List<Vehicle> vehicles,
  ) {
    final grouped = <int, List<ServiceRecord>>{
      for (final vehicle in vehicles)
        if (vehicle.id != null) vehicle.id!: <ServiceRecord>[],
    };
    for (final record in records) {
      grouped.putIfAbsent(record.vehicleId, () => <ServiceRecord>[]).add(record);
    }
    for (final list in grouped.values) {
      list.sort(ServiceRecord.compareByDateDesc);
    }
    return grouped;
  }

  void _recomputeAll() {
    _statsByVehicle.clear();
    _entriesByVehicle.forEach((vehicleId, entries) {
      _statsByVehicle[vehicleId] = FuelCalculator.analyze(vehicleId, entries);
    });
  }

  void _recompute(int vehicleId) {
    final entries = _entriesByVehicle[vehicleId] ?? const <FuelEntry>[];
    _statsByVehicle[vehicleId] = FuelCalculator.analyze(vehicleId, entries);
  }

  void setShowArchived(bool value) {
    if (_showArchived == value) return;
    _showArchived = value;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Vehicle CRUD
  // -------------------------------------------------------------------------

  /// Returns the new vehicle's id.
  Future<int> addVehicle(Vehicle vehicle) async {
    final now = DateTime.now();
    final id = await _vehicleDao.insert(
      vehicle.copyWith(createdAt: now, updatedAt: now),
    );
    final saved = await _vehicleDao.getById(id);
    if (saved != null) {
      _vehicles = [saved, ..._vehicles];
      _entriesByVehicle[id] = <FuelEntry>[];
      _servicesByVehicle[id] = <ServiceRecord>[];
      _recompute(id);
    }
    notifyListeners();
    return id;
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    final id = vehicle.id;
    if (id == null) return;
    final updated = vehicle.copyWith(updatedAt: DateTime.now());
    await _vehicleDao.update(updated);
    _vehicles = [
      for (final existing in _vehicles)
        if (existing.id == id) updated else existing,
    ];
    notifyListeners();
  }

  /// Removes the vehicle **and all of its entries**. Confirm before calling.
  Future<void> deleteVehicle(int id) async {
    await _vehicleDao.delete(id);
    _vehicles = _vehicles.where((v) => v.id != id).toList(growable: false);
    _entriesByVehicle.remove(id);
    _statsByVehicle.remove(id);
    // The database cascade takes these; the cache has to be told.
    _servicesByVehicle.remove(id);
    notifyListeners();
  }

  Future<void> setArchived(int id, bool archived) async {
    await _vehicleDao.setArchived(id, archived);
    _vehicles = [
      for (final vehicle in _vehicles)
        if (vehicle.id == id)
          vehicle.copyWith(isArchived: archived, updatedAt: DateTime.now())
        else
          vehicle,
    ];
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Entry CRUD
  // -------------------------------------------------------------------------

  Future<int> addEntry(FuelEntry entry) async {
    final now = DateTime.now();
    final id = await _entryDao.insert(
      entry.copyWith(createdAt: now, updatedAt: now),
    );
    await _reloadEntries(entry.vehicleId);
    // Keeps the garage list ordered by recent activity.
    await _vehicleDao.touch(entry.vehicleId);
    _bumpVehicleTimestamp(entry.vehicleId, now);
    notifyListeners();
    return id;
  }

  /// Bulk insert for CSV import. Reloads and recomputes once at the end rather
  /// than per row, which for a few hundred imported fill-ups is the difference
  /// between instant and visibly slow.
  ///
  /// Returns the number of entries written.
  Future<int> addEntries(int vehicleId, List<FuelEntry> entries) async {
    if (entries.isEmpty) return 0;

    final now = DateTime.now();
    await _entryDao.insertMany([
      for (final entry in entries)
        entry.copyWith(vehicleId: vehicleId, createdAt: now, updatedAt: now),
    ]);

    await _reloadEntries(vehicleId);
    await _vehicleDao.touch(vehicleId);
    _bumpVehicleTimestamp(vehicleId, now);
    notifyListeners();
    return entries.length;
  }

  Future<void> updateEntry(FuelEntry entry) async {
    if (entry.id == null) return;
    await _entryDao.update(entry.copyWith(updatedAt: DateTime.now()));
    await _reloadEntries(entry.vehicleId);
    notifyListeners();
  }

  Future<void> deleteEntry(FuelEntry entry) async {
    final id = entry.id;
    if (id == null) return;
    await _entryDao.delete(id);
    await _reloadEntries(entry.vehicleId);
    notifyListeners();
  }

  /// Re-reads one vehicle's entries and recomputes only its statistics.
  Future<void> _reloadEntries(int vehicleId) async {
    final entries = await _entryDao.getForVehicle(vehicleId);
    _entriesByVehicle[vehicleId] = List<FuelEntry>.of(entries)
      ..sort(FuelEntry.compareByOdometer);
    _recompute(vehicleId);
  }

  void _bumpVehicleTimestamp(int vehicleId, DateTime now) {
    _vehicles = [
      for (final vehicle in _vehicles)
        if (vehicle.id == vehicleId) vehicle.copyWith(updatedAt: now) else vehicle,
    ];
  }

  // -------------------------------------------------------------------------
  // Service records (I19)
  // -------------------------------------------------------------------------

  /// Newest first.
  List<ServiceRecord> servicesFor(int? vehicleId) {
    if (vehicleId == null) return const [];
    return _servicesByVehicle[vehicleId] ?? const [];
  }

  /// The odometer reminders are measured against: the highest fuel reading on
  /// record, falling back to the vehicle's starting odometer.
  ///
  /// Service records carry their own odometer too, and a vehicle whose only
  /// odometer history is a service visit should still get distance reminders.
  double? currentOdometerFor(int? vehicleId) {
    if (vehicleId == null) return null;

    double? highest = statsFor(vehicleId).lastOdometerKm;

    for (final record in servicesFor(vehicleId)) {
      final odometer = record.odometer;
      if (odometer == null) continue;
      if (highest == null || odometer > highest) highest = odometer;
    }

    return highest ?? vehicleById(vehicleId)?.initialOdometer;
  }

  List<ServiceReminder> remindersFor(int? vehicleId) {
    if (vehicleId == null) return const [];
    return ServicePlanner.remindersFor(
      servicesFor(vehicleId),
      currentOdometerKm: currentOdometerFor(vehicleId),
    );
  }

  /// Reminders worth surfacing unprompted — overdue or due soon.
  List<ServiceReminder> serviceAlertsFor(int? vehicleId) {
    if (vehicleId == null) return const [];
    return ServicePlanner.attentionNeeded(
      servicesFor(vehicleId),
      currentOdometerKm: currentOdometerFor(vehicleId),
    );
  }

  double serviceCostFor(int? vehicleId) =>
      ServicePlanner.totalCost(servicesFor(vehicleId));

  Future<int> addService(ServiceRecord record) async {
    final now = DateTime.now();
    final id = await _serviceDao.insert(
      record.copyWith(createdAt: now, updatedAt: now),
    );
    await _reloadServices(record.vehicleId);
    notifyListeners();
    return id;
  }

  Future<void> updateService(ServiceRecord record) async {
    if (record.id == null) return;
    await _serviceDao.update(record.copyWith(updatedAt: DateTime.now()));
    await _reloadServices(record.vehicleId);
    notifyListeners();
  }

  Future<void> deleteService(ServiceRecord record) async {
    final id = record.id;
    if (id == null) return;
    await _serviceDao.delete(id);
    await _reloadServices(record.vehicleId);
    notifyListeners();
  }

  Future<void> _reloadServices(int vehicleId) async {
    final records = await _serviceDao.getForVehicle(vehicleId);
    _servicesByVehicle[vehicleId] = List<ServiceRecord>.of(records)
      ..sort(ServiceRecord.compareByDateDesc);
  }

  /// Called after a backup restore, which rewrites everything underneath us.
  Future<void> reloadAfterRestore() => load();
}
