import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppBackHeader extends StatelessWidget {
  const AppBackHeader({
    super.key,
    required this.title,
    this.onTap,
    this.titleStyle,
    this.tooltip,
    this.maxTitleLines = 1,
    this.titleOverflow = TextOverflow.ellipsis,
  });

  final String title;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final String? tooltip;
  final int maxTitleLines;
  final TextOverflow titleOverflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final backOverlayColor = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return AppColors.textSoftFor(brightness).withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return AppColors.textSoftFor(brightness).withValues(alpha: 0.08);
      }
      return null;
    });

    return Tooltip(
      message: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          overlayColor: backOverlayColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.micro,
              vertical: AppSpacing.textTight,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasBoundedWidth = constraints.hasBoundedWidth;
                final titleWidget = Text(
                  title,
                  style: titleStyle,
                  maxLines: maxTitleLines,
                  overflow: titleOverflow,
                  softWrap: false,
                );

                return Row(
                  mainAxisSize:
                      hasBoundedWidth ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: theme.iconTheme.color,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.compact),
                    if (hasBoundedWidth)
                      Flexible(child: titleWidget)
                    else
                      titleWidget,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
