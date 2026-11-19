import 'package:flutter/material.dart';
import '../acceptance_models.dart';
import '../l10n/app_locale.dart';
import 'app_card.dart';

class AcceptanceRecoveryCard extends StatelessWidget {
  const AcceptanceRecoveryCard(
      {super.key,
      required this.run,
      this.onChat,
      this.onEditStartup,
      this.onEditEnvironment,
      this.onRetry});
  final AcceptanceRun run;
  final VoidCallback? onChat, onEditStartup, onEditEnvironment, onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repair = run.repair;
    final repairing =
        run.phase == 'starting' || run.automation == 'starting_app';
    return AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.build_circle_outlined),
        const SizedBox(width: 10),
        Expanded(
            child: Text(l.acceptanceRepairTitle,
                style: Theme.of(context).textTheme.titleMedium)),
        if (repair != null) Text('${repair.attempt} / ${repair.maxAttempts}'),
      ]),
      const SizedBox(height: 10),
      if (run.canRetry)
        Text(l.acceptanceRepairHint)
      else if (repairing)
        Text(l.acceptanceRepairActive),
      if (repair != null && repair.failures.isNotEmpty)
        ExpansionTile(
            key: const Key('acceptance-repair-history'),
            tilePadding: EdgeInsets.zero,
            title: Text(l.acceptanceErrorDetails),
            children: [
              for (final failure in repair.failures)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                            '${failure.attempt}. ${failure.error}'))),
            ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (run.repairSessionId != null)
          FilledButton.tonalIcon(
              key: const Key('acceptance-repair-chat'),
              onPressed: onChat,
              icon: const Icon(Icons.chat_outlined),
              label: Text(l.acceptanceRepairChat)),
        OutlinedButton.icon(
            key: const Key('acceptance-repair-startup'),
            onPressed: onEditStartup,
            icon: const Icon(Icons.terminal),
            label: Text(l.acceptanceRepairStartup)),
        OutlinedButton.icon(
            key: const Key('acceptance-repair-environment'),
            onPressed: onEditEnvironment,
            icon: const Icon(Icons.settings_outlined),
            label: Text(l.acceptanceRepairEnvironment)),
        if (run.canRetry)
          FilledButton.icon(
              key: const Key('acceptance-retry-run'),
              onPressed: onRetry,
              icon: const Icon(Icons.restart_alt),
              label: Text(l.acceptanceRepairRetry)),
      ]),
    ]));
  }
}
