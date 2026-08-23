/// A single refuelling record. Pure Dart — no Flutter imports.
library;

/// One visit to the pump.
///
/// The four fields the requirements asked for are [volume] (amount refilled),
/// [totalCost] (cost of that refill), [tripMeter] and [odometer] (the trip and
/// ODO readings at which fuel was refilled).
///
/// [isFullTank] and [missedFillUp] are additions, and they are what make the
/// economy figures trustworthy — see docs/PLAN.md §6.
///
/// Canonical units: kilometres and litres. Conversion happens at the UI edge.
class FuelEntry {
  const FuelEntry({
    this.id,
    required this.vehicleId,
    required this.filledAt,
    required this.odometer,
    this.tripMeter,
    required this.volume,
    required this.totalCost,
    this.isFullTank = true,
    this.missedFillUp = false,
    this.station,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Null until the row has been inserted.
  final int? id;

  final int vehicleId;

  final DateTime filledAt;

  /// Total distance on the clock, in kilometres.
  final double odometer;

  /// Trip-meter reading in kilometres, if the driver resets it at each fill.
  /// Optional, and used only as a cross-check against the odometer delta.
  final double? tripMeter;

  /// Litres put into the tank.
  final double volume;

  /// What this refill cost, in the user's single configured currency.
  final double totalCost;

  /// True when the tank was filled all the way to the cut-off.
  ///
  /// This is the single most important flag in the model. The tank-to-tank
  /// method needs a known reference level at both ends of a window; only a
  /// full tank provides one.
  final bool isFullTank;

  /// True when the driver refuelled at some point before this entry and did
  /// not record it. Voids the window in progress rather than quietly
  /// understating fuel used.
  final bool missedFillUp;

  final String? station;
  final String? notes;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Derived, never stored — storing it alongside [totalCost] and [volume]
  /// would let the three disagree after an edit.
  double? get pricePerLitre => volume > 0 ? totalCost / volume : null;

  /// Engine ordering: by odometer, because odometer is the physical truth that
  /// window distances are measured from. Dates break ties.
  static int compareByOdometer(FuelEntry a, FuelEntry b) {
    final byOdo = a.odometer.compareTo(b.odometer);
    if (byOdo != 0) return byOdo;
    final byDate = a.filledAt.compareTo(b.filledAt);
    if (byDate != 0) return byDate;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  /// Display ordering: newest first.
  static int compareByDateDesc(FuelEntry a, FuelEntry b) =>
      -compareByOdometer(a, b);

  static const Object _unset = Object();

  FuelEntry copyWith({
    int? id,
    int? vehicleId,
    DateTime? filledAt,
    double? odometer,
    Object? tripMeter = _unset,
    double? volume,
    double? totalCost,
    bool? isFullTank,
    bool? missedFillUp,
    Object? station = _unset,
    Object? notes = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FuelEntry(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      filledAt: filledAt ?? this.filledAt,
      odometer: odometer ?? this.odometer,
      tripMeter:
          identical(tripMeter, _unset) ? this.tripMeter : tripMeter as double?,
      volume: volume ?? this.volume,
      totalCost: totalCost ?? this.totalCost,
      isFullTank: isFullTank ?? this.isFullTank,
      missedFillUp: missedFillUp ?? this.missedFillUp,
      station: identical(station, _unset) ? this.station : station as String?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'vehicle_id': vehicleId,
        'filled_at': filledAt.millisecondsSinceEpoch,
        'odometer': odometer,
        'trip_meter': tripMeter,
        'volume': volume,
        'total_cost': totalCost,
        'is_full_tank': isFullTank ? 1 : 0,
        'missed_fill_up': missedFillUp ? 1 : 0,
        'station': station,
        'notes': notes,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory FuelEntry.fromMap(Map<String, Object?> map) {
    return FuelEntry(
      id: (map['id'] as num?)?.toInt(),
      vehicleId: (map['vehicle_id'] as num?)?.toInt() ?? 0,
      filledAt: DateTime.fromMillisecondsSinceEpoch(
        (map['filled_at'] as num?)?.toInt() ?? 0,
      ),
      odometer: (map['odometer'] as num?)?.toDouble() ?? 0,
      tripMeter: (map['trip_meter'] as num?)?.toDouble(),
      volume: (map['volume'] as num?)?.toDouble() ?? 0,
      totalCost: (map['total_cost'] as num?)?.toDouble() ?? 0,
      isFullTank: ((map['is_full_tank'] as num?)?.toInt() ?? 1) == 1,
      missedFillUp: ((map['missed_fill_up'] as num?)?.toInt() ?? 0) == 1,
      station: map['station'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  String toString() =>
      'FuelEntry(id: $id, vehicle: $vehicleId, odo: $odometer, vol: $volume)';

  @override
  bool operator ==(Object other) =>
      other is FuelEntry &&
      other.id == id &&
      other.vehicleId == vehicleId &&
      other.filledAt == filledAt &&
      other.odometer == odometer &&
      other.tripMeter == tripMeter &&
      other.volume == volume &&
      other.totalCost == totalCost &&
      other.isFullTank == isFullTank &&
      other.missedFillUp == missedFillUp &&
      other.station == station &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
        id,
        vehicleId,
        filledAt,
        odometer,
        tripMeter,
        volume,
        totalCost,
        isFullTank,
        missedFillUp,
        station,
        notes,
      );
}
