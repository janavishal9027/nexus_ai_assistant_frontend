import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      primaryColor: const Color(0xFF10A37F),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF10A37F),
        secondary: Color(0xFF10A37F),
        surface: Color(0xFF171717),
        onSurface: Color(0xFFECECEC),
        outline: Color(0xFF2D2D2D),
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

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      primaryColor: const Color(0xFF10A37F),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF10A37F),
        secondary: Color(0xFF10A37F),
        surface: Color(0xFFF7F7F8),
        onSurface: Color(0xFF1A1A1A),
        outline: Color(0xFFE5E5E5),
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
