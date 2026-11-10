import 'package:flutter/widgets.dart';

import '../models.dart';
import '../settings/app_settings.dart';
import 'desktop_shortcut.dart';
import 'desktop_shortcut_scope.dart';

/// Shared by the sidebar and its shortcuts: filter first, then show five.
List<SessionSummary> visibleRecentSessions(
  List<SessionSummary> sessions, {
  required String? activeProjectId,
  required bool currentProjectOnly,
}) =>
    sessions
        .where((session) =>
            !currentProjectOnly ||
            activeProjectId == null ||
            session.projectId == activeProjectId)
        .take(5)
        .toList(growable: false);

SessionSummary? adjacentRecentSession(
  List<SessionSummary> visibleSessions, {
  required String activeSessionId,
  required bool previous,
}) {
  if (visibleSessions.isEmpty) return null;
  final index =
      visibleSessions.indexWhere((session) => session.id == activeSessionId);
  // A session opened from search or a deep link may not be in the recent five.
  if (index < 0) return previous ? visibleSessions.last : visibleSessions.first;
  final target = index + (previous ? -1 : 1);
  return target < 0 || target >= visibleSessions.length
      ? null
      : visibleSessions[target];
}

class RecentSessionShortcuts extends StatelessWidget {
  const RecentSessionShortcuts({
    super.key,
    required this.activeProjectId,
    required this.activeSessionId,
    required this.recentSessions,
    required this.onOpenSession,
    required this.child,
  });

  final String activeProjectId;
  final String activeSessionId;
  final List<SessionSummary> recentSessions;
  final ValueChanged<SessionSummary> onOpenSession;
  final Widget child;

  void _move({required bool previous}) {
    final target = adjacentRecentSession(
      visibleRecentSessions(recentSessions,
          activeProjectId: activeProjectId,
          currentProjectOnly:
              appSettingsController.settings.recentSessionsCurrentProjectOnly),
      activeSessionId: activeSessionId,
      previous: previous,
    );
    if (target != null) onOpenSession(target);
  }

  @override
  Widget build(BuildContext context) => DesktopRouteShortcuts(
        actions: {
          DesktopShortcutAction.previousSession: () => _move(previous: true),
          DesktopShortcutAction.nextSession: () => _move(previous: false),
        },
        child: child,
      );
}
