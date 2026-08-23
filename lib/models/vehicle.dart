/// The vehicle record. Pure Dart — no Flutter imports.
library;

/// What the vehicle burns. Stored as [FuelType.key] so that reordering or
/// extending this enum can never silently reinterpret existing rows.
enum FuelType {
  petrol('petrol', 'Petrol'),
  diesel('diesel', 'Diesel'),
  cng('cng', 'CNG'),
  lpg('lpg', 'LPG'),
  hybrid('hybrid', 'Hybrid'),
  electric('electric', 'Electric'),
  other('other', 'Other');

  const FuelType(this.key, this.label);

  final String key;
  final String label;

  static FuelType fromKey(String? key) {
    for (final type in FuelType.values) {
      if (type.key == key) return type;
    }
    return FuelType.petrol;
  }
}

/// One vehicle in the garage.
///
/// Per the requirements: **make, model and variant are required**; **year,
/// colour and licence plate are optional**. Everything below them is an
/// addition (see docs/PLAN.md §3, I7).
///
/// Immutable; [copyWith] uses an `_unset` sentinel so that an optional field
/// can genuinely be *cleared* rather than merely left alone.
class Vehicle {
  const Vehicle({
    this.id,
    required this.make,
    required this.model,
    required this.variant,
    this.year,
    this.color,
    this.licensePlate,
    this.fuelType = FuelType.petrol,
    this.tankCapacity,
    this.initialOdometer,
    this.notes,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Null until the row has been inserted.
  final int? id;

  // --- Required identity -------------------------------------------------
  final String make;
  final String model;
  final String variant;

  // --- Optional identity -------------------------------------------------
  final int? year;
  final String? color;
  final String? licensePlate;

  // --- Additions ---------------------------------------------------------
  final FuelType fuelType;

  /// Litres. Enables the range estimate.
  final double? tankCapacity;

  /// Kilometres on the clock when tracking started. Informational only — the
  /// economy engine anchors on actual entries, never on this.
  final double? initialOdometer;

  final String? notes;

  /// Archived vehicles stay in the database with all their history but drop
  /// out of the main garage list.
  final bool isArchived;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// `Toyota Corolla Altis`
  String get name =>
      [make, model, variant].map((p) => p.trim()).where((p) => p.isNotEmpty).join(' ');

  /// `2019 Toyota Corolla Altis`
  String get displayName => year != null ? '$year $name' : name;

  /// `ABC-123 · White · Petrol` — whichever optional parts exist.
  String get subtitle {
    final parts = <String>[
      if (licensePlate != null && licensePlate!.trim().isNotEmpty) licensePlate!.trim(),
      if (color != null && color!.trim().isNotEmpty) color!.trim(),
      fuelType.label,
    ];
    return parts.join(' · ');
  }

  /// Two letters for the avatar chip.
  String get initials {
    final a = make.trim();
    final b = model.trim();
    final first = a.isNotEmpty ? a[0] : '?';
    final second = b.isNotEmpty ? b[0] : '';
    return '$first$second'.toUpperCase();
  }

  static const Object _unset = Object();

  Vehicle copyWith({
    int? id,
    String? make,
    String? model,
    String? variant,
    Object? year = _unset,
    Object? color = _unset,
    Object? licensePlate = _unset,
    FuelType? fuelType,
    Object? tankCapacity = _unset,
    Object? initialOdometer = _unset,
    Object? notes = _unset,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      make: make ?? this.make,
      model: model ?? this.model,
      variant: variant ?? this.variant,
      year: identical(year, _unset) ? this.year : year as int?,
      color: identical(color, _unset) ? this.color : color as String?,
      licensePlate: identical(licensePlate, _unset)
          ? this.licensePlate
          : licensePlate as String?,
      fuelType: fuelType ?? this.fuelType,
      tankCapacity: identical(tankCapacity, _unset)
          ? this.tankCapacity
          : tankCapacity as double?,
      initialOdometer: identical(initialOdometer, _unset)
          ? this.initialOdometer
          : initialOdometer as double?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'make': make,
        'model': model,
        'variant': variant,
        'year': year,
        'color': color,
        'license_plate': licensePlate,
        'fuel_type': fuelType.key,
        'tank_capacity': tankCapacity,
        'initial_odometer': initialOdometer,
        'notes': notes,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Vehicle.fromMap(Map<String, Object?> map) {
    return Vehicle(
      id: (map['id'] as num?)?.toInt(),
      make: (map['make'] as String?) ?? '',
      model: (map['model'] as String?) ?? '',
      variant: (map['variant'] as String?) ?? '',
      year: (map['year'] as num?)?.toInt(),
      color: map['color'] as String?,
      licensePlate: map['license_plate'] as String?,
      fuelType: FuelType.fromKey(map['fuel_type'] as String?),
      tankCapacity: (map['tank_capacity'] as num?)?.toDouble(),
      initialOdometer: (map['initial_odometer'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      isArchived: ((map['is_archived'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  String toString() => 'Vehicle(id: $id, $displayName)';

  @override
  bool operator ==(Object other) =>
      other is Vehicle &&
      other.id == id &&
      other.make == make &&
      other.model == model &&
      other.variant == variant &&
      other.year == year &&
      other.color == color &&
      other.licensePlate == licensePlate &&
      other.fuelType == fuelType &&
      other.tankCapacity == tankCapacity &&
      other.initialOdometer == initialOdometer &&
      other.notes == notes &&
      other.isArchived == isArchived;

  @override
  int get hashCode => Object.hash(
        id,
        make,
        model,
        variant,
        year,
        color,
        licensePlate,
        fuelType,
        tankCapacity,
        initialOdometer,
        notes,
        isArchived,
      );
}
