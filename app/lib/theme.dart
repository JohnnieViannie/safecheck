import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // =========================
  // 🎨 Brand Colors
  // =========================
  static const Color primary = Color(0xFF1F6F8B);
  static const Color secondary = Color(0xFFC62839);
  static const Color accent = Color(0xFF6D4C41);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;

  static const Color onPrimary = Colors.white;
  static const Color onSecondary = Colors.white;

  // =========================
  // 📐 Layout
  // =========================
  static const double borderRadius = 12;

  static const EdgeInsets screenPadding = EdgeInsets.all(24);
  static const EdgeInsets sectionSpacing =
      EdgeInsets.symmetric(vertical: 14);

  // =========================
  // 🔘 Buttons
  // =========================
  static final ElevatedButtonThemeData elevatedButtonTheme =
      ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      minimumSize: const Size.fromHeight(56),
    ),
  );

  // =========================
  // 🌞 Light Theme
  // =========================
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      tertiary: accent,
      onTertiary: Colors.white,
      error: Colors.red,
      onError: Colors.white,
      surface: surface,
      onSurface: Colors.black87,
    ),

    scaffoldBackgroundColor: background,

    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      elevation: 0,
    ),

    elevatedButtonTheme: elevatedButtonTheme,

    // ✅ FIXED HERE
    cardTheme: CardThemeData(
      color: surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide.none,
      ),
    ),

    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        height: 1.2,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        color: Colors.black87,
      ),
    ),
  );

  // =========================
  // 🌙 Dark Theme
  // =========================
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      tertiary: accent,
      onTertiary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.black,
      surface: Color(0xFF121212),
      onSurface: Colors.white70,
    ),

    scaffoldBackgroundColor: const Color(0xFF0B0F14),

    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: onPrimary,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        minimumSize: const Size.fromHeight(56),
      ),
    ),

    // ✅ FIXED HERE
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1A1A),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade900,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide.none,
      ),
    ),

    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        height: 1.2,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        color: Colors.white70,
      ),
    ),
  );
}