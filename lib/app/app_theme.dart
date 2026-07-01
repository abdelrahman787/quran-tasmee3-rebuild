/// App theme — Material Design 3 with a Quran/Islamic aesthetic.
///
/// Color palette inspired by traditional mushaf decoration:
///  - Primary: deep emerald green (associated with Islamic art)
///  - Secondary: warm gold (mushaf border illumination)
///  - Background: soft cream (parchment-like)
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Brand colors
  static const Color primaryGreen = Color(0xFF1B6B4C);
  static const Color lightGreen = Color(0xFF2D8A66);
  static const Color darkGreen = Color(0xFF0D4A33);
  static const Color goldAccent = Color(0xFFD4A843);
  static const Color goldLight = Color(0xFFE8C97A);
  static const Color parchment = Color(0xFFFBF8F0);
  static const Color parchmentDark = Color(0xFFF5EFE0);
  static const Color inkDark = Color(0xFF1A1A2E);
  static const Color inkMedium = Color(0xFF3D3D5C);

  // Recitation word colors (spec §8 matching rules)
  static const Color wordUnrevealed = Color(0xFFB0B0B0);     // gray — not yet recited
  static const Color wordRevealed = Color(0xFF1A1A2E);       // dark — correctly recited
  static const Color wordError = Color(0xFFD32F2F);           // red — confirmed wrong
  static const Color wordSoftError = Color(0xFFFF9800);       // orange — soft/attempt 2
  static const Color wordPronunciation = Color(0xFFFFC107);   // amber — flagged pronunciation
  static const Color wordCurrent = Color(0xFF1B6B4C);         // green — current cursor position

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      primary: primaryGreen,
      secondary: goldAccent,
      surface: parchment,
      onSurface: inkDark,
    ),
    scaffoldBackgroundColor: parchment,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: goldAccent.withValues(alpha: 0.2), width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryGreen,
        side: const BorderSide(color: primaryGreen),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: primaryGreen,
      unselectedItemColor: Color(0xFF888888),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: parchmentDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: goldAccent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: inkDark,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: inkDark,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: inkMedium,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: inkMedium,
      ),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: inkDark,
      ),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      brightness: Brightness.dark,
      primary: lightGreen,
      secondary: goldLight,
      surface: const Color(0xFF1A1A2E),
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFF121220),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1A2E),
      selectedItemColor: lightGreen,
      unselectedItemColor: Color(0xFF666688),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );
}
