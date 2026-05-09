import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  static const String displayFontFamily = 'JetBrains Mono';
  static const String bodyFontFamily = 'JetBrains Mono';
  static const List<String> monoFontFamilyFallback = <String>['monospace'];

  static ThemeData get darkTheme => _buildTheme(AppColors.darkColorScheme);

  static ThemeData get lightTheme => _buildTheme(AppColors.lightColorScheme);

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final brightness = colorScheme.brightness;
    final accentBlue = AppColors.accentBlueFor(brightness);
    final panel = AppColors.panelFor(brightness);
    final panelAlt = AppColors.panelAltFor(brightness);
    final panelDeep = AppColors.panelDeepFor(brightness);
    final outline = AppColors.outlineFor(brightness);
    final outlineStrong = AppColors.outlineStrongFor(brightness);
    final softText = AppColors.textSoftFor(brightness);
    final muted = AppColors.mutedFor(brightness);
    final mutedSoft = AppColors.mutedSoftFor(brightness);

    final textTheme = TextTheme(
      headlineMedium: _textStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: colorScheme.onSurface,
        display: true,
      ),
      titleLarge: _textStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: colorScheme.onSurface,
        display: true,
      ),
      titleMedium: _textStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: softText,
        display: true,
      ),
      bodyLarge: _textStyle(
        fontSize: 14,
        height: 1.45,
        color: colorScheme.onSurface,
      ),
      bodyMedium: _textStyle(
        fontSize: 12,
        height: 1.45,
        color: mutedSoft,
      ),
      bodySmall: _textStyle(
        fontSize: 11,
        height: 1.35,
        color: muted,
      ),
      labelLarge: _textStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        height: 1.25,
        color: softText,
        display: true,
      ),
      labelMedium: _textStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: softText,
        display: true,
      ),
      labelSmall: _textStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: muted,
        display: true,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.boardFor(brightness),
      canvasColor: AppColors.screenFor(brightness),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: panel,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          side: BorderSide(color: outline, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          side: BorderSide(color: outline),
        ),
      ),
      dividerColor: outline,
      iconTheme: IconThemeData(color: softText),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: panelDeep,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelAlt,
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          borderSide: BorderSide(color: outlineStrong),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.tileX,
          vertical: AppSpacing.tileY,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.onSurface,
        selectionHandleColor: colorScheme.onSurface,
        selectionColor: colorScheme.onSurface.withValues(alpha: 0.22),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accentBlue,
        linearTrackColor: panelDeep,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(42),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: panelDeep,
          foregroundColor: softText,
          minimumSize: const Size.fromHeight(42),
          side: BorderSide(color: outlineStrong),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlue,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: softText,
          backgroundColor: panelDeep,
          side: BorderSide(color: outlineStrong),
          minimumSize: const Size.square(34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        iconColor: muted,
        textColor: colorScheme.onSurface,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return mutedSoft;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.28);
          }
          return panelDeep;
        }),
      ),
    );
  }

  static TextStyle _textStyle({
    required double fontSize,
    FontWeight? fontWeight,
    required double height,
    required Color color,
    bool display = false,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
      fontFamily: display ? displayFontFamily : bodyFontFamily,
      fontFamilyFallback: monoFontFamilyFallback,
    );
  }
}
