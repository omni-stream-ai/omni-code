import 'package:flutter/widgets.dart';

import 'desktop_shortcut.dart';

class DesktopShortcutScope extends InheritedWidget {
  const DesktopShortcutScope(
      {super.key,
      required this.onInvoke,
      required this.routeShortcuts,
      required super.child});

  final ValueChanged<DesktopShortcutAction> onInvoke;
  final DesktopRouteShortcutRegistry routeShortcuts;

  static DesktopShortcutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopShortcutScope>();

  @override
  bool updateShouldNotify(DesktopShortcutScope oldWidget) =>
      onInvoke != oldWidget.onInvoke ||
      routeShortcuts != oldWidget.routeShortcuts;
}

/// Dispatches contextual actions only to the top route, even when its editor
/// does not have focus or the route has no name.
class DesktopRouteShortcutRegistry {
  final _handlers =
      <Route<dynamic>, Map<DesktopShortcutAction, VoidCallback>>{};

  VoidCallback register(
      Route<dynamic> route, Map<DesktopShortcutAction, VoidCallback> actions) {
    _handlers[route] = actions;
    return () {
      if (identical(_handlers[route], actions)) _handlers.remove(route);
    };
  }

  bool canInvoke(Route<dynamic>? route, DesktopShortcutAction action) =>
      _handlers[route]?.containsKey(action) ?? false;

  bool invoke(Route<dynamic>? route, DesktopShortcutAction action) {
    final callback = _handlers[route]?[action];
    if (callback == null) return false;
    callback();
    return true;
  }
}

class DesktopRouteShortcuts extends StatefulWidget {
  const DesktopRouteShortcuts(
      {super.key, required this.actions, required this.child});

  final Map<DesktopShortcutAction, VoidCallback> actions;
  final Widget child;

  @override
  State<DesktopRouteShortcuts> createState() => _DesktopRouteShortcutsState();
}

class _DesktopRouteShortcutsState extends State<DesktopRouteShortcuts> {
  VoidCallback? _unregister;

  void _register() {
    _unregister?.call();
    final route = ModalRoute.of(context);
    final registry = DesktopShortcutScope.maybeOf(context)?.routeShortcuts;
    _unregister =
        route == null ? null : registry?.register(route, widget.actions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(DesktopRouteShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
