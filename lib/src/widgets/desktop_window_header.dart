import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../shortcuts/desktop_shortcut.dart';
import '../shortcuts/desktop_shortcut_scope.dart';
import '../shortcuts/shortcut_keycaps.dart';
import '../theme/app_colors.dart';

class DesktopWindowHeaderScope extends InheritedWidget {
  const DesktopWindowHeaderScope({required super.child, super.key});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopWindowHeaderScope>() !=
      null;

  @override
  bool updateShouldNotify(DesktopWindowHeaderScope oldWidget) => false;
}

class DesktopWindowHeader extends StatelessWidget {
  const DesktopWindowHeader({
    required this.maximized,
    required this.onDrag,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    super.key,
  });

  final bool maximized;
  final VoidCallback onDrag, onMinimize, onToggleMaximize, onClose;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final muted = AppColors.mutedSoftFor(brightness);
    final l10n = context.l10n;
    final shortcuts = DesktopShortcutScope.maybeOf(context);
    return Material(
      key: const Key('desktop-window-header'),
      color: AppColors.boardFor(brightness),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: AppColors.outlineFor(brightness))),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                key: const Key('desktop-window-drag-region'),
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => onDrag(),
                onDoubleTap: onToggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (shortcuts == null)
                        Icon(Icons.terminal_rounded, size: 18, color: muted)
                      else
                        const SizedBox(width: 18),
                      if (width >= 640) ...[
                        const SizedBox(width: 9),
                        Text(l10n.appTitle,
                            style: TextStyle(
                              color: AppColors.textSoftFor(brightness),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ]),
                  ),
                ),
              ),
              if (shortcuts != null)
                Positioned(
                  left: 5,
                  top: 0,
                  bottom: 0,
                  child: _WindowButton(
                    key: const Key('desktop-window-navigation'),
                    label: l10n.shortcutToggleNavigation,
                    icon: Icons.view_sidebar_outlined,
                    onPressed: () => shortcuts
                        .onInvoke(DesktopShortcutAction.toggleNavigation),
                  ),
                ),
              if (width >= 320 && shortcuts != null)
                Center(
                  child: SizedBox(
                    width: (width - 360).clamp(36.0, 420.0),
                    height: 28,
                    child: TextButton(
                      key: const Key('desktop-window-search'),
                      onPressed: () =>
                          shortcuts.onInvoke(DesktopShortcutAction.search),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            horizontal: width >= 640 ? 10 : 0),
                        foregroundColor: muted,
                        backgroundColor: AppColors.panelDeepFor(brightness),
                        side:
                            BorderSide(color: AppColors.outlineFor(brightness)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_rounded, size: 15),
                          if (width >= 640) ...[
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(l10n.shortcutSearchHint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400))),
                            const SizedBox(width: 8),
                            ActionShortcutHint(
                                action: DesktopShortcutAction.search,
                                foregroundColor: muted),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _WindowButton(
                    key: const Key('desktop-window-minimize'),
                    label: l10n.minimizeWindow,
                    icon: Icons.remove_rounded,
                    onPressed: onMinimize,
                  ),
                  _WindowButton(
                    key: const Key('desktop-window-maximize'),
                    label: maximized ? l10n.restoreWindow : l10n.maximizeWindow,
                    icon: maximized
                        ? Icons.filter_none_rounded
                        : Icons.crop_square_rounded,
                    onPressed: onToggleMaximize,
                  ),
                  _WindowButton(
                    key: const Key('desktop-window-close'),
                    label: l10n.close,
                    icon: Icons.close_rounded,
                    onPressed: onClose,
                    destructive: true,
                  ),
                ]),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton(
      {required this.label,
      required this.icon,
      required this.onPressed,
      this.destructive = false,
      super.key});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Semantics(
      label: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        style: ButtonStyle(
          fixedSize: const WidgetStatePropertyAll(Size(40, 43)),
          minimumSize: const WidgetStatePropertyAll(Size.zero),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              destructive && states.contains(WidgetState.hovered)
                  ? AppColors.errorTextFor(brightness)
                  : AppColors.mutedSoftFor(brightness)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? destructive
                      ? AppColors.errorBgFor(brightness)
                      : AppColors.panelAltFor(brightness)
                  : Colors.transparent),
        ),
      ),
    );
  }
}
