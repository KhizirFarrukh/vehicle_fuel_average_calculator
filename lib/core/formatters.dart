/// Hand-rolled number, date and currency formatting.
///
/// Deliberately dependency-free: `intl` is version-pinned by
/// `flutter_localizations` and can wedge a dependency solve, and this app needs
/// perhaps eighty lines of what it offers. See docs/PLAN.md §4.
///
/// Pure Dart — no Flutter imports, so it is directly unit-testable.
library;

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Shown wherever a value exists but cannot be computed (no data, divide by
/// zero, infinity). A consistent glyph beats a scattering of '0.00' and 'N/A'.
const String kEmDash = '—';

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats [value] with [decimals] places and thousands separators.
///
/// Non-finite input yields [kEmDash] rather than 'NaN' or 'Infinity'.
String formatNumber(num? value, {int decimals = 2, bool grouped = true}) {
  if (value == null) return kEmDash;
  final d = value.toDouble();
  if (d.isNaN || d.isInfinite) return kEmDash;

  final negative = d < 0;
  final text = d.abs().toStringAsFixed(decimals);
  final dot = text.indexOf('.');
  final intPart = dot == -1 ? text : text.substring(0, dot);
  final fracPart = dot == -1 ? '' : text.substring(dot);

  final head = grouped ? _groupThousands(intPart) : intPart;
  return '${negative ? '-' : ''}$head$fracPart';
}

/// Drops trailing zeros: 12.50 -> '12.5', 12.00 -> '12'.
///
/// Used in text fields, where a pre-filled '12.00' is annoying to edit.
String formatCompactNumber(num? value, {int maxDecimals = 2}) {
  if (value == null) return '';
  final d = value.toDouble();
  if (d.isNaN || d.isInfinite) return '';

  var text = d.toStringAsFixed(maxDecimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

/// `$1,234.50`. The symbol is whatever the user typed in Settings, so it may
/// be 'Rs', 'PKR', '₹', '€' or empty.
String formatCurrency(num? value, String symbol, {int decimals = 2}) {
  final number = formatNumber(value, decimals: decimals);
  if (number == kEmDash) return kEmDash;
  if (symbol.isEmpty) return number;
  return '$symbol$number';
}

/// A value with its unit appended: `14.20 km/L`.
String formatWithUnit(num? value, String unitSymbol, {int decimals = 2}) {
  final number = formatNumber(value, decimals: decimals);
  if (number == kEmDash) return kEmDash;
  return '$number $unitSymbol';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `23 Aug 2026`
String formatDate(DateTime? date) {
  if (date == null) return kEmDash;
  return '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';
}

/// `23 Aug 2026, 14:05`
String formatDateTime(DateTime? date) {
  if (date == null) return kEmDash;
  return '${formatDate(date)}, ${_two(date.hour)}:${_two(date.minute)}';
}

/// `August 2026`
String formatMonthYear(DateTime? date) {
  if (date == null) return kEmDash;
  return '${_monthsLong[date.month - 1]} ${date.year}';
}

/// `Aug 26` — for chart axis labels, where space is scarce.
String formatMonthShort(DateTime? date) {
  if (date == null) return kEmDash;
  return '${_monthsShort[date.month - 1]} ${_two(date.year % 100)}';
}

/// `2026-08-23` — for filenames and CSV, where sort order matters.
String formatIsoDate(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

/// `2026-08-23_1405` — for backup filenames.
String formatFileStamp(DateTime date) =>
    '${formatIsoDate(date)}_${_two(date.hour)}${_two(date.minute)}';

/// `Today`, `Yesterday`, `5 days ago`, `3 months ago`, else an absolute date.
String formatRelativeDate(DateTime? date, {DateTime? now}) {
  if (date == null) return kEmDash;
  final reference = now ?? DateTime.now();

  final thatDay = DateTime(date.year, date.month, date.day);
  final thisDay = DateTime(reference.year, reference.month, reference.day);
  final days = thisDay.difference(thatDay).inDays;

  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 0) return formatDate(date);
  if (days < 30) return '$days days ago';
  if (days < 365) {
    final months = (days / 30).floor();
    return months == 1 ? '1 month ago' : '$months months ago';
  }
  return formatDate(date);
}

/// `4 days`, `1 day`, `about 2 months`.
String formatDuration(int? days) {
  if (days == null || days < 0) return kEmDash;
  if (days == 0) return 'same day';
  if (days == 1) return '1 day';
  if (days < 60) return '$days days';
  final months = (days / 30).round();
  return 'about $months months';
}
