import 'package:flutter/material.dart';

import '../acceptance_models.dart';
import '../l10n/app_locale.dart';
import 'app_card.dart';

Color acceptanceAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF80CBC4)
        : const Color(0xFF176B60);

class AcceptanceIntro extends StatelessWidget {
  const AcceptanceIntro(
      {super.key,
      required this.title,
      required this.subtitle,
      this.icon = Icons.fact_check_outlined,
      this.onTap,
      this.child});
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = acceptanceAccent(context);
    return AppCard(
      onTap: onTap,
      color: Color.alphaBlend(
          accent.withValues(alpha: .07), theme.colorScheme.surface),
      borderSide: BorderSide(color: accent.withValues(alpha: .22)),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: accent, size: 26)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.onSurface)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ])),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20, color: accent),
          ],
        ]),
        if (child != null) ...[const SizedBox(height: 20), child!],
      ]),
    );
  }
}

class AcceptanceJourney extends StatelessWidget {
  const AcceptanceJourney({super.key, this.run});
  final AcceptanceRun? run;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final value = run;
    final manual = value != null && !value.automatic;
    final labels = [
      if (!manual) l.acceptanceStagePlan,
      l.acceptanceStageEnvironment,
      l.acceptanceStageRun,
      l.acceptanceStageReview
    ];
    final icons = [
      if (!manual) Icons.edit_note_rounded,
      Icons.layers_outlined,
      Icons.play_arrow_rounded,
      Icons.fact_check_outlined
    ];
    final stage = value == null
        ? -1
        : value.phase == 'failed'
            ? value.testPlan != null && !value.testPlan!.approved
                ? 0
                : value.environment?.phase == 'failed'
                    ? (manual ? 0 : 1)
                    : labels.length - 2
            : value.terminal ||
                    value.autoVerdict != null ||
                    value.automation == 'awaiting_confirmation'
                ? labels.length - 1
                : value.running
                    ? labels.length - 2
                    : value.phase == 'planning'
                        ? 0
                        : manual
                            ? 0
                            : 1;
    final loading = value != null &&
        !value.terminal &&
        value.automation != 'failed' &&
        (value.phase == 'starting' ||
            value.environment?.busy == true ||
            (value.phase == 'planning' &&
                (value.testPlan == null ||
                    value.automation == 'revising_plan')) ||
            (value.running &&
                value.automatic &&
                !const ['awaiting_confirmation', 'completed']
                    .contains(value.automation)));
    final accent = acceptanceAccent(context);
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
            child: Semantics(
          selected: i == stage,
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: Divider(
                      color: i == 0
                          ? Colors.transparent
                          : theme.colorScheme.outlineVariant)),
              Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: i <= stage
                          ? accent.withValues(alpha: .14)
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: i == stage ? Border.all(color: accent) : null),
                  child: loading && i == stage
                      ? Padding(
                          padding: const EdgeInsets.all(7),
                          child: CircularProgressIndicator(
                            key: const Key('acceptance-journey-loading'),
                            strokeWidth: 2,
                            color: accent,
                          ))
                      : Icon(
                          i < stage && value?.phase != 'failed'
                              ? Icons.check_rounded
                              : icons[i],
                          size: 19,
                          color: i <= stage
                              ? accent
                              : theme.colorScheme.onSurfaceVariant)),
              Expanded(
                  child: Divider(
                      color: i == labels.length - 1
                          ? Colors.transparent
                          : theme.colorScheme.outlineVariant)),
            ]),
            const SizedBox(height: 8),
            Text(labels[i],
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: i == stage
                        ? accent
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        i == stage ? FontWeight.w700 : FontWeight.w500)),
          ]),
        )),
    ]);
  }
}
