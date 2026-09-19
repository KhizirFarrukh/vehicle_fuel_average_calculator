/// Renders an [EntryIssue] as a sentence in the reader's units.
///
/// Pure Dart. This exists because of a layering constraint worth understanding:
/// the engine in `lib/domain/` is deliberately Flutter-free and stores
/// canonical kilometres, so it cannot know whether the reader wants miles. It
/// therefore emits a unit-free [EntryIssue.message] plus the raw figures, and
/// this function puts them back together.
///
/// Earlier versions built the sentence in the engine with `km` hardcoded, which
/// showed kilometre values labelled `km` to someone whose every other reading
/// was in miles.
library;

import '../models/fuel_stats.dart';
import 'unit_formatter.dart';

String describeIssue(EntryIssue issue, UnitFormatter units) {
  switch (issue.kind) {
    case IssueKind.windowTooShort:
      final distance = issue.distanceKm;
      if (distance == null) return issue.message;
      return 'The odometer moved only ${units.distance(distance, decimals: 1)} '
          'since the last full tank, so no average could be calculated. '
          'Check the reading.';

    case IssueKind.duplicateOdometer:
      final odometer = issue.odometerKm;
      if (odometer == null) return issue.message;
      return 'Two entries share the odometer reading '
          '${units.distance(odometer)}.';

    case IssueKind.tripMismatch:
      final trip = issue.tripKm;
      final distance = issue.distanceKm;
      if (trip == null || distance == null) return issue.message;
      return 'Trip meter says ${units.distance(trip)} but the odometer moved '
          '${units.distance(distance)} since the last full tank.';

    // No figures to render; the engine's sentence already stands on its own.
    case IssueKind.missedFillUp:
    case IssueKind.dateOutOfOrder:
      return issue.message;
  }
}
