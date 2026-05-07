import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final resolvedTextColor = textColor ?? const Color(0xFFF8FAFC);
    final resolvedIconColor = iconColor ?? const Color(0xFFCBD5E1);
    final resolvedBackgroundColor = backgroundColor ?? const Color(0xFF0F172A);
    final resolvedBorderColor = borderColor ?? const Color(0xFF1E293B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: resolvedBackgroundColor,
        borderRadius: BorderRadius.circular(14),
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
            const SizedBox(width: 8),
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
