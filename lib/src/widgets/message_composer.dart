import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The text input and toolbar shared by session and workspace conversations.
/// Callers own drafts, attachments, commands, and sending; wrappers can attach
/// shortcut handling and suggestion overlays without duplicating the editor.
class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.hintText,
    required this.actions,
    this.settings = const [],
    this.inputKey,
    this.focusNode,
    this.enabled = true,
    this.expanded = true,
    this.prominent = false,
    this.maxLines = 4,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.inputWrapper,
    this.surfaceColor,
    this.borderColor,
  });

  final TextEditingController controller;
  final String hintText;
  final List<Widget> actions, settings;
  final Key? inputKey;
  final FocusNode? focusNode;
  final bool enabled, expanded, prominent;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget Function(Widget input)? inputWrapper;
  final Color? surfaceColor, borderColor;

  static ButtonStyle actionStyle(BuildContext context, {bool primary = false}) {
    final brightness = Theme.of(context).brightness;
    return IconButton.styleFrom(
      backgroundColor:
          primary ? AppColors.primaryFor(brightness) : Colors.transparent,
      foregroundColor: primary
          ? AppColors.onPrimaryFor(brightness)
          : AppColors.textSoftFor(brightness),
      disabledForegroundColor: AppColors.mutedFor(brightness),
      disabledBackgroundColor: Colors.transparent,
      minimumSize: Size.square(primary ? 34 : 32),
      fixedSize: Size.square(primary ? 34 : 32),
      padding: EdgeInsets.zero,
      side: BorderSide.none,
      shape: const CircleBorder(),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = Theme.of(context).brightness;
    final field = TextField(
      key: inputKey,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      maxLines: expanded ? maxLines : 1,
      minLines: prominent && expanded && maxLines > 1 ? 2 : 1,
      style: prominent
          ? theme.textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.5)
          : null,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: prominent
            ? theme.textTheme.bodyLarge?.copyWith(
                fontSize: 14,
                height: 1.5,
                color: AppColors.mutedSoftFor(brightness))
            : null,
        counterText: '',
        filled: false,
        contentPadding: EdgeInsetsDirectional.only(
          start: prominent ? 18 : AppSpacing.card,
          end: prominent
              ? 18
              : expanded
                  ? AppSpacing.card
                  : AppSpacing.micro,
          top: prominent
              ? 18
              : expanded
                  ? AppSpacing.stack
                  : AppSpacing.compact,
          bottom: prominent ? 12 : AppSpacing.compact,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
      ),
    );
    final input = inputWrapper?.call(field) ?? field;
    final actionRow = Row(mainAxisSize: MainAxisSize.min, children: actions);
    return SizedBox(
      height: expanded ? null : 48,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: surfaceColor ?? AppColors.panelDeepFor(brightness),
          borderRadius:
              BorderRadius.circular(prominent ? 22 : AppSpacing.radiusPanel),
          border: Border.all(
              color: borderColor ?? AppColors.outlineStrongFor(brightness)),
          boxShadow: prominent
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(
                          alpha: brightness == Brightness.dark ? .12 : .035),
                      blurRadius: 24,
                      offset: const Offset(0, 6)),
                ]
              : null,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
              0,
              0,
              prominent ? 8 : AppSpacing.micro,
              prominent ? 8 : AppSpacing.micro),
          child: expanded
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  input,
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.compact, AppSpacing.micro, 0, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: prominent
                            ? Colors.transparent
                            : AppColors.panelFor(brightness).withValues(
                                alpha:
                                    brightness == Brightness.dark ? .18 : .3),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusControl),
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            AppSpacing.compact,
                            AppSpacing.micro,
                            AppSpacing.micro,
                            AppSpacing.micro),
                        child: FocusTraversalGroup(
                          policy: OrderedTraversalPolicy(),
                          child: SizedBox(
                              height: 36,
                              child: Row(children: [
                                Expanded(
                                    child: Row(children: [
                                  for (final setting in settings)
                                    Flexible(child: setting),
                                ])),
                                actionRow,
                              ])),
                        ),
                      ),
                    ),
                  ),
                ])
              : Row(children: [
                  Expanded(child: input),
                  FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(), child: actionRow),
                ]),
        ),
      ),
    );
  }
}
