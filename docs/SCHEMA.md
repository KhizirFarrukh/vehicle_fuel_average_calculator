# Database schema

SQLite via `sqflite`. Defined in `lib/data/app_database.dart`.

- **Current version:** 2 (`AppDatabase.schemaVersion`)
- **File:** `fuel_tracker.db` in the app support directory (desktop) or the
  databases directory (mobile)
- **Foreign keys:** enabled in `onConfigure` with `PRAGMA foreign_keys = ON`.
  Without this, sqflite silently treats `ON DELETE CASCADE` as a no-op and
  orphans every entry of a deleted vehicle. There is a test for it.

---

## Tables

### `vehicles`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `make` | TEXT NOT NULL | required |
| `model` | TEXT NOT NULL | required |
| `variant` | TEXT NOT NULL | required |
| `year` | INTEGER | **optional** |
| `color` | TEXT | **optional** |
| `license_plate` | TEXT | **optional** |
| `fuel_type` | TEXT NOT NULL DEFAULT `'petrol'` | `FuelType.key` |
| `tank_capacity` | REAL | litres; enables the range estimate |
| `initial_odometer` | REAL | km |
| `notes` | TEXT | |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | boolean as 0/1 |
| `created_at`, `updated_at` | INTEGER NOT NULL | epoch ms |

### `fuel_entries`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `vehicle_id` | INTEGER NOT NULL | FK → `vehicles(id)` **ON DELETE CASCADE** |
| `filled_at` | INTEGER NOT NULL | epoch ms |
| `odometer` | REAL NOT NULL | **kilometres** |
| `trip_meter` | REAL | kilometres, optional |
| `volume` | REAL NOT NULL | **litres** |
| `total_cost` | REAL NOT NULL | never unit-converted |
| `is_full_tank` | INTEGER NOT NULL DEFAULT 1 | see below |
| `missed_fill_up` | INTEGER NOT NULL DEFAULT 0 | see below |
| `station` | TEXT | |
| `notes` | TEXT | |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Indexes: `(vehicle_id, odometer)` and `(vehicle_id, filled_at)`.

**`is_full_tank` and `missed_fill_up` are load-bearing**, not conveniences.
The whole economy calculation depends on them — see
[DECISIONS.md](DECISIONS.md) §D3.

There is no `price_per_litre` column. It is derived from
`total_cost / volume` in `FuelEntry.pricePerLitre`, so it cannot drift out of
step after an edit.

### `service_records` *(added in v2)*

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `vehicle_id` | INTEGER NOT NULL | FK → `vehicles(id)` **ON DELETE CASCADE** |
| `type` | TEXT NOT NULL DEFAULT `'other'` | `ServiceType.key` |
| `title` | TEXT | overrides the type label in the UI |
| `performed_at` | INTEGER NOT NULL | epoch ms |
| `odometer` | REAL | km, **optional** — insurance has no mileage |
| `cost` | REAL NOT NULL DEFAULT 0 | |
| `notes` | TEXT | |
| `next_due_odometer` | REAL | km; null = not distance-tracked |
| `next_due_at` | INTEGER | epoch ms; null = not date-tracked |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Index: `(vehicle_id, performed_at)`.

### `settings`

| Column | Type |
|---|---|
| `key` | TEXT PRIMARY KEY |
| `value` | TEXT NOT NULL |

Written with `ConflictAlgorithm.replace`. Keys are the `AppSettings.key*`
constants. In a table rather than `shared_preferences` so a backup captures
preferences too (D9).

---

## Conventions

- **Booleans** are INTEGER 0/1. Models convert.
- **Dates** are epoch milliseconds, INTEGER. Never ISO strings — they sort
  wrong and cost parsing.
- **Distances** are always kilometres. **Volumes** are always litres. No
  exceptions, no per-row unit tags (D4).
- **Money** has no unit and is never converted.
- Column names are `snake_case`; Dart fields are `camelCase`; the mapping is
  explicit in each model's `toMap`/`fromMap`.

---

## Adding a migration

Follow this exactly — the pattern exists to stop fresh installs and upgraded
installs from drifting apart (D12).

1. **Put the DDL in a shared constant** on `AppDatabase`, next to
   `_serviceRecordsV2`:

   ```dart
   static const List<String> _somethingV3 = [
     'ALTER TABLE vehicles ADD COLUMN nickname TEXT',
   ];
   ```

2. **Call it from `_create`** so fresh installs get it:

   ```dart
   for (final statement in _somethingV3) {
     batch.execute(statement);
   }
   ```

3. **Add a case to `_upgrade`** so existing installs get it:

   ```dart
   case 3:
     for (final statement in _somethingV3) {
       await db.execute(statement);
     }
   ```

4. **Bump `AppDatabase.schemaVersion`** to 3 and update its doc comment.

5. **Write a migration test** in `test/database_test.dart` modelled on the
   existing one: build the previous version by hand, reopen through
   `AppDatabase.open(overridePath: ...)`, then assert both that the change
   landed *and that existing rows survived*.

   Use a **temp file, not `:memory:`** — every in-memory open creates a new
   database, so a migration cannot be observed across one. This is the single
   easiest mistake to make here.

6. If the change affects what a backup should carry, bump
   `BackupService.formatVersion` too and make sure older backups still restore.

**Never edit an existing migration case.** Users may already have run it. Add
a new version instead.

---

## Backup format

JSON, `BackupService.formatVersion` = 2, versioned independently of the schema.

```jsonc
{
  "format": "vehicle_fuel_average_calculator.backup",
  "version": 2,
  "exportedAt": "2026-08-25T...",
  "units": "Distances in kilometres, volumes in litres.",
  "settings": { "distance_unit": "km", ... },
  "vehicles": [
    {
      "make": "Toyota", "model": "Corolla", "variant": "Altis",
      "entries":  [ { ...fuel_entries row... } ],
      "services": [ { ...service_records row... } ]   // absent in v1
    }
  ]
}
```

On restore, **vehicle ids are remapped** — each vehicle is inserted, and its
entries and service records are re-pointed at the id it actually received. This
is what makes merge-restore safe. A *newer* format version is refused with a
readable message rather than half-read; older ones restore fine.
