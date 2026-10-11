import 'package:flutter/material.dart';

/// Pulsar VPN visual language — dark zinc, green accent, no purple glow.
abstract final class PulsarColors {
  static const bg = Color(0xFF09090B);
  static const surface = Color(0xFF18181B);
  static const surfaceElevated = Color(0xFF27272A);
  static const border = Color(0xFF3F3F46);
  static const text = Color(0xFFFAFAFA);
  static const textMuted = Color(0xFFA1A1AA);
  static const textDim = Color(0xFF71717A);
  static const accent = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);
  static const onAccent = Color(0xFF052E16);
}

ThemeData buildPulsarTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: PulsarColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: PulsarColors.bg,
      primary: Color(0xFFE4E4E7),
      secondary: PulsarColors.accent,
      error: PulsarColors.danger,
    ),
    useMaterial3: true,
    fontFamily: 'Roboto', // platform fallback; desktop uses system sans
    appBarTheme: const AppBarTheme(
      backgroundColor: PulsarColors.bg,
      foregroundColor: PulsarColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PulsarColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PulsarColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PulsarColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PulsarColors.accent, width: 1.4),
      ),
      labelStyle: const TextStyle(color: PulsarColors.textMuted),
      hintStyle: const TextStyle(color: PulsarColors.textDim),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PulsarColors.surfaceElevated,
    ),
    dividerColor: PulsarColors.border,
  );
}
