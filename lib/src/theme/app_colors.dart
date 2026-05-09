import 'package:flutter/material.dart';

class AppColors {
  static const Color darkBoard = Color(0xFF17181D);
  static const Color darkBoardAlt = Color(0xFF121A24);
  static const Color darkScreen = Color(0xFF0E1319);
  static const Color darkPanel = Color(0xFF151B22);
  static const Color darkPanelAlt = Color(0xFF141B22);
  static const Color darkPanelDeep = Color(0xFF0F151B);
  static const Color darkStroke = Color(0xFF27313C);
  static const Color darkStrokeStrong = Color(0xFF31404D);
  static const Color darkText = Color(0xFFE7EDF2);
  static const Color darkTextSoft = Color(0xFFD7DEE5);
  static const Color darkMuted = Color(0xFF7F92A3);
  static const Color darkMutedSoft = Color(0xFF9AA9B8);
  static const Color darkSignal = Color(0xFF6EC7FF);
  static const Color darkAccentPurple = Color(0xFFA78BFA);
  static const Color darkProjectsAccent = darkAccentPurple;
  static const Color darkPrimary = Color(0xFFA3FF12);
  static const Color darkPrimaryOn = Color(0xFF09110A);
  static const Color darkSuccessBg = Color(0xFF132018);
  static const Color darkSuccessStroke = Color(0xFF285641);
  static const Color darkSuccessText = Color(0xFFE5FFF1);
  static const Color darkWarningBg = Color(0xFF291C12);
  static const Color darkWarningStroke = Color(0xFFA05A1B);
  static const Color darkWarningText = Color(0xFFFFD9A8);
  static const Color darkWarningMuted = Color(0xFFE8C9A2);
  static const Color darkDanger = Color(0xFFFF7A7A);
  static const Color darkIdle = Color(0xFF7F92A3);

  static const Color lightBoard = Color(0xFFF4F0E8);
  static const Color lightBoardAlt = Color(0xFFE8EEF3);
  static const Color lightScreen = Color(0xFFF3F0EA);
  static const Color lightPanel = Color(0xFFF7F9FC);
  static const Color lightPanelAlt = Color(0xFFE7EDF3);
  static const Color lightPanelDeep = Color(0xFFE7EDF3);
  static const Color lightStroke = Color(0xFFCDD6E0);
  static const Color lightStrokeStrong = Color(0xFFC7D0DA);
  static const Color lightText = Color(0xFF10161D);
  static const Color lightTextSoft = Color(0xFF1A2430);
  static const Color lightMuted = Color(0xFF748292);
  static const Color lightMutedSoft = Color(0xFF536170);
  static const Color lightSignal = Color(0xFF66C8FF);
  static const Color lightAccentBlue = Color(0xFF006CFF);
  static const Color lightAccentPurple = Color(0xFF8B5CF6);
  static const Color lightProjectsAccent = lightAccentPurple;
  static const Color lightPrimary = Color(0xFFB2FF2E);
  static const Color lightPrimaryOn = Color(0xFF0F151B);
  static const Color lightSuccessBg = Color(0xFFEAF7E9);
  static const Color lightSuccessStroke = Color(0xFF7DCCA0);
  static const Color lightSuccessText = Color(0xFF10321F);
  static const Color lightWarningBg = Color(0xFFFFF2E6);
  static const Color lightWarningStroke = Color(0xFFF2B57E);
  static const Color lightWarningText = Color(0xFF8C4A18);
  static const Color lightWarningMuted = Color(0xFF9A693E);
  static const Color lightDanger = Color(0xFFD85C5C);
  static const Color lightIdle = Color(0xFF8E98A4);

