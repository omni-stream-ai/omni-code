import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../models.dart';
import '../theme/app_spacing.dart';
import 'navigation_panel.dart';

class MobileNavigationDrawer extends StatelessWidget {
  const MobileNavigationDrawer({
    super.key,
    required this.activeRoute,
    required this.onNavigateHome,
    required this.onNavigateProjects,
    required this.onNavigateSettings,
    this.recentProjects = const [],
    this.recentSessions = const [],
    this.activeProjectId,
    this.activeSessionId,
    this.onOpenProject,
    this.onOpenSession,
    this.onNewSession,
    this.onNewSessionForProject,
    this.onNewSessionForSession,
    this.agentLabelFor,
  });

  final AppRouteKind activeRoute;
  final VoidCallback onNavigateHome;
  final VoidCallback onNavigateProjects;
  final VoidCallback onNavigateSettings;
  final List<ProjectSummary> recentProjects;
  final List<SessionSummary> recentSessions;
  final String? activeProjectId;
  final String? activeSessionId;
  final ValueChanged<ProjectSummary>? onOpenProject;
  final ValueChanged<SessionSummary>? onOpenSession;
  final VoidCallback? onNewSession;
  final ValueChanged<ProjectSummary>? onNewSessionForProject;
  final ValueChanged<SessionSummary>? onNewSessionForSession;
  final AgentLabelResolver? agentLabelFor;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.block,
            AppSpacing.block,
            AppSpacing.block,
            AppSpacing.screenBottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: NavigationPanel(
                  activeRoute: activeRoute,
                  onNavigateHome: onNavigateHome,
                  onNavigateProjects: onNavigateProjects,
                  onNavigateSettings: onNavigateSettings,
                  recentProjects: recentProjects,
                  recentSessions: recentSessions,
                  activeProjectId: activeProjectId,
                  activeSessionId: activeSessionId,
                  onOpenProject: onOpenProject,
                  onOpenSession: onOpenSession,
                  onNewSession: onNewSession,
                  onNewSessionForProject: onNewSessionForProject,
                  onNewSessionForSession: onNewSessionForSession,
                  agentLabelFor: agentLabelFor,
                  showRecentContent: activeRoute != AppRouteKind.home,
                  alwaysShowRecentMenus: true,
                  onBeforeNavigate: () => Navigator.of(context).pop(),
                  headerStyle: NavigationHeaderStyle.prominent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
