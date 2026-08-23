/// Form validators and lenient numeric parsing.
///
/// Every function returns `null` when the value is acceptable and an error
/// string otherwise, matching Flutter's `FormFieldValidator` contract without
/// importing Flutter.
library;

/// Parses a number the way a person types one at a petrol pump: with stray
/// spaces, thousands separators, a comma as the decimal mark, or a currency
/// symbol still attached.
///
/// Returns null when nothing numeric can be recovered.
double? parseFlexibleDouble(String? raw) {
  if (raw == null) return null;
  var text = raw.trim();
  if (text.isEmpty) return null;

  // Strip anything that is not a digit, separator or sign.
  text = text.replaceAll(RegExp(r'[^0-9.,\-]'), '');
  if (text.isEmpty) return null;

  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');

  if (lastComma != -1 && lastDot != -1) {
    // Both present: whichever comes last is the decimal mark.
    if (lastComma > lastDot) {
      // Dots were grouping. Drop them, then split on the final comma —
      // recomputed, because removing the dots shifted every index left.
      text = text.replaceAll('.', '');
      final mark = text.lastIndexOf(',');
      final whole = text.substring(0, mark).replaceAll(',', '');
      text = '$whole.${text.substring(mark + 1)}';
    } else {
      text = text.replaceAll(',', '');
    }
  } else if (lastComma != -1) {
    // Only commas. Three digits after a single comma reads as grouping
    // ("1,234"); anything else reads as a decimal mark ("12,5").
    final after = text.length - lastComma - 1;
    final commaCount = ','.allMatches(text).length;
    if (commaCount == 1 && after != 3) {
      text = text.replaceFirst(',', '.');
    } else {
      text = text.replaceAll(',', '');
    }
  }

  return double.tryParse(text);
}

/// Parses an integer with the same leniency.
int? parseFlexibleInt(String? raw) {
  final value = parseFlexibleDouble(raw);
  if (value == null) return null;
  return value.round();
}

String? validateRequired(String? value, String label) {
  if (value == null || value.trim().isEmpty) return '$label is required';
  return null;
}

/// Validates a number field.
///
/// [min] is exclusive when [allowZero] is false, which is what "litres must be
/// positive" actually means.
String? validateNumber(
  String? value,
  String label, {
  bool required = true,
  bool allowZero = false,
  bool allowNegative = false,
  double? min,
  double? max,
}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return required ? '$label is required' : null;
  }

  final parsed = parseFlexibleDouble(text);
  if (parsed == null) return 'Enter a valid number for $label';
  if (parsed.isNaN || parsed.isInfinite) return 'Enter a valid number for $label';

  if (!allowNegative && parsed < 0) return '$label cannot be negative';
  if (!allowZero && parsed == 0) return '$label must be greater than zero';
  if (min != null && parsed < min) {
    return '$label must be at least ${_trim(min)}';
  }
  if (max != null && parsed > max) {
    return '$label must be at most ${_trim(max)}';
  }
  return null;
}

/// Model years outside this range are almost certainly typos.
const int kMinVehicleYear = 1900;

String? validateYear(String? value, {int? currentYear}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null; // optional per the requirements

  final parsed = parseFlexibleInt(text);
  if (parsed == null) return 'Enter a valid year';

  final maxYear = (currentYear ?? DateTime.now().year) + 2;
  if (parsed < kMinVehicleYear || parsed > maxYear) {
    return 'Year must be between $kMinVehicleYear and $maxYear';
  }
  return null;
}

String _trim(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}
