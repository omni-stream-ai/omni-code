import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

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
    this.collapsed = false,
    this.showRecentContent = false,
    this.onBeforeNavigate,
    this.headerStyle = NavigationHeaderStyle.compact,
    this.onToggleCollapsed,
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
  final bool collapsed;
  final bool showRecentContent;
  final VoidCallback? onBeforeNavigate;
  final NavigationHeaderStyle headerStyle;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final muted = AppColors.mutedFor(brightness);
    final text = AppColors.textFor(brightness);
    final hasRecentContent =
        showRecentContent && (recentSessions.isNotEmpty || recentProjects.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                tooltip: collapsed ? 'Expand navigation' : 'Collapse navigation',
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
        NavigationPrimaryItem(
          collapsed: collapsed,
          label: context.l10n.appTitle,
          icon: Icons.home_outlined,
          onTap: _wrapAction(onNavigateHome),
          active: activeRoute == AppRouteKind.home,
        ),
        const SizedBox(height: AppSpacing.compact),
        NavigationPrimaryItem(
          collapsed: collapsed,
          label: context.l10n.projectsTitle,
          icon: Icons.folder_open_outlined,
          onTap: _wrapAction(onNavigateProjects),
          active: activeRoute == AppRouteKind.projects ||
              activeRoute == AppRouteKind.project ||
              activeRoute == AppRouteKind.session,
        ),
        const SizedBox(height: AppSpacing.compact),
        NavigationPrimaryItem(
          collapsed: collapsed,
          label: context.l10n.settingsTitle,
          icon: Icons.settings_outlined,
          onTap: _wrapAction(onNavigateSettings),
          active: activeRoute == AppRouteKind.settings,
        ),
        if (hasRecentContent) ...[
          const SizedBox(height: AppSpacing.section),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (recentSessions.isNotEmpty) ...[
                    NavigationSectionLabel(
                      label: 'Recent sessions',
                      collapsed: collapsed,
                      icon: Icons.schedule_rounded,
                    ),
                    const SizedBox(height: AppSpacing.compact),
                    ...recentSessions.take(4).map(
                      (session) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.compact,
                        ),
                        child: NavigationRecentItem(
                          label: session.title,
                          active: session.id == activeSessionId,
                          collapsed: collapsed,
                          icon: Icons.chat_bubble_outline_rounded,
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
                      label: 'Recent projects',
                      collapsed: collapsed,
                      icon: Icons.folder_open_outlined,
                    ),
                    const SizedBox(height: AppSpacing.compact),
                    ...recentProjects.take(4).map(
                      (project) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.compact,
                        ),
                        child: NavigationRecentItem(
                          label: project.name,
                          active: project.id == activeProjectId,
                          collapsed: collapsed,
                          icon: Icons.folder_outlined,
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
        if (onNewSession != null)
          FilledButton(
            onPressed: _wrapAction(onNewSession!),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(collapsed ? 46 : 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.tileX),
              backgroundColor: text,
              foregroundColor: brightness == Brightness.dark
                  ? AppColors.darkPanel
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
              ),
            ),
            child: collapsed
                ? const Icon(Icons.add_rounded, size: 18)
                : Text(context.l10n.newSession),
          ),
      ],
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
    this.icon,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool collapsed;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  State<NavigationRecentItem> createState() => _NavigationRecentItemState();
}

class _NavigationRecentItemState extends State<NavigationRecentItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
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
        message: widget.label,
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
                    child: Text(
                      _compactNavigationLabel(widget.label),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textColor,
                            fontWeight:
                                widget.active ? FontWeight.w800 : FontWeight.w600,
                            height: 1.05,
                            fontSize: 10,
                          ),
                    ),
                  )
                : Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textColor,
                          fontWeight:
                              widget.active ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
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
