import '../../l10n/generated/app_localizations.dart';
import 'desktop_shortcut.dart';

extension DesktopShortcutLabel on DesktopShortcutAction {
  String label(AppLocalizations l10n) => switch (this) {
        DesktopShortcutAction.search => l10n.shortcutSearch,
        DesktopShortcutAction.newWindow => l10n.shortcutNewWindow,
        DesktopShortcutAction.newSession => l10n.shortcutNewSession,
        DesktopShortcutAction.settings => l10n.shortcutSettings,
        DesktopShortcutAction.home => l10n.shortcutHome,
        DesktopShortcutAction.projects => l10n.shortcutProjects,
        DesktopShortcutAction.toggleNavigation => l10n.shortcutToggleNavigation,
        DesktopShortcutAction.goBack => l10n.shortcutGoBack,
      };
}
