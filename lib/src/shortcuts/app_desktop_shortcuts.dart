import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../responsive/app_responsive_layout.dart';
import '../services/desktop_window_service.dart';
import '../settings/app_settings.dart';
import '../widgets/new_session_flow.dart';
import 'desktop_search_dialog.dart';
import 'desktop_shortcut.dart';
import 'desktop_shortcut_scope.dart';
import 'shortcut_recorder_dialog.dart';

class DesktopShortcutNavigatorObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  Route<dynamic>? get topRoute => _routes.lastOrNull;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }
}

class AppDesktopShortcuts extends StatefulWidget {
  const AppDesktopShortcuts({
    super.key,
    required this.navigatorKey,
    required this.observer,
    required this.child,
    this.client,
    this.openWindow = openDesktopWindow,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final DesktopShortcutNavigatorObserver observer;
  final Widget child;
  final BridgeClient? client;
  final Future<void> Function() openWindow;

  @override
  State<AppDesktopShortcuts> createState() => _AppDesktopShortcutsState();
}

class _AppDesktopShortcutsState extends State<AppDesktopShortcuts> {
  bool _openingSearch = false;
  final _sessionOrigins = <Route<dynamic>?>{};
  final _routeShortcuts = DesktopRouteShortcutRegistry();

  @override
  void initState() {
    super.initState();
    // Run before EditableText's shortcuts so user bindings also work while
    // typing in the composer or a settings field.
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.dispose();
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (!supportsDesktopShortcuts ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<ShortcutRecorderDialog>() !=
        null) {
      return KeyEventResult.ignored;
    }
    final bindings = appSettingsController.settings.desktopShortcuts;
    for (final action in DesktopShortcutAction.values) {
      if (resolveDesktopShortcut(bindings, action)?.matches(event) != true) {
        continue;
      }
      if ((action == DesktopShortcutAction.previousSession ||
              action == DesktopShortcutAction.nextSession) &&
          !_routeShortcuts.canInvoke(widget.observer.topRoute, action)) {
        return KeyEventResult.ignored;
      }
      // Holding a shortcut should never create many windows or stack dialogs.
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null) return KeyEventResult.ignored;
      if (widget.observer.topRoute is PopupRoute &&
          action != DesktopShortcutAction.newWindow &&
          action != DesktopShortcutAction.goBack) {
        return KeyEventResult.handled;
      }
      unawaited(_invoke(action, navigator));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _invoke(
      DesktopShortcutAction action, NavigatorState navigator) async {
    final routeContext = navigator.overlay?.context;
    if (routeContext == null) return;
    try {
      if (_routeShortcuts.invoke(widget.observer.topRoute, action)) return;
      switch (action) {
        case DesktopShortcutAction.previousSession:
        case DesktopShortcutAction.nextSession:
          return;
        case DesktopShortcutAction.search:
          if (_openingSearch) return;
          _openingSearch = true;
          try {
            final result = await showDialog<Object>(
              context: routeContext,
              builder: (_) =>
                  DesktopSearchDialog(client: widget.client ?? bridgeClient),
            );
            if (!navigator.mounted) return;
            if (result is ProjectSummary) {
              unawaited(navigator.pushNamed(AppRoutes.project(result.id),
                  arguments: result));
            } else if (result is SessionSummary) {
              unawaited(navigator.pushNamed(
                  AppRoutes.session(result.projectId, result.id),
                  arguments: result));
            }
          } finally {
            _openingSearch = false;
          }
        case DesktopShortcutAction.newWindow:
          await widget.openWindow();
        case DesktopShortcutAction.newSession:
          // The flow lasts until its session closes. A new session page can
          // still start its own flow while the original page waits.
          final origin = widget.observer.topRoute;
          if (!_sessionOrigins.add(origin)) return;
          try {
            final match =
                AppRoutes.parse(widget.observer.topRoute?.settings.name);
            await startNewSessionFlow(
              routeContext,
              client: widget.client,
              initialProject: match.projectId == null
                  ? null
                  : (widget.client ?? bridgeClient)
                      .peekProject(match.projectId!),
            );
          } finally {
            _sessionOrigins.remove(origin);
          }
        case DesktopShortcutAction.settings:
          _navigate(navigator, AppRoutes.settings);
        case DesktopShortcutAction.home:
          _navigate(navigator, AppRoutes.home);
        case DesktopShortcutAction.projects:
          _navigate(navigator, AppRoutes.projects);
        case DesktopShortcutAction.toggleNavigation:
          await toggleDesktopNavigationCollapsed();
        case DesktopShortcutAction.goBack:
          await navigator.maybePop();
      }
    } catch (error) {
      if (!routeContext.mounted) return;
      final l10n = routeContext.l10n;
      ScaffoldMessenger.of(routeContext).showSnackBar(SnackBar(
        content: Text(action == DesktopShortcutAction.newWindow
            ? l10n.desktopWindowFailed('$error')
            : '$error'),
      ));
    }
  }

  void _navigate(NavigatorState navigator, String name) {
    if (widget.observer.topRoute?.settings.name == name) return;
    unawaited(
        navigator.pushNamedAndRemoveUntil(name, (route) => route.isFirst));
  }

  @override
  Widget build(BuildContext context) => DesktopShortcutScope(
        routeShortcuts: _routeShortcuts,
        onInvoke: (action) {
          final navigator = widget.navigatorKey.currentState;
          if (navigator != null) unawaited(_invoke(action, navigator));
        },
        child: widget.child,
      );
}
