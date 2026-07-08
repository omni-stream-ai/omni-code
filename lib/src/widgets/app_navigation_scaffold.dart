import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../models.dart';
import 'desktop_navigation_sidebar.dart';
import 'mobile_navigation_drawer.dart';
import 'navigation_panel.dart';

typedef NavigationBodyBuilder = Widget Function(
  BuildContext context,
  bool useDesktop,
  BoxConstraints constraints,
);

class AppNavigationScaffold extends StatelessWidget {
  const AppNavigationScaffold({
    super.key,
    required this.activeRoute,
    required this.onNavigateHome,
    required this.onNavigateProjects,
    required this.onNavigateSettings,
    required this.bodyBuilder,
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
    this.backgroundColor,
    this.floatingActionButton,
    this.appBar,
    this.desktopBreakpoint = 1180,
    this.desktopSidebarWidth = 232,
    this.desktopSidebarCollapsedWidth,
    this.desktopSidebarCollapsed = false,
    this.onToggleDesktopSidebar,
    this.showDesktopSidebar = true,
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
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;
  final double desktopBreakpoint;
  final double desktopSidebarWidth;
  final double? desktopSidebarCollapsedWidth;
  final bool desktopSidebarCollapsed;
  final VoidCallback? onToggleDesktopSidebar;
  final bool showDesktopSidebar;
  final NavigationBodyBuilder bodyBuilder;

  @override
  Widget build(BuildContext context) {
    final sidebarWidth =
        desktopSidebarCollapsedWidth != null && desktopSidebarCollapsed
            ? desktopSidebarCollapsedWidth!
            : desktopSidebarWidth;

    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      appBar: appBar,
      drawer: MobileNavigationDrawer(
        activeRoute: activeRoute,
        recentProjects: recentProjects,
        recentSessions: recentSessions,
        activeProjectId: activeProjectId,
        activeSessionId: activeSessionId,
        onNavigateHome: onNavigateHome,
        onNavigateProjects: onNavigateProjects,
        onNavigateSettings: onNavigateSettings,
        onOpenProject: onOpenProject,
        onOpenSession: onOpenSession,
        onNewSession: onNewSession,
        onNewSessionForProject: onNewSessionForProject,
        onNewSessionForSession: onNewSessionForSession,
        agentLabelFor: agentLabelFor,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useDesktop = constraints.maxWidth >= desktopBreakpoint;
            final useDesktopSidebar = useDesktop && showDesktopSidebar;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (useDesktopSidebar)
                  SizedBox(
                    width: sidebarWidth,
                    child: DesktopNavigationSidebar(
                      activeRoute: activeRoute,
                      recentProjects: recentProjects,
                      recentSessions: recentSessions,
                      activeProjectId: activeProjectId,
                      activeSessionId: activeSessionId,
                      onNavigateHome: onNavigateHome,
                      onNavigateProjects: onNavigateProjects,
                      onNavigateSettings: onNavigateSettings,
                      onOpenProject: onOpenProject,
                      onOpenSession: onOpenSession,
                      onNewSession: onNewSession,
                      onNewSessionForProject: onNewSessionForProject,
                      onNewSessionForSession: onNewSessionForSession,
                      agentLabelFor: agentLabelFor,
                      collapsed: desktopSidebarCollapsed,
                      onToggleCollapsed: onToggleDesktopSidebar,
                    ),
                  ),
                Expanded(
                  child: bodyBuilder(context, useDesktopSidebar, constraints),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
