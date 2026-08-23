import 'package:flutter/material.dart';

/// Material 3 light and dark themes.
///
/// Replaces the original `primarySwatch: Colors.blue` (a Material 2 API) with
/// a seeded M3 colour scheme, which produces a coherent dark mode for free.
///
/// **Deliberately conservative.** Flutter has been migrating component themes
/// from `XTheme` to `XThemeData` (`CardTheme` -> `CardThemeData`,
/// `AppBarTheme` -> `AppBarThemeData`, `InputDecorationTheme` ->
/// `InputDecorationThemeData`, ...), and the accepted type differs by Flutter
/// version. This file therefore sets only fields whose types have been stable
/// for years, and the affected components are styled at the call site instead
/// — see [AppTheme.inputDecoration] and [AppTheme.cardShape].
class AppTheme {
  const AppTheme._();

  /// A deep teal. Reads as "instrument cluster" rather than "default blue app".
  static const Color seed = Color(0xFF00696D);

  static const Color _goodLight = Color(0xFF2E7D32);
  static const Color _goodDark = Color(0xFF81C784);
  static const Color _warnLight = Color(0xFFB26A00);
  static const Color _warnDark = Color(0xFFFFB74D);

  static const double cardRadius = 16;
  static const double fieldRadius = 12;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
        ),
      ),
    );
  }

  /// Shared text-field decoration, applied per field rather than through
  /// `ThemeData.inputDecorationTheme` (see the class doc).
  static InputDecoration inputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    String? helper,
    String? suffix,
    String? prefix,
    Widget? suffixIcon,
    Widget? prefixIcon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(fieldRadius);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      errorMaxLines: 3,
      suffixText: suffix,
      prefixText: prefix,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static RoundedRectangleBorder get cardShape => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
      );

  /// Background for the app's cards, matching what `cardTheme` would have set.
  static Color cardColor(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  /// Colour for "this number is good news", legible in both brightnesses.
  static Color good(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _goodDark : _goodLight;

  /// Colour for "have a second look at this".
  static Color warn(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _warnDark : _warnLight;
}
