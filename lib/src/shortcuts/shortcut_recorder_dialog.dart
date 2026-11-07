import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_locale.dart';
import 'desktop_shortcut.dart';
import 'shortcut_labels.dart';
import 'shortcut_keycaps.dart';
import '../theme/app_colors.dart';

class ShortcutRecorderDialog extends StatefulWidget {
  const ShortcutRecorderDialog({
    super.key,
    required this.action,
    required this.bindings,
  });

  final DesktopShortcutAction action;
  final Map<DesktopShortcutAction, DesktopKeyBinding?> bindings;

  @override
  State<ShortcutRecorderDialog> createState() => _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<ShortcutRecorderDialog> {
  DesktopKeyBinding? _binding;
  String? _error;

  KeyEventResult _record(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (DesktopKeyBinding.modifierKeys.contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    final binding = DesktopKeyBinding.fromEvent(event);
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !binding.control &&
        !binding.alt &&
        !binding.meta) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !binding.control &&
        !binding.alt &&
        !binding.meta &&
        !binding.shift) {
      if (_binding != null && _error == null) {
        Navigator.of(context).pop(_binding);
      }
      return KeyEventResult.handled;
    }
    String? error;
    if (!binding.isValid) {
      error = context.l10n.shortcutInvalid;
    } else {
      for (final action in DesktopShortcutAction.values) {
        if (action != widget.action &&
            resolveDesktopShortcut(widget.bindings, action) == binding) {
          error = context.l10n.shortcutConflict(action.label(context.l10n));
          break;
        }
      }
    }
    setState(() {
      _binding = binding;
      _error = error;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        onKeyEvent: _record,
        child: AlertDialog(
          title: Text(widget.action.label(context.l10n)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.shortcutRecordHelp),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 104),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.panelDeepFor(Theme.of(context).brightness),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _error != null
                            ? Theme.of(context).colorScheme.error
                            : AppColors.outlineStrongFor(
                                Theme.of(context).brightness)),
                  ),
                  child: Center(
                      child: _binding == null
                          ? Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.keyboard_outlined, size: 28),
                              const SizedBox(height: 8),
                              Text(context.l10n.shortcutPressKeys,
                                  textAlign: TextAlign.center),
                            ])
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: ShortcutKeycaps(
                                  labels: _binding!.keyLabels))),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel)),
            FilledButton(
              onPressed: _binding != null && _error == null
                  ? () => Navigator.pop(context, _binding)
                  : null,
              child: Text(context.l10n.save),
            ),
          ],
        ),
      );
}
