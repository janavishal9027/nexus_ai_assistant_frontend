import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  /// The brand teal — the default accent, and the fallback everywhere.
  static const Color defaultAccent = Color(0xFF10A37F);

  /// Dark theme, tinted by the user's chosen [accent] (Settings →
  /// Personalization). Kept as a function rather than a getter so the accent
  /// can vary; callers that don't care can omit it.
  static ThemeData dark({Color accent = defaultAccent}) {
    return ThemeData(
      // Material 3 across every platform (desktop, Android, iOS, web).
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      primaryColor: accent,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: const Color(0xFF171717),
        onSurface: const Color(0xFFECECEC),
        outline: const Color(0xFF2D2D2D),
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D0D0D),
        elevation: 0,
        // Kill the Material 3 primary-colored tint that appears when content
        // scrolls under the app bar (was showing as a green header).
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      // Floating, dark, rounded toasts — not the default full-width light bar.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF212121),
        contentTextStyle: const TextStyle(color: Color(0xFFECECEC)),
        actionTextColor: accent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2F2F2F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFECECEC)),
      dividerColor: const Color(0xFF2D2D2D),
    );
  }

  /// Light theme, tinted by [accent]. Note this was dead code until the
  /// Personalization section shipped — `themeMode` was pinned to dark.
  static ThemeData light({Color accent = defaultAccent}) {
    return ThemeData(
      // Material 3 across every platform (desktop, Android, iOS, web).
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      primaryColor: accent,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: accent,
        surface: const Color(0xFFF7F7F8),
        onSurface: const Color(0xFF1A1A1A),
        outline: const Color(0xFFE5E5E5),
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.light().textTheme,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: accent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F7F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
      ),
      dividerColor: const Color(0xFFE5E5E5),
    );
  }
}
