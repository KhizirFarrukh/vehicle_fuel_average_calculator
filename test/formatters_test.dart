import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_fuel_average_calculator/core/formatters.dart';
import 'package:vehicle_fuel_average_calculator/core/validators.dart';

void main() {
  group('formatNumber', () {
    test('groups thousands', () {
      expect(formatNumber(1234.5), '1,234.50');
      expect(formatNumber(1234567.891, decimals: 1), '1,234,567.9');
      expect(formatNumber(999), '999.00');
      expect(formatNumber(1000, decimals: 0), '1,000');
    });

    test('handles negatives and zero decimals', () {
      expect(formatNumber(-1234.5, decimals: 1), '-1,234.5');
      expect(formatNumber(0, decimals: 0), '0');
    });

    test('non-finite input becomes an em dash', () {
      expect(formatNumber(null), '—');
      expect(formatNumber(double.nan), '—');
      expect(formatNumber(double.infinity), '—');
    });

    test('grouping can be switched off', () {
      expect(formatNumber(1234.5, grouped: false), '1234.50');
    });
  });

  group('formatCompactNumber', () {
    test('drops trailing zeros', () {
      expect(formatCompactNumber(12.50), '12.5');
      expect(formatCompactNumber(12.00), '12');
      expect(formatCompactNumber(12.34), '12.34');
      expect(formatCompactNumber(0), '0');
    });

    test('null and non-finite become empty, for text fields', () {
      expect(formatCompactNumber(null), '');
      expect(formatCompactNumber(double.infinity), '');
    });

    test('honours a wider precision', () {
      expect(formatCompactNumber(2.8456, maxDecimals: 3), '2.846');
    });
  });

  group('currency', () {
    test('prefixes the symbol', () {
      expect(formatCurrency(1234.5, r'$'), r'$1,234.50');
      expect(formatCurrency(1234.5, 'Rs '), 'Rs 1,234.50');
    });

    test('copes with an empty symbol', () {
      expect(formatCurrency(10, ''), '10.00');
    });

    test('passes the em dash through', () {
      expect(formatCurrency(null, r'$'), '—');
    });
  });

  group('dates', () {
    final date = DateTime(2026, 8, 23, 14, 5);

    test('absolute formats', () {
      expect(formatDate(date), '23 Aug 2026');
      expect(formatDateTime(date), '23 Aug 2026, 14:05');
      expect(formatMonthYear(date), 'August 2026');
      expect(formatMonthShort(date), 'Aug 26');
      expect(formatIsoDate(date), '2026-08-23');
      expect(formatFileStamp(date), '2026-08-23_1405');
    });

    test('relative formats', () {
      final now = DateTime(2026, 8, 23, 9);
      expect(formatRelativeDate(DateTime(2026, 8, 23), now: now), 'Today');
      expect(formatRelativeDate(DateTime(2026, 8, 22), now: now), 'Yesterday');
      expect(formatRelativeDate(DateTime(2026, 8, 18), now: now), '5 days ago');
      expect(formatRelativeDate(DateTime(2026, 6, 23), now: now), '2 months ago');
      // Beyond a year, an absolute date is more use than "13 months ago".
      expect(formatRelativeDate(DateTime(2024, 1, 1), now: now), '1 Jan 2024');
    });

    test('durations read naturally', () {
      expect(formatDuration(0), 'same day');
      expect(formatDuration(1), '1 day');
      expect(formatDuration(9), '9 days');
      expect(formatDuration(90), 'about 3 months');
      expect(formatDuration(null), '—');
    });
  });

  group('parseFlexibleDouble', () {
    test('plain numbers', () {
      expect(parseFlexibleDouble('42'), 42);
      expect(parseFlexibleDouble('42.5'), 42.5);
      expect(parseFlexibleDouble('  42.5  '), 42.5);
    });

    test('thousands separators', () {
      expect(parseFlexibleDouble('1,234'), 1234);
      expect(parseFlexibleDouble('1,234.56'), closeTo(1234.56, 1e-9));
      expect(parseFlexibleDouble('1,234,567'), 1234567);
    });

    test('comma as the decimal mark', () {
      expect(parseFlexibleDouble('12,5'), closeTo(12.5, 1e-9));
      expect(parseFlexibleDouble('1.234,56'), closeTo(1234.56, 1e-9));
    });

    test('strips currency symbols and stray text', () {
      expect(parseFlexibleDouble(r'$1,234.50'), closeTo(1234.50, 1e-9));
      expect(parseFlexibleDouble('45.5 L'), closeTo(45.5, 1e-9));
    });

    test('rejects what is not a number', () {
      expect(parseFlexibleDouble(''), isNull);
      expect(parseFlexibleDouble(null), isNull);
      expect(parseFlexibleDouble('abc'), isNull);
    });
  });

  group('validators', () {
    test('required fields', () {
      expect(validateRequired('', 'Make'), 'Make is required');
      expect(validateRequired('   ', 'Make'), 'Make is required');
      expect(validateRequired('Toyota', 'Make'), isNull);
    });

    test('numbers', () {
      expect(validateNumber('', 'Volume'), 'Volume is required');
      expect(validateNumber('', 'Volume', required: false), isNull);
      expect(validateNumber('0', 'Volume'), 'Volume must be greater than zero');
      expect(validateNumber('0', 'Volume', allowZero: true), isNull);
      expect(validateNumber('-5', 'Volume'), 'Volume cannot be negative');
      expect(validateNumber('abc', 'Volume'), 'Enter a valid number for Volume');
      expect(validateNumber('45.5', 'Volume'), isNull);
    });

    test('number bounds', () {
      expect(validateNumber('2000', 'Tank', max: 1000), contains('at most'));
      expect(validateNumber('5', 'Tank', min: 10), contains('at least'));
    });

    test('year is optional but bounded', () {
      expect(validateYear(''), isNull);
      expect(validateYear(null), isNull);
      expect(validateYear('2019', currentYear: 2026), isNull);
      expect(validateYear('1850', currentYear: 2026), contains('between'));
      expect(validateYear('2040', currentYear: 2026), contains('between'));
      expect(validateYear('abc'), 'Enter a valid year');
    });
  });
}
