// lib/utils/app_theme.dart
// Identical design system as the CSMS app — same brand, surfaces, status colours.
import 'package:flutter/material.dart';

class AppTheme {
  // ─── Brand Colours ──────────────────────────────────────────────────────────
  static const Color primary        = Color(0xFF00E5A0); // Electric green
  static const Color primaryDark    = Color(0xFF00B87A);

  // ─── Surface Colours ────────────────────────────────────────────────────────
  static const Color surface         = Color(0xFF0D1117);
  static const Color surfaceElevated = Color(0xFF161B22);
  static const Color surfaceCard     = Color(0xFF1C2330);
  static const Color border          = Color(0xFF30363D);

  // ─── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);

  // ─── Status Colours ─────────────────────────────────────────────────────────
  static const Color error       = Color(0xFFF85149);
  static const Color warning     = Color(0xFFD29922);
  static const Color info        = Color(0xFF58A6FF);
  static const Color charging    = Color(0xFF00E5A0);
  static const Color available   = Color(0xFF3FB950);
  static const Color unavailable = Color(0xFF8B949E);
  static const Color faulted     = Color(0xFFF85149);
  static const Color preparing   = Color(0xFFE3B341);
  static const Color finishing   = Color(0xFFD29922);
  static const Color reserved    = Color(0xFF58A6FF);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: surface,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primaryDark,
      surface: surfaceElevated,
      error: error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceElevated,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: textPrimary, fontSize: 18,
        fontWeight: FontWeight.w600, letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    cardTheme: CardThemeData(
      color: surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: surface,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textSecondary),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceElevated,
      selectedItemColor: primary,
      unselectedItemColor: textSecondary,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
    ),
    textTheme: const TextTheme(
      headlineLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleLarge:     TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleMedium:    TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
      bodyLarge:      TextStyle(color: textPrimary),
      bodyMedium:     TextStyle(color: textSecondary),
      bodySmall:      TextStyle(color: textSecondary, fontSize: 12),
      labelLarge:     TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
    ),
  );

  // ─── Status colour helper ────────────────────────────────────────────────────
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available':    return available;
      case 'charging':     return charging;
      case 'preparing':    return preparing;
      case 'finishing':    return finishing;
      case 'reserved':     return reserved;
      case 'unavailable':  return unavailable;
      case 'faulted':      return faulted;
      case 'suspendedevse':
      case 'suspendedev':  return warning;
      default:             return textSecondary;
    }
  }

  static Color onlineColor(bool isOnline) => isOnline ? available : textSecondary;
}
