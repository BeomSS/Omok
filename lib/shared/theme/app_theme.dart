import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Refined warm-wood and sumi-ink color system tailored for a classic 2D Omok app.
class AppTheme {
  const AppTheme._();

  static const Color boardWoodLight = Color(0xFFE7C27D);
  static const Color boardWoodDark = Color(0xFFD1A054);
  static const Color boardBorder = Color(0xFF7A5326);
  static const Color boardGrid = Color(0xFF3A2814);
  static const Color forbiddenCrimson = Color(0xFFD32F2F);
  static const Color winGold = Color(0xFFFFB300);

  static const Color inkPrimary = Color(0xFF1F1A14);
  static const Color warmSurface = Color(0xFFF7F2E8);
  static const Color warmCard = Color(0xFFFFFCF6);
  static const Color accentWood = Color(0xFF8B5A2B);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentWood,
      brightness: Brightness.light,
      surface: warmSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: warmSurface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: inkPrimary,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: warmCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accentWood.withValues(alpha: 0.14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: inkPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
