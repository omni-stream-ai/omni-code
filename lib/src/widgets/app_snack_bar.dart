import 'package:flutter/material.dart';

/// Shared notification timing. Actions must not implicitly make success persistent.
class AppSnackBar extends SnackBar {
  AppSnackBar({
    super.key,
    required Widget content,
    SnackBarAction? action,
    bool isError = false,
    Duration? duration,
  }) : super(
          content: _NotificationContent(
              content: content, action: action, showClose: isError),
          persist: false,
          showCloseIcon: false,
          padding: isError || action != null
              ? const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4)
              : null,
          duration:
              duration ?? Duration(seconds: isError || action != null ? 8 : 4),
        );
}

class _NotificationContent extends StatelessWidget {
  const _NotificationContent(
      {required this.content, required this.action, required this.showClose});

  final Widget content;
  final SnackBarAction? action;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onInverseSurface;
    return Row(children: [
      Expanded(child: content),
      if (action != null) ...[
        const SizedBox(width: 8),
        action!,
      ],
      if (showClose) ...[
        const SizedBox(width: 4),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          style: IconButton.styleFrom(
            foregroundColor: color.withValues(alpha: .55),
            hoverColor: color.withValues(alpha: .06),
            highlightColor: color.withValues(alpha: .1),
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.close_rounded, size: 16),
        ),
      ],
    ]);
  }
}
