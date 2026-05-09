import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class CopyableMessage extends StatelessWidget {
  const CopyableMessage({
    super.key,
    required this.message,
    this.copyLabel = 'Copy',
    this.copiedLabel = 'Copied',
    this.showCopyButton = true,
    this.iconColor,
    this.textColor,
    this.backgroundColor,
    this.borderColor,
  });

  final String message;
  final String copyLabel;
  final String copiedLabel;
  final bool showCopyButton;
  final Color? iconColor;
  final Color? textColor;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final resolvedTextColor =
        textColor ?? Theme.of(context).colorScheme.onSurface;
    final resolvedIconColor = iconColor ?? AppColors.textSoftFor(brightness);
    final resolvedBackgroundColor =
        backgroundColor ?? AppColors.panelFor(brightness);
    final resolvedBorderColor = borderColor ?? AppColors.outlineFor(brightness);

    return Container(
      width: double.infinity,
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: resolvedBackgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: resolvedBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(
                color: resolvedTextColor,
                height: 1.4,
              ),
            ),
          ),
          if (showCopyButton) ...[
            const SizedBox(width: AppSpacing.compact),
            IconButton(
              tooltip: copyLabel,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: message));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(copiedLabel)),
                );
              },
              icon: Icon(Icons.copy, size: 18, color: resolvedIconColor),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
