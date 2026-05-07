import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF38BDF8); // Sky 400
  static const Color secondary = Color(0xFF818CF8); // Indigo 400
  static const Color accent = Color(0xFF22C55E); // Green 500

  // Neutral Colors (Dark Mode)
  static const Color background = Color(0xFF020617); // Slate 950
  static const Color surface = Color(0xFF0F172A); // Slate 900
  static const Color surfaceVariant = Color(0xFF1E293B); // Slate 800
  static const Color outline = Color(0xFF334155); // Slate 700
  
  // Text Colors
  static const Color onBackground = Color(0xFFF8FAFC); // Slate 50
  static const Color onSurface = Color(0xFFF1F5F9); // Slate 100
  static const Color onSurfaceVariant = Color(0xFF94A3B8); // Slate 400
  static const Color muted = Color(0xFF64748B); // Slate 500

  // Semantic Colors
  static const Color success = Color(0xFF22C55E); // Green 500
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color error = Color(0xFFEF4444); // Red 500
  static const Color info = Color(0xFF38BDF8); // Sky 400

  static const ColorScheme darkColorScheme = ColorScheme.dark(
    primary: primary,
    onPrimary: Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    tertiary: accent,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: surfaceVariant,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    error: error,
    onError: Colors.white,
  );
}
