import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

AppLocalizations approvalModeLocalizations(BuildContext context) =>
    AppLocalizations.of(context) ??
    lookupAppLocalizations(Localizations.localeOf(context));

String approvalModeLabel(BuildContext context, ApprovalMode mode) =>
    switch (mode) {
      ApprovalMode.manual =>
        approvalModeLocalizations(context).approvalModeManual,
      ApprovalMode.smart =>
        approvalModeLocalizations(context).approvalModeSmart,
      ApprovalMode.auto => approvalModeLocalizations(context).approvalModeAuto,
    };

/// A separate control beside model settings in every conversation composer.
class ApprovalModeSelector extends StatelessWidget {
  const ApprovalModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.enabled = true,
    this.saving = false,
  });

  final ApprovalMode value;
  final ValueChanged<ApprovalMode> onChanged;
  final String keyPrefix;
  final bool enabled, saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = approvalModeLocalizations(context);
    final muted = AppColors.mutedFor(theme.brightness);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.micro),
      child: PopupMenuButton<ApprovalMode>(
        tooltip: l10n.approvalMode,
        enabled: enabled && !saving,
        initialValue: value,
        requestFocus: false,
        onSelected: onChanged,
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
        color: AppColors.panelDeepFor(theme.brightness),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
        itemBuilder: (_) => [
          for (final mode in ApprovalMode.values)
            PopupMenuItem<ApprovalMode>(
              key: Key('$keyPrefix-option-${mode.name}'),
              value: mode,
              child: Semantics(
                selected: mode == value,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.micro),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(approvalModeLabel(context, mode),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: mode == value
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            )),
                        const SizedBox(height: AppSpacing.micro),
                        Text(
                            switch (mode) {
                              ApprovalMode.manual =>
                                l10n.approvalModeManualDescription,
                              ApprovalMode.smart =>
                                l10n.approvalModeSmartDescription,
                              ApprovalMode.auto =>
                                l10n.approvalModeAutoDescription,
                            },
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted)),
                      ],
                    )),
                    const SizedBox(width: AppSpacing.compact),
                    SizedBox(
                        width: 18,
                        child: mode == value
                            ? Icon(Icons.check_rounded,
                                size: 18, color: theme.colorScheme.tertiary)
                            : null),
                  ]),
                ),
              ),
            ),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.panelFor(theme.brightness).withValues(
              alpha: theme.brightness == Brightness.dark ? .44 : .58,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.compact,
              vertical: AppSpacing.textTight,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(
                approvalModeLabel(context, value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              )),
              const SizedBox(width: AppSpacing.micro),
              if (saving)
                SizedBox(
                    width: 12,
                    height: 12,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: muted))
              else
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: muted),
            ]),
          ),
        ),
      ),
    );
  }
}