  static const Color primary = darkPrimary;
  static const Color onPrimary = darkPrimaryOn;
  static const Color background = darkScreen;
  static const Color surface = darkPanel;
  static const Color surfaceAlt = darkPanelAlt;
  static const Color surfaceDeep = darkPanelDeep;
  static const Color outline = darkStroke;
  static const Color outlineStrong = darkStrokeStrong;
  static const Color onBackground = darkText;
  static const Color onSurface = darkText;
  static const Color onSurfaceSoft = darkTextSoft;
  static const Color onSurfaceVariant = darkMutedSoft;
  static const Color muted = darkMuted;
  static const Color mutedSoft = darkMutedSoft;
  static const Color signal = darkSignal;
  static const Color success = darkSuccessText;
  static const Color warning = darkWarningText;
  static const Color error = darkDanger;
  static const Color idle = darkIdle;

  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary,
    onPrimary: darkPrimaryOn,
    secondary: darkSignal,
    onSecondary: darkPrimaryOn,
    error: darkDanger,
    onError: darkText,
    surface: darkPanel,
    onSurface: darkText,
  );

  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary,
    onPrimary: lightPrimaryOn,
    secondary: lightSignal,
    onSecondary: lightPrimaryOn,
    error: lightDanger,
    onError: Colors.white,
    surface: lightPanel,
    onSurface: lightText,
  );

  static Color boardFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBoard : lightBoard;

  static Color boardAltFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBoardAlt : lightBoardAlt;

  static Color screenFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkScreen : lightScreen;

  static Color panelFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPanel : lightPanel;

  static Color surfaceFor(Brightness brightness) => panelFor(brightness);

  static Color panelAltFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPanelAlt : lightPanelAlt;

  static Color surfaceAltFor(Brightness brightness) => panelAltFor(brightness);

  static Color panelDeepFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPanelDeep : lightPanelDeep;

  static Color surfaceDeepFor(Brightness brightness) =>
      panelDeepFor(brightness);

  static Color outlineFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkStroke : lightStroke;

  static Color outlineStrongFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkStrokeStrong : lightStrokeStrong;

  static Color textFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkText : lightText;

  static Color onSurfaceFor(Brightness brightness) => textFor(brightness);

  static Color textSoftFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkTextSoft : lightTextSoft;

  static Color onSurfaceSoftFor(Brightness brightness) =>
      textSoftFor(brightness);

  static Color mutedFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkMuted : lightMuted;

  static Color mutedSoftFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkMutedSoft : lightMutedSoft;

  static Color onSurfaceVariantFor(Brightness brightness) =>
      mutedSoftFor(brightness);

  static Color signalFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSignal : lightSignal;

  static Color accentBlueFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSignal : lightAccentBlue;

  static Color accentBlueOnFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrimaryOn : Colors.white;

  static Color accentPurpleFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccentPurple : lightAccentPurple;

  static Color projectsAccentFor(Brightness brightness) =>
      accentPurpleFor(brightness);

  static Color primaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrimary : lightPrimary;

  static Color onPrimaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrimaryOn : lightPrimaryOn;

  static Color successSurfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSuccessBg : lightSuccessBg;

  static Color successBorderFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSuccessStroke : lightSuccessStroke;

  static Color successTextFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSuccessText : lightSuccessText;

  static Color successFor(Brightness brightness) => successTextFor(brightness);

  static Color warningSurfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkWarningBg : lightWarningBg;

  static Color warningBorderFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkWarningStroke : lightWarningStroke;

  static Color warningTextFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkWarningText : lightWarningText;

  static Color warningFor(Brightness brightness) => warningTextFor(brightness);

  static Color warningMutedFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkWarningMuted : lightWarningMuted;

  static Color dangerFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkDanger : lightDanger;

  static Color errorFor(Brightness brightness) => dangerFor(brightness);

  static Color errorBgFor(Brightness brightness) => _blendWithSurface(
        errorFor(brightness),
        surfaceFor(brightness),
        brightness == Brightness.dark ? 0.16 : 0.10,
      );

  static Color errorBorderFor(Brightness brightness) => _blendWithSurface(
        errorFor(brightness),
        surfaceFor(brightness),
        brightness == Brightness.dark ? 0.42 : 0.22,
      );

  static Color errorIconFor(Brightness brightness) => errorFor(brightness);

  static Color errorTextFor(Brightness brightness) => errorFor(brightness);

  static Color idleFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkIdle : lightIdle;

  static Color skeletonBaseFor(Brightness brightness) => _blendWithSurface(
        textFor(brightness),
        surfaceFor(brightness),
        brightness == Brightness.dark ? 0.10 : 0.05,
      );

  static Color skeletonHighlightFor(Brightness brightness) => _blendWithSurface(
        textFor(brightness),
        surfaceFor(brightness),
        brightness == Brightness.dark ? 0.18 : 0.10,
      );

  static Color tintSurfaceFor(
    Brightness brightness,
    Color accent, {
    Color? base,
    double darkAlpha = 0.16,
    double lightAlpha = 0.10,
  }) {
    return _blendWithSurface(
      accent,
      base ?? surfaceFor(brightness),
      brightness == Brightness.dark ? darkAlpha : lightAlpha,
    );
  }

  static Color tintBorderFor(
    Brightness brightness,
    Color accent, {
    Color? base,
    double darkAlpha = 0.42,
    double lightAlpha = 0.22,
  }) {
    return _blendWithSurface(
      accent,
      base ?? outlineFor(brightness),
      brightness == Brightness.dark ? darkAlpha : lightAlpha,
    );
  }

  static LinearGradient boardGradientFor(Brightness brightness) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        boardFor(brightness),
        boardFor(brightness),
        boardAltFor(brightness),
      ],
      stops: const [0, 0.52, 1],
    );
  }

  static Color _blendWithSurface(Color accent, Color surface, double alpha) {
    return Color.alphaBlend(accent.withValues(alpha: alpha), surface);
  }
}
