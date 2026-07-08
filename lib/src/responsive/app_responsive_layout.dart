import '../settings/app_settings.dart';

class AppResponsiveLayout {
  static const double desktopBreakpoint = 900;
  static const double wideDesktopBreakpoint = 1200;
  static const double desktopSidebarWidth = 232;
  static const double desktopSidebarCollapsedWidth = 76;

  static bool isDesktopWidth(double width) => width >= desktopBreakpoint;

  static bool isWideDesktopWidth(double width) =>
      width >= wideDesktopBreakpoint;
}

Future<void> toggleDesktopNavigationCollapsed() {
  final next = !appSettingsController.settings.desktopNavigationCollapsed;
  return appSettingsController.save(
    appSettingsController.settings.copyWith(
      desktopNavigationCollapsed: next,
    ),
  );
}

Future<void> toggleDesktopHomeRailCollapsed() {
  final next = !appSettingsController.settings.desktopHomeRailCollapsed;
  return appSettingsController.save(
    appSettingsController.settings.copyWith(
      desktopHomeRailCollapsed: next,
    ),
  );
}

Future<void> toggleDesktopSessionRailCollapsed() {
  final next = !appSettingsController.settings.desktopSessionRailCollapsed;
  return appSettingsController.save(
    appSettingsController.settings.copyWith(
      desktopSessionRailCollapsed: next,
    ),
  );
}
