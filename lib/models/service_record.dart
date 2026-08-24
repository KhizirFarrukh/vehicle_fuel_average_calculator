/// Maintenance and service records (I19). Pure Dart — no Flutter imports.
library;

/// What was done. Stored as [ServiceType.key] so reordering or extending this
/// enum can never reinterpret existing rows.
///
/// [defaultIntervalKm] and [defaultIntervalDays] only seed the form; once a
/// record is saved, its own next-due values are what count.
enum ServiceType {
  oilChange('oil_change', 'Oil change', 5000, 180),
  tyres('tyres', 'Tyres', 40000, null),
  brakes('brakes', 'Brakes', 25000, null),
  airFilter('air_filter', 'Air filter', 15000, null),
  battery('battery', 'Battery', null, 1095),
  inspection('inspection', 'Inspection', null, 365),
  insurance('insurance', 'Insurance', null, 365),
  registration('registration', 'Registration', null, 365),
  tuning('tuning', 'Tuning / service', 10000, 365),
  repair('repair', 'Repair', null, null),
  other('other', 'Other', null, null);

  const ServiceType(
    this.key,
    this.label,
    this.defaultIntervalKm,
    this.defaultIntervalDays,
  );

  final String key;
  final String label;

  /// Typical distance between occurrences, or null when this is not a
  /// distance-based item.
  final int? defaultIntervalKm;

  /// Typical time between occurrences, or null when it is not time-based.
  final int? defaultIntervalDays;

  static ServiceType fromKey(String? key) {
    for (final type in ServiceType.values) {
      if (type.key == key) return type;
    }
    return ServiceType.other;
  }
}

/// One piece of work done on a vehicle, optionally with a next-due marker.
class ServiceRecord {
  const ServiceRecord({
    this.id,
    required this.vehicleId,
    required this.type,
    this.title,
    required this.performedAt,
    this.odometer,
    this.cost = 0,
    this.notes,
    this.nextDueOdometer,
    this.nextDueAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int vehicleId;

  final ServiceType type;

  /// Overrides [ServiceType.label] in the UI when the user wants something
  /// more specific than "Repair".
  final String? title;

  final DateTime performedAt;

  /// Kilometres on the clock when this was done. Optional: an insurance
  /// renewal has no meaningful odometer reading.
  final double? odometer;

  final double cost;
  final String? notes;

  /// Kilometres at which this is next due. Null means not distance-tracked.
  final double? nextDueOdometer;

  /// Date at which this is next due. Null means not date-tracked.
  final DateTime? nextDueAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayTitle {
    final custom = title?.trim();
    return (custom == null || custom.isEmpty) ? type.label : custom;
  }

  /// True when this record is watching for anything at all.
  bool get hasReminder => nextDueOdometer != null || nextDueAt != null;

  /// Newest first, for the history list.
  static int compareByDateDesc(ServiceRecord a, ServiceRecord b) {
    final byDate = b.performedAt.compareTo(a.performedAt);
    if (byDate != 0) return byDate;
    return (b.id ?? 0).compareTo(a.id ?? 0);
  }

  static const Object _unset = Object();

  ServiceRecord copyWith({
    int? id,
    int? vehicleId,
    ServiceType? type,
    Object? title = _unset,
    DateTime? performedAt,
    Object? odometer = _unset,
    double? cost,
    Object? notes = _unset,
    Object? nextDueOdometer = _unset,
    Object? nextDueAt = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceRecord(
      id: id ?? this.id,
      vehicleId: vehicleId ?? this.vehicleId,
      type: type ?? this.type,
      title: identical(title, _unset) ? this.title : title as String?,
      performedAt: performedAt ?? this.performedAt,
      odometer: identical(odometer, _unset) ? this.odometer : odometer as double?,
      cost: cost ?? this.cost,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      nextDueOdometer: identical(nextDueOdometer, _unset)
          ? this.nextDueOdometer
          : nextDueOdometer as double?,
      nextDueAt:
          identical(nextDueAt, _unset) ? this.nextDueAt : nextDueAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'vehicle_id': vehicleId,
        'type': type.key,
        'title': title,
        'performed_at': performedAt.millisecondsSinceEpoch,
        'odometer': odometer,
        'cost': cost,
        'notes': notes,
        'next_due_odometer': nextDueOdometer,
        'next_due_at': nextDueAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ServiceRecord.fromMap(Map<String, Object?> map) {
    final nextDueAtMillis = (map['next_due_at'] as num?)?.toInt();
    return ServiceRecord(
      id: (map['id'] as num?)?.toInt(),
      vehicleId: (map['vehicle_id'] as num?)?.toInt() ?? 0,
      type: ServiceType.fromKey(map['type'] as String?),
      title: map['title'] as String?,
      performedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['performed_at'] as num?)?.toInt() ?? 0,
      ),
      odometer: (map['odometer'] as num?)?.toDouble(),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      nextDueOdometer: (map['next_due_odometer'] as num?)?.toDouble(),
      nextDueAt: nextDueAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextDueAtMillis),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  String toString() => 'ServiceRecord(id: $id, $displayTitle)';

  @override
  bool operator ==(Object other) =>
      other is ServiceRecord &&
      other.id == id &&
      other.vehicleId == vehicleId &&
      other.type == type &&
      other.title == title &&
      other.performedAt == performedAt &&
      other.odometer == odometer &&
      other.cost == cost &&
      other.notes == notes &&
      other.nextDueOdometer == nextDueOdometer &&
      other.nextDueAt == nextDueAt;

  @override
  int get hashCode => Object.hash(
        id,
        vehicleId,
        type,
        title,
        performedAt,
        odometer,
        cost,
        notes,
        nextDueOdometer,
        nextDueAt,
      );
}
