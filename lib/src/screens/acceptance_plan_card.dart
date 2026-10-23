import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../widgets/app_card.dart';

class AcceptancePlanCard extends StatefulWidget {
  const AcceptancePlanCard(
      {super.key,
      required this.run,
      required this.client,
      required this.onUpdated});
  final AcceptanceRun run;
  final BridgeClient client;
  final ValueChanged<AcceptanceRun> onUpdated;
  @override
  State<AcceptancePlanCard> createState() => _AcceptancePlanCardState();
}

class _AcceptancePlanCardState extends State<AcceptancePlanCard> {
  final message = TextEditingController();
  bool busy = false;
  Object? error;
  bool get editable =>
      !busy &&
      widget.run.phase == 'planning' &&
      widget.run.automation == 'awaiting_plan_approval';
  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> operation(Future<AcceptanceRun> Function() action,
      {bool clearMessage = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      if (clearMessage) message.clear();
      widget.onUpdated(updated);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(AcceptanceTestCase? item) async {
    final plan = widget.run.testPlan!;
    final result = await showDialog<AcceptanceTestCase>(
        context: context, builder: (_) => _CaseEditor(item: item));
    if (result == null || !mounted) return;
    final cases = [...plan.cases];
    final index = cases.indexWhere((c) => c.id == result.id);
    if (index < 0) {
      cases.add(result);
    } else {
      cases[index] = result;
    }
    await operation(() => widget.client
        .editAcceptanceTestPlan(widget.run.id, plan.version, cases));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final plan = widget.run.testPlan!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final revising = widget.run.automation == 'revising_plan';
    return AppCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(plan.approved ? Icons.fact_check_rounded : Icons.edit_note_rounded,
            color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(l.acceptancePlanTitle,
                style: theme.textTheme.titleMedium)),
        Text('v${plan.version}', style: theme.textTheme.bodySmall),
      ]),
      const SizedBox(height: 8),
      Text(plan.approved ? l.acceptancePlanApproved : l.acceptancePlanHint,
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      for (final (index, item) in plan.cases.indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text('${index + 1}. ${item.title}',
                      style: theme.textTheme.titleSmall)),
              if (editable) ...[
                IconButton(
                    key: Key('acceptance-case-edit-${item.id}'),
                    tooltip: l.acceptancePlanEdit,
                    onPressed: () => edit(item),
                    icon: const Icon(Icons.edit_outlined, size: 20)),
                IconButton(
                    key: Key('acceptance-case-delete-${item.id}'),
                    tooltip: l.acceptancePlanDelete,
                    onPressed: plan.cases.length <= 1
                        ? null
                        : () => operation(() => widget.client
                            .editAcceptanceTestPlan(
                                widget.run.id,
                                plan.version,
                                plan.cases
                                    .where((c) => c.id != item.id)
                                    .toList())),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20)),
              ],
            ]),
            for (final (step, text) in item.steps.indexed)
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${step + 1}) $text')),
            const SizedBox(height: 8),
            Text('${l.acceptancePlanExpected}：${item.expected}',
                style: TextStyle(color: colors.primary)),
          ]),
        ),
      if (plan.notes.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(plan.notes, style: theme.textTheme.bodySmall)),
      if (editable)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                key: const Key('acceptance-case-add'),
                onPressed: plan.cases.length >= 32 ? null : () => edit(null),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.acceptancePlanAdd))),
      if (!plan.approved && widget.run.phase == 'planning') ...[
        const Divider(height: 24),
        Text(l.acceptancePlanChat, style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        for (final entry in widget.run.planMessages)
          Align(
              alignment: entry.role == 'user'
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: entry.role == 'user'
                          ? colors.primaryContainer
                          : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(entry.content,
                      style: TextStyle(
                          color: entry.role == 'user'
                              ? colors.onPrimaryContainer
                              : colors.onSurface)))),
        if (busy || revising) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (revising) Text(l.acceptancePlanRevising),
        ],
        const SizedBox(height: 8),
        TextField(
            key: const Key('acceptance-plan-message'),
            controller: message,
            enabled: editable,
            minLines: 2,
            maxLines: 4,
            maxLength: 4000,
            decoration: InputDecoration(
                hintText: l.acceptancePlanMessageHint,
                border: const OutlineInputBorder())),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                key: const Key('acceptance-plan-send'),
                onPressed: !editable
                    ? null
                    : () {
                        if (message.text.trim().isEmpty) return;
                        operation(
                            () => widget.client.reviseAcceptanceTestPlan(
                                widget.run.id,
                                plan.version,
                                message.text.trim()),
                            clearMessage: true);
                      },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(l.send))),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('$error', style: TextStyle(color: colors.error))),
        const SizedBox(height: 8),
        FilledButton.icon(
            key: const Key('acceptance-plan-confirm'),
            onPressed: !editable
                ? null
                : () => operation(() => widget.client
                    .confirmAcceptanceTestPlan(widget.run.id, plan.version)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l.acceptancePlanConfirm)),
      ],
    ]));
  }
}

class _CaseEditor extends StatefulWidget {
  const _CaseEditor({this.item});
  final AcceptanceTestCase? item;
  @override
  State<_CaseEditor> createState() => _CaseEditorState();
}

class _CaseEditorState extends State<_CaseEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.item?.title ?? '');
  late final steps =
      TextEditingController(text: widget.item?.steps.join('\n') ?? '');
  late final expected =
      TextEditingController(text: widget.item?.expected ?? '');
  @override
  void dispose() {
    title.dispose();
    steps.dispose();
    expected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String? required(String? text) =>
        text == null || text.trim().isEmpty ? l.acceptancePlanRequired : null;
    return AlertDialog(
        title: Text(
            widget.item == null ? l.acceptancePlanAdd : l.acceptancePlanEdit),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          key: const Key('acceptance-case-title'),
                          controller: title,
                          decoration: InputDecoration(
                              labelText: l.acceptancePlanCaseTitle),
                          maxLength: 160,
                          validator: required),
                      const SizedBox(height: 12),
                      TextFormField(
                          key: const Key('acceptance-case-steps'),
                          controller: steps,
                          decoration: InputDecoration(
                              labelText: l.acceptancePlanSteps,
                              hintText: l.acceptancePlanStepsHint),
                          minLines: 3,
                          maxLines: 7,
                          maxLength: 6000,
                          validator: (text) {
                            final lines = (text ?? '')
                                .split('\n')
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList();
                            return lines.isEmpty ||
                                    lines.length > 12 ||
                                    lines.any((s) => s.runes.length > 1000)
                                ? l.acceptancePlanStepsLimit
                                : null;
                          }),
                      const SizedBox(height: 12),
                      TextFormField(
                          key: const Key('acceptance-case-expected'),
                          controller: expected,
                          decoration: InputDecoration(
                              labelText: l.acceptancePlanExpected),
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 2000,
                          validator: required),
                    ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
          FilledButton(
              key: const Key('acceptance-case-save'),
              onPressed: () {
                if (form.currentState?.validate() != true) return;
                Navigator.pop(
                    context,
                    AcceptanceTestCase(
                        id: widget.item?.id ?? 'case_${const Uuid().v4()}',
                        title: title.text.trim(),
                        steps: steps.text
                            .split('\n')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList(),
                        expected: expected.text.trim()));
              },
              child: Text(l.save)),
        ]);
  }
}
