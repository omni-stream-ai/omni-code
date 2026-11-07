import 'package:flutter/widgets.dart';

import 'desktop_shortcut.dart';

class DesktopShortcutScope extends InheritedWidget {
  const DesktopShortcutScope(
      {super.key, required this.onInvoke, required super.child});

  final ValueChanged<DesktopShortcutAction> onInvoke;

  static DesktopShortcutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopShortcutScope>();

  @override
  bool updateShouldNotify(DesktopShortcutScope oldWidget) =>
      onInvoke != oldWidget.onInvoke;
}
