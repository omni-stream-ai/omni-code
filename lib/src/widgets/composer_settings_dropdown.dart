import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class ComposerSettingsSection<T extends Object> {
  const ComposerSettingsSection(
      {required this.value,
      required this.label,
      required this.key,
      required this.contentBuilder});
  final T value;
  final String label;
  final Key key;
  final WidgetBuilder contentBuilder;
}

/// The same anchored settings menu for session and workspace composers.
class ComposerSettingsDropdown<T extends Object> extends StatefulWidget {
  const ComposerSettingsDropdown(
      {super.key,
      required this.label,
      required this.controller,
      required this.sections,
      required this.selectedSection,
      required this.onSectionChanged,
      this.enabled = true,
      this.beforeOpen,
      this.maxButtonWidth = 168});

  final String label;
  final OverlayPortalController controller;
  final List<ComposerSettingsSection<T>> sections;
  final T? selectedSection;
  final ValueChanged<T?> onSectionChanged;
  final bool enabled;
  final Future<bool> Function()? beforeOpen;
  final double maxButtonWidth;

  @override
  State<ComposerSettingsDropdown<T>> createState() =>
      _ComposerSettingsDropdownState<T>();
}

class _ComposerSettingsDropdownState<T extends Object>
    extends State<ComposerSettingsDropdown<T>> {
  final _anchor = GlobalKey();
  bool _opening = false;

  @override
  void didUpdateWidget(covariant ComposerSettingsDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.enabled && !widget.enabled) ||
        oldWidget.controller != widget.controller) {
      final controller = oldWidget.controller;
      if (controller.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              controller.isShowing &&
              (!widget.enabled || controller != widget.controller)) {
            controller.hide();
            setState(() {});
          }
        });
      }
    }
  }

  Future<void> _toggle() async {
    if (!widget.enabled || _opening) return;
    if (widget.controller.isShowing) {
      _dismiss();
      return;
    }
    _opening = true;
    try {
      if (widget.beforeOpen != null && !await widget.beforeOpen!()) return;
      if (!mounted || !widget.enabled) return;
      widget.onSectionChanged(null);
      setState(() => widget.controller.show());
    } finally {
      _opening = false;
    }
  }

  void _dismiss() {
    setState(() => widget.controller.hide());
    widget.onSectionChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OverlayPortal(
        controller: widget.controller,
        overlayChildBuilder: _overlay,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                onTap: widget.enabled ? _toggle : null,
                borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                child: ConstrainedBox(
                    key: _anchor,
                    constraints:
                        BoxConstraints(maxWidth: widget.maxButtonWidth),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: AppColors.panelFor(theme.brightness)
                                .withValues(
                                    alpha: theme.brightness == Brightness.dark
                                        ? .44
                                        : .58),
                            borderRadius: BorderRadius.circular(
                                AppSpacing.radiusControl)),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.compact,
                                vertical: AppSpacing.textTight),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                  child: Text(widget.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: AppColors.mutedFor(
                                                  theme.brightness),
                                              fontWeight: FontWeight.w600))),
                              const SizedBox(width: AppSpacing.micro),
                              Icon(
                                  widget.controller.isShowing
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: AppColors.mutedFor(theme.brightness)),
                            ])))))));
  }

  Widget _overlay(BuildContext context) {
    final target = _anchor.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return const SizedBox.shrink();
    final rect = target.localToGlobal(Offset.zero) & target.size;
    final media = MediaQuery.of(context);
    final safeLeft = AppSpacing.screenX + media.padding.left;
    final safeRight =
        media.size.width - AppSpacing.screenX - media.padding.right;
    final safeTop = media.padding.top + AppSpacing.compact;
    final safeBottom =
        media.size.height - media.viewInsets.bottom - media.padding.bottom;
    final screenWidth = math.max(0.0, safeRight - safeLeft);
    final primaryWidth = math.min(156.0, screenWidth);
    final secondaryWidth = math.min(240.0, screenWidth);
    const gap = AppSpacing.micro;
    const maxHeight = 360.0;
    final below = safeBottom - rect.bottom - gap;
    final above = rect.top - gap - safeTop;
    final showBelow = below >= math.min(maxHeight, above);
    final height = (showBelow ? below : above).clamp(0.0, maxHeight);
    final left =
        rect.left.clamp(safeLeft, math.max(safeLeft, safeRight - primaryWidth));
    final top = showBelow ? rect.bottom + gap : null;
    final bottom = showBelow ? null : media.size.height - rect.top + gap;
    final section = widget.sections
        .where((s) => s.value == widget.selectedSection)
        .firstOrNull;
    final compact = screenWidth < primaryWidth + gap + secondaryWidth;
    final secondaryLeft = compact
        ? rect.left
            .clamp(safeLeft, math.max(safeLeft, safeRight - secondaryWidth))
        : left + primaryWidth + gap + secondaryWidth <= safeRight
            ? left + primaryWidth + gap
            : (left - gap - secondaryWidth)
                .clamp(safeLeft, safeRight - secondaryWidth);
    return Material(
        color: Colors.transparent,
        child: Stack(children: [
          Positioned.fill(
              child: GestureDetector(
                  behavior: HitTestBehavior.translucent, onTap: _dismiss)),
          if (!compact || section == null)
            Positioned(
                left: left.toDouble(),
                top: top,
                bottom: bottom,
                child: _panel(context,
                    width: primaryWidth,
                    height: height,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < widget.sections.length; i++) ...[
                            if (i > 0)
                              const SizedBox(height: AppSpacing.compact),
                            _section(context, widget.sections[i]),
                          ]
                        ]))),
          if (section != null)
            Positioned(
                left: secondaryLeft.toDouble(),
                top: top,
                bottom: bottom,
                child: _panel(context,
                    width: secondaryWidth,
                    height: height,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (compact)
                            TextButton.icon(
                                key: const Key('composer-settings-back'),
                                onPressed: () => widget.onSectionChanged(null),
                                icon: const Icon(Icons.arrow_back_rounded,
                                    size: 16),
                                label: Text(section.label)),
                          section.contentBuilder(context),
                        ]))),
        ]));
  }

  Widget _panel(BuildContext context,
          {required double width,
          required double height,
          required Widget child}) =>
      ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: width, maxWidth: width, maxHeight: height),
          child: DecoratedBox(
              decoration: BoxDecoration(
                  color: AppColors.surfaceFor(Theme.of(context).brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
                  border: Border.all(
                      color:
                          AppColors.outlineFor(Theme.of(context).brightness))),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.compact),
                  child: child)));

  Widget _section(BuildContext context, ComposerSettingsSection<T> section) {
    final theme = Theme.of(context);
    final selected = widget.selectedSection == section.value;
    Widget child = Material(
        color: Colors.transparent,
        child: InkWell(
            key: section.key,
            onTap: () =>
                widget.onSectionChanged(selected ? null : section.value),
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: selected
                        ? AppColors.panelFor(theme.brightness).withValues(
                            alpha:
                                theme.brightness == Brightness.dark ? .62 : .78)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusControl)),
                child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.compact),
                    child: Row(children: [
                      Expanded(
                          child: Text(section.label,
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600))),
                      Icon(Icons.chevron_right_rounded,
                          size: 16,
                          color: AppColors.mutedFor(theme.brightness)),
                    ])))));
    if (theme.platform != TargetPlatform.android &&
        theme.platform != TargetPlatform.iOS) {
      child = MouseRegion(
          onEnter: (_) {
            if (!selected) widget.onSectionChanged(section.value);
          },
          child: child);
    }
    return child;
  }
}

class ComposerSettingsOption extends StatelessWidget {
  const ComposerSettingsOption(
      {super.key,
      required this.label,
      required this.selected,
      this.subtitle,
      required this.onTap});
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.tertiary
        : AppColors.textFor(theme.brightness);
    return Material(
        color: Colors.transparent,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            child: Padding(
                padding: const EdgeInsets.all(AppSpacing.compact),
                child: Row(children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: color,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.mutedFor(theme.brightness))),
                      ],
                    ],
                  )),
                  const SizedBox(width: AppSpacing.compact),
                  SizedBox(
                      width: 18,
                      child: selected
                          ? Icon(Icons.check_rounded, size: 18, color: color)
                          : null),
                ]))));
  }
}
