import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import 'desktop_shortcut.dart';

/// A visual key sequence shared by the guide, action hints and recorder.
class ShortcutKeycaps extends StatelessWidget {
  const ShortcutKeycaps({
    super.key,
    required this.labels,
    this.compact = false,
    this.foregroundColor,
  });

  final List<String> labels;
  final bool compact;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = foregroundColor ?? AppColors.textSoftFor(brightness);
    return Semantics(
      label: labels.join('+'),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) SizedBox(width: compact ? 3 : 5),
              Container(
                constraints: BoxConstraints(minWidth: compact ? 19 : 28),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 4 : 8,
                  vertical: compact ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.08),
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: color,
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ActionShortcutHint extends StatelessWidget {
  const ActionShortcutHint(
      {super.key, required this.action, this.foregroundColor});

  final DesktopShortcutAction action;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: appSettingsController,
        builder: (context, _) {
          final binding = resolveDesktopShortcut(
              appSettingsController.settings.desktopShortcuts, action);
          if (!supportsDesktopShortcuts || binding == null) {
            return const SizedBox.shrink();
          }
          return ShortcutKeycaps(
              labels: binding.keyLabels,
              compact: true,
              foregroundColor: foregroundColor);
        },
      );
}

String shortcutTooltip(String label, DesktopShortcutAction action) {
  final binding = resolveDesktopShortcut(
      appSettingsController.settings.desktopShortcuts, action);
  return supportsDesktopShortcuts && binding != null
      ? '$label · ${binding.label}'
      : label;
}
