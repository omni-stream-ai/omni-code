import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_routes.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../settings/app_settings.dart';
import '../screens/keyboard_shortcuts_screen.dart';
import '../shortcuts/desktop_shortcut.dart';
import '../shortcuts/desktop_shortcut_scope.dart';
import '../shortcuts/recent_session_shortcuts.dart';
import '../shortcuts/shortcut_keycaps.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'desktop_window_header.dart';

typedef AgentLabelResolver = String Function(String agentId);

const _recentSessionScopeSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M4 6h16M7 12h10M10 18h4" fill="none" stroke="#000000"
    stroke-width="2" stroke-linecap="round"/>
</svg>
''';

class NavigationPanel extends StatelessWidget {
  const NavigationPanel({
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
    this.collapsed = false,
    this.showRecentContent = false,
    this.alwaysShowRecentMenus = false,
    this.onBeforeNavigate,
    this.headerStyle = NavigationHeaderStyle.compact,
    this.onToggleCollapsed,
    this.showDesktopShortcuts = false,
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
  final bool collapsed;
  final bool showRecentContent;
  final bool alwaysShowRecentMenus;
  final VoidCallback? onBeforeNavigate;
  final NavigationHeaderStyle headerStyle;
  final VoidCallback? onToggleCollapsed;
  final bool showDesktopShortcuts;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: appSettingsController,
        builder: (context, _) => _buildPanel(context),
      );

  Widget _buildPanel(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final muted = AppColors.mutedFor(brightness);
    final text = AppColors.textFor(brightness);
    final shortcutScope = DesktopShortcutScope.maybeOf(context);
    final integratedHeader = DesktopWindowHeaderScope.isActive(context);
    final showShortcuts = showDesktopShortcuts &&
        supportsDesktopShortcuts &&
        shortcutScope != null;
    final currentProjectOnly =
        appSettingsController.settings.recentSessionsCurrentProjectOnly;
    final visibleSessions = visibleRecentSessions(recentSessions,
        activeProjectId: activeProjectId,
        currentProjectOnly: currentProjectOnly);
    final hasRecentContent = showRecentContent &&
        (recentSessions.isNotEmpty || recentProjects.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!integratedHeader) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (!collapsed)
                Expanded(
                  child: Text(
                    'Omni Code',
                    style: _headerTextStyle(context, text),
                  ),
                ),
              if (onToggleCollapsed != null)
                IconButton(
                  tooltip: showShortcuts
                      ? shortcutTooltip(context.l10n.shortcutToggleNavigation,
                          DesktopShortcutAction.toggleNavigation)
                      : (collapsed
                          ? 'Expand navigation'
                          : 'Collapse navigation'),
                  onPressed: onToggleCollapsed,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.panelDeepFor(brightness),
                    foregroundColor: text,
                    minimumSize: const Size.square(36),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusControl,
                      ),
                    ),
                  ),
                  icon: Icon(
                    collapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                    size: 18,
                  ),
                ),
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(height: AppSpacing.compact),
            Text(
              'A quieter desk for active sessions.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.45,
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.section),
        ],
        if (showShortcuts) ...[
          if (!integratedHeader || MediaQuery.sizeOf(context).width < 320) ...[
            Tooltip(
              message: shortcutTooltip(
                  context.l10n.shortcutSearch, DesktopShortcutAction.search),
              child: OutlinedButton(
                key: const Key('navigation-open-search'),
                onPressed: _wrapAction(
                    () => shortcutScope.onInvoke(DesktopShortcutAction.search)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(38),
                  padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
                ),
                child: collapsed
                    ? const Icon(Icons.search_rounded, size: 18)
                    : Row(children: [
                        const Icon(Icons.search_rounded, size: 17),
                        const SizedBox(width: 8),
                        Expanded(child: Text(context.l10n.shortcutSearchEntry)),
                        const Expanded(
                            child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: ActionShortcutHint(
                                        action:
                                            DesktopShortcutAction.search)))),
                      ]),
              ),
            ),
            const SizedBox(height: AppSpacing.compact),
          ],
          Tooltip(
            message: shortcutTooltip(context.l10n.shortcutNewWindow,
                DesktopShortcutAction.newWindow),
            child: TextButton(
              key: const Key('navigation-new-window'),
              onPressed: _wrapAction(() =>
                  shortcutScope.onInvoke(DesktopShortcutAction.newWindow)),
              style: TextButton.styleFrom(
                  padding:
                      EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10)),
              child: collapsed
                  ? const Icon(Icons.open_in_new_rounded, size: 17)
                  : Row(children: [
                      const Icon(Icons.open_in_new_rounded, size: 17),
                      const SizedBox(width: 8),
                      Expanded(child: Text(context.l10n.shortcutNewWindow)),
                      const Expanded(
                          child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: ActionShortcutHint(
                                      action:
                                          DesktopShortcutAction.newWindow)))),
                    ]),
            ),
          ),
          const SizedBox(height: AppSpacing.compact),
        ],
        Tooltip(
            message: shortcutTooltip(
                context.l10n.shortcutHome, DesktopShortcutAction.home),
            child: NavigationPrimaryItem(
              collapsed: collapsed,
              label: context.l10n.appTitle,
              icon: Icons.home_outlined,
              onTap: _wrapAction(onNavigateHome),
              active: activeRoute == AppRouteKind.home,
            )),
        const SizedBox(height: AppSpacing.compact),
        Tooltip(
            message: shortcutTooltip(
                context.l10n.shortcutProjects, DesktopShortcutAction.projects),
            child: NavigationPrimaryItem(
              collapsed: collapsed,
              label: context.l10n.projectsTitle,
              icon: Icons.folder_open_outlined,
              onTap: _wrapAction(onNavigateProjects),
              active: activeRoute == AppRouteKind.projects ||
                  activeRoute == AppRouteKind.project ||
                  activeRoute == AppRouteKind.session,
            )),
        const SizedBox(height: AppSpacing.compact),
        Tooltip(
            message: shortcutTooltip(
                context.l10n.shortcutSettings, DesktopShortcutAction.settings),
            child: NavigationPrimaryItem(
              collapsed: collapsed,
              label: context.l10n.settingsTitle,
              icon: Icons.settings_outlined,
              onTap: _wrapAction(onNavigateSettings),
              active: activeRoute == AppRouteKind.settings,
            )),
        if (hasRecentContent) ...[
          const SizedBox(height: AppSpacing.section),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (recentSessions.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                            child: NavigationSectionLabel(
                          label: context.l10n.recentSessionsTitle,
                          collapsed: collapsed,
                          icon: Icons.schedule_rounded,
                        )),
                        if (!collapsed)
                          PopupMenuButton<bool>(
                            key: const Key('navigation-recent-session-scope'),
                            initialValue: currentProjectOnly,
                            tooltip:
                                '${context.l10n.recentSessionsScope}: ${currentProjectOnly ? context.l10n.recentSessionsCurrentProject : context.l10n.recentSessionsAllProjects}',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.panelDeepFor(brightness),
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusControl),
                                border: Border.all(
                                    color: AppColors.outlineFor(brightness)),
                              ),
                              child: RepaintBoundary(
                                key: const Key(
                                    'navigation-recent-session-scope-icon'),
                                child: SvgPicture.string(
                                  _recentSessionScopeSvg,
                                  width: 18,
                                  height: 18,
                                  colorFilter:
                                      ColorFilter.mode(text, BlendMode.srcIn),
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                            itemBuilder: (_) => [
                              _scopeMenuItem(context,
                                  value: true,
                                  selected: currentProjectOnly,
                                  label: context
                                      .l10n.recentSessionsCurrentProject),
                              _scopeMenuItem(context,
                                  value: false,
                                  selected: !currentProjectOnly,
                                  label:
                                      context.l10n.recentSessionsAllProjects),
                            ],
                            onSelected: (value) async {
                              try {
                                await appSettingsController.save(
                                    appSettingsController.settings.copyWith(
                                        recentSessionsCurrentProjectOnly:
                                            value));
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.maybeOf(context)
                                      ?.showSnackBar(
                                          SnackBar(content: Text('$error')));
                                }
                              }
                            },
                          ),
                      ],
                    ),
                    if (showShortcuts &&
                        !collapsed &&
                        activeRoute == AppRouteKind.session &&
                        activeSessionId != null &&
                        onOpenSession != null)
                      Row(children: [
                        for (final previous in [true, false])
                          Expanded(
                            child: _sessionShortcutButton(context,
                                previous: previous,
                                sessions: visibleSessions,
                                scope: shortcutScope),
                          ),
                      ]),
                    const SizedBox(height: AppSpacing.compact),
                    ...visibleSessions.map(
                      (session) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.compact,
                        ),
                        child: NavigationRecentItem(
                          label: session.title,
                          active: session.id == activeSessionId,
                          collapsed: collapsed,
                          unreadCount: session.unreadCount,
                          status: session.status,
                          alwaysShowMenu: alwaysShowRecentMenus,
                          icon: Icons.chat_bubble_outline_rounded,
                          menuChildren: _recentSessionMenuChildren(
                            context,
                            session,
                          ),
                          onTap: onOpenSession == null
                              ? null
                              : _wrapAction(() => onOpenSession!(session)),
                        ),
                      ),
                    ),
                  ],
                  if (recentProjects.isNotEmpty) ...[
                    if (recentSessions.isNotEmpty)
                      collapsed
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.compact,
                              ),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.outlineFor(brightness),
                              ),
                            )
                          : const SizedBox(height: AppSpacing.stack),
                    NavigationSectionLabel(
                      label: context.l10n.recentProjectsTitle,
                      collapsed: collapsed,
                      icon: Icons.folder_open_outlined,
                    ),
                    const SizedBox(height: AppSpacing.compact),
                    ...recentProjects.take(5).map(
                          (project) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.compact,
                            ),
                            child: NavigationRecentItem(
                              label: project.name,
                              active: project.id == activeProjectId,
                              collapsed: collapsed,
                              alwaysShowMenu: alwaysShowRecentMenus,
                              icon: Icons.folder_outlined,
                              menuChildren: _recentProjectMenuChildren(
                                context,
                                project,
                              ),
                              onTap: onOpenProject == null
                                  ? null
                                  : _wrapAction(() => onOpenProject!(project)),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (showShortcuts) ...[
          Tooltip(
            message: context.l10n.desktopShortcutsTitle,
            child: TextButton(
              key: const Key('navigation-shortcut-guide'),
              onPressed: _wrapAction(() => Navigator.of(context)
                  .pushNamed(KeyboardShortcutsScreen.routeName)),
              child: collapsed
                  ? const Icon(Icons.keyboard_outlined, size: 18)
                  : Row(children: [
                      const Icon(Icons.keyboard_outlined, size: 17),
                      const SizedBox(width: 8),
                      Flexible(child: Text(context.l10n.shortcutGuide)),
                    ]),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (onNewSession != null)
          Tooltip(
              message: shortcutTooltip(
                  context.l10n.newSession, DesktopShortcutAction.newSession),
              child: FilledButton(
                key: const Key('navigation-new-session-button'),
                onPressed: _wrapAction(onNewSession!),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(collapsed ? 46 : 48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.tileX),
                  backgroundColor: text,
                  foregroundColor: brightness == Brightness.dark
                      ? AppColors.darkPanel
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusControl),
                  ),
                ),
                child: collapsed
                    ? const Icon(Icons.add_rounded, size: 18)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Flexible(child: Text(context.l10n.newSession)),
                            if (showShortcuts &&
                                resolveDesktopShortcut(
                                        appSettingsController
                                            .settings.desktopShortcuts,
                                        DesktopShortcutAction.newSession) !=
                                    null) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: ActionShortcutHint(
                                          action:
                                              DesktopShortcutAction.newSession,
                                          foregroundColor:
                                              brightness == Brightness.dark
                                                  ? AppColors.darkPanel
                                                  : Colors.white))),
                            ],
                          ]),
              )),
      ],
    );
  }

  PopupMenuItem<bool> _scopeMenuItem(
    BuildContext context, {
    required bool value,
    required bool selected,
    required String label,
  }) {
    final brightness = Theme.of(context).brightness;
    final accent = AppColors.accentBlueFor(brightness);
    return PopupMenuItem<bool>(
      key: Key('navigation-session-scope-$value'),
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Semantics(
        selected: selected,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color:
                selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          ),
          child: Row(children: [
            SizedBox(
                width: 18,
                height: 18,
                child: selected
                    ? SvgPicture.string(
                        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="m5 12 4 4L19 6" fill="none" stroke="#000000" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
                        key: const Key(
                            'navigation-session-scope-selected-check'),
                        colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                        excludeFromSemantics: true,
                      )
                    : null),
            const SizedBox(width: 8),
            Flexible(
                child: Text(label,
                    style: TextStyle(
                      color: selected ? accent : AppColors.textFor(brightness),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ))),
          ]),
        ),
      ),
    );
  }

  TextStyle? _headerTextStyle(BuildContext context, Color text) {
    final textTheme = Theme.of(context).textTheme;
    return switch (headerStyle) {
      NavigationHeaderStyle.compact => textTheme.labelSmall?.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      NavigationHeaderStyle.prominent => textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: text,
        ),
    };
  }

  VoidCallback _wrapAction(VoidCallback action) {
    return () {
      onBeforeNavigate?.call();
      action();
    };
  }

  Widget _sessionShortcutButton(BuildContext context,
      {required bool previous,
      required List<SessionSummary> sessions,
      required DesktopShortcutScope scope}) {
    final action = previous
        ? DesktopShortcutAction.previousSession
        : DesktopShortcutAction.nextSession;
    final enabled = adjacentRecentSession(sessions,
            activeSessionId: activeSessionId!, previous: previous) !=
        null;
    final binding = resolveDesktopShortcut(
        appSettingsController.settings.desktopShortcuts, action);
    return Tooltip(
      message: shortcutTooltip(action.label(context.l10n), action),
      child: Semantics(
        label: action.label(context.l10n),
        child: TextButton(
          key: Key('navigation-${action.name}'),
          onPressed: enabled ? () => scope.onInvoke(action) : null,
          style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: binding == null
                  ? Icon(
                      previous
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16)
                  : ActionShortcutHint(action: action),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _recentSessionMenuChildren(
    BuildContext context,
    SessionSummary session,
  ) {
    final runtimeSessionRef = session.runtimeSessionRef;
    final children = <Widget>[
      NavigationMenuAction(
        label: context.l10n.newSession,
        icon: Icons.add_comment_outlined,
        onTap: onNewSessionForSession == null
            ? null
            : _wrapAction(() => onNewSessionForSession!(session)),
      ),
    ];
    if (runtimeSessionRef != null && runtimeSessionRef.isNotEmpty) {
      final agentLabel =
          agentLabelFor?.call(session.agentId) ?? session.agentId;
      children.add(
        NavigationMenuAction(
          label: context.l10n.copySessionId(agentLabel),
          icon: Icons.content_copy_rounded,
          onTap: () {
            Clipboard.setData(ClipboardData(text: runtimeSessionRef));
          },
        ),
      );
    }
    return children;
  }

  List<Widget> _recentProjectMenuChildren(
    BuildContext context,
    ProjectSummary project,
  ) {
    return [
      NavigationMenuAction(
        label: context.l10n.newSession,
        icon: Icons.add_comment_outlined,
        onTap: onNewSessionForProject == null
            ? null
            : _wrapAction(() => onNewSessionForProject!(project)),
      ),
    ];
  }
}

enum NavigationHeaderStyle {
  compact,
  prominent,
}

class NavigationSectionLabel extends StatelessWidget {
  const NavigationSectionLabel({
    super.key,
    required this.label,
    this.collapsed = false,
    this.icon,
  });

  final String label;
  final bool collapsed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (collapsed) {
      return Tooltip(
        message: label,
        child: Center(
          child: Icon(
            icon ?? Icons.more_horiz_rounded,
            size: 14,
            color: AppColors.mutedSoftFor(brightness),
          ),
        ),
      );
    }
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.mutedSoftFor(brightness),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
    );
  }
}

class NavigationRecentItem extends StatefulWidget {
  const NavigationRecentItem({
    super.key,
    required this.label,
    required this.active,
    this.collapsed = false,
    this.unreadCount = 0,
    this.status,
    this.alwaysShowMenu = false,
    this.icon,
    this.menuChildren = const [],
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool collapsed;
  final int unreadCount;
  final SessionStatus? status;
  final bool alwaysShowMenu;
  final IconData? icon;
  final List<Widget> menuChildren;
  final VoidCallback? onTap;

  @override
  State<NavigationRecentItem> createState() => _NavigationRecentItemState();
}

class _NavigationRecentItemState extends State<NavigationRecentItem> {
  final MenuController _menuController = MenuController();
  bool _hovered = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final statusLabel = switch (widget.status) {
      SessionStatus.running => context.l10n.sessionStatusRunning,
      SessionStatus.waiting => context.l10n.sessionStatusWaiting,
      SessionStatus.awaitingApproval =>
        context.l10n.sessionStatusAwaitingApproval,
      SessionStatus.failed => context.l10n.sessionStatusFailed,
      _ => null,
    };
    final statusColor = switch (widget.status) {
      SessionStatus.failed => AppColors.errorFor(brightness),
      SessionStatus.awaitingApproval ||
      SessionStatus.waiting =>
        AppColors.warningFor(brightness),
      SessionStatus.running => brightness == Brightness.dark
          ? Colors.green.shade400
          : Colors.green.shade600,
      _ => AppColors.accentBlueFor(brightness),
    };
    final showIndicator = statusLabel != null || widget.unreadCount > 0;
    final statusDot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: statusColor,
        shape: BoxShape.circle,
      ),
    );
    final statusIndicator = Semantics(label: statusLabel, child: statusDot);
    final textColor = widget.active
        ? AppColors.textFor(brightness)
        : _hovered
            ? AppColors.textSoftFor(brightness)
            : AppColors.mutedFor(brightness);
    final backgroundColor = widget.active
        ? AppColors.panelFor(brightness)
        : _hovered
            ? AppColors.panelDeepFor(brightness).withValues(alpha: 0.6)
            : Colors.transparent;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      child: Tooltip(
        message: statusLabel == null
            ? widget.label
            : '${widget.label} · $statusLabel',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal:
                  widget.collapsed ? AppSpacing.compact : AppSpacing.tileX,
              vertical: AppSpacing.compact,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
              border: widget.active
                  ? Border.all(color: AppColors.outlineFor(brightness))
                  : null,
            ),
            child: widget.collapsed
                ? Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Text(
                          _compactNavigationLabel(widget.label),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: textColor,
                                    fontWeight: widget.active
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    height: 1.05,
                                    fontSize: 10,
                                  ),
                        ),
                        if (showIndicator)
                          Positioned(
                            top: -3,
                            right: -5,
                            child: statusIndicator,
                          ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: textColor,
                                    fontWeight: widget.active
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ),
                      if (showIndicator) ...[
                        const SizedBox(width: AppSpacing.micro),
                        statusIndicator,
                      ],
                      if (widget.menuChildren.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.micro),
                        _NavigationRecentMoreButton(
                          controller: _menuController,
                          visible:
                              widget.alwaysShowMenu || _hovered || _menuOpen,
                          menuChildren: widget.menuChildren,
                          onOpenChanged: (isOpen) {
                            if (mounted) {
                              setState(() => _menuOpen = isOpen);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _NavigationRecentMoreButton extends StatelessWidget {
  const _NavigationRecentMoreButton({
    required this.controller,
    required this.visible,
    required this.menuChildren,
    required this.onOpenChanged,
  });

  final MenuController controller;
  final bool visible;
  final List<Widget> menuChildren;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return MenuAnchor(
      controller: controller,
      onOpen: () => onOpenChanged(true),
      onClose: () => onOpenChanged(false),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          AppColors.panelFor(brightness),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.compact,
            vertical: AppSpacing.compact,
          ),
          child: SizedBox(
            width: 188,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < menuChildren.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.micro),
                  menuChildren[i],
                ],
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 100),
        child: IgnorePointer(
          ignoring: !visible,
          child: IconButton(
            tooltip: context.l10n.more,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(
              width: 28,
              height: 28,
            ),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              foregroundColor: Colors.black,
              backgroundColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              shape: const CircleBorder(),
            ),
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            icon: const Icon(Icons.more_horiz_rounded, size: 17),
          ),
        ),
      ),
    );
  }
}

class NavigationMenuAction extends StatelessWidget {
  const NavigationMenuAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.compact,
            vertical: AppSpacing.compact,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: AppColors.mutedFor(brightness),
              ),
              const SizedBox(width: AppSpacing.compact),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactNavigationLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return '...';
  }

  final asciiWords = trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (asciiWords.length >= 2 &&
      asciiWords.every((part) => RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(part))) {
    return asciiWords.take(2).map((part) => part[0].toUpperCase()).join();
  }

  final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
  final runes = compact.runes.toList(growable: false);
  if (runes.length <= 4) {
    return compact;
  }
  return String.fromCharCodes(runes.take(4));
}

class NavigationPrimaryItem extends StatefulWidget {
  const NavigationPrimaryItem({
    super.key,
    required this.collapsed,
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final bool collapsed;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  State<NavigationPrimaryItem> createState() => _NavigationPrimaryItemState();
}

class _NavigationPrimaryItemState extends State<NavigationPrimaryItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final text = widget.active
        ? AppColors.textFor(brightness)
        : _hovered
            ? AppColors.textSoftFor(brightness)
            : AppColors.mutedSoftFor(brightness);
    final backgroundColor = widget.active
        ? AppColors.panelFor(brightness)
        : _hovered
            ? AppColors.panelDeepFor(brightness).withValues(alpha: 0.45)
            : Colors.transparent;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal:
                widget.collapsed ? AppSpacing.compact : AppSpacing.tileX,
            vertical: AppSpacing.compact,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCapsule),
            border: widget.active
                ? Border.all(color: AppColors.outlineFor(brightness))
                : null,
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 17, color: text),
              if (!widget.collapsed) ...[
                const SizedBox(width: AppSpacing.compact),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: text,
                          fontWeight:
                              widget.active ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
