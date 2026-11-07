import 'dart:async';

import 'package:flutter/material.dart';

import '../acceptance_models.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import 'acceptance_ui.dart';

/// Both acceptance routes use the same approval presentation and submission flow.
mixin AcceptanceApprovalPresenter<T extends StatefulWidget> on State<T> {
  bool _approvalOpen = false;
  final Set<String> _presentedApprovals = {};

  Future<void> presentAcceptanceApprovals(BridgeClient client,
      List<AcceptanceRun> runs, Future<void> Function() refresh) async {
    final pending = {
      for (final run in runs.where((run) => !run.terminal))
        for (final approval in run.pendingApprovals)
          approval.key: (run, approval)
    };
    _presentedApprovals.retainAll(pending.keys);
    if (!mounted ||
        _approvalOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    for (final entry in pending.entries) {
      if (!mounted) return;
      if (_presentedApprovals.contains(entry.key)) continue;
      _presentedApprovals.add(entry.key);
      _approvalOpen = true;
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AcceptanceApprovalDialog(
            client: client,
            runId: entry.value.$1.id,
            approval: entry.value.$2,
          ),
        );
      } finally {
        _approvalOpen = false;
      }
      if (mounted) await refresh();
      return;
    }
  }
}

class AcceptanceApprovalDialog extends StatefulWidget {
  const AcceptanceApprovalDialog(
      {super.key,
      required this.client,
      required this.runId,
      required this.approval});
  final BridgeClient client;
  final String runId;
  final AcceptanceApproval approval;

  @override
  State<AcceptanceApprovalDialog> createState() =>
      _AcceptanceApprovalDialogState();
}

class _AcceptanceApprovalDialogState extends State<AcceptanceApprovalDialog> {
  Timer? _timer;
  bool _submitting = false, _polling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer =
        Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_poll()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _submitting) return;
    _polling = true;
    try {
      final run = await widget.client.getAcceptanceRun(widget.runId);
      if (mounted &&
          !_submitting &&
          (run.terminal ||
              !run.pendingApprovals
                  .any((item) => item.key == widget.approval.key))) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      // Keep the request available during temporary connection failures.
    } finally {
      _polling = false;
    }
  }

  Future<void> _submit(String choice) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.client.submitApproval(
          widget.approval.sessionId, widget.approval.request.requestId, choice);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = context.l10n.approvalSubmitFailed(error.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final request = widget.approval.request;
    final enabled = request.resolvable && !_submitting;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('acceptance-approval-dialog'),
        icon: Icon(Icons.rule_rounded, color: acceptanceAccent(context)),
        title: Text(l.agentAwaitingPermission('Agent')),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (request.reason?.isNotEmpty == true)
                      SelectableText(request.reason!),
                    if (request.command?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12)),
                          child: SelectableText(request.command!,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 13))),
                    ],
                    if (request.autoApprovalReason?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      SelectableText(request.autoApprovalReason!),
                    ],
                    if (!request.resolvable) ...[
                      const SizedBox(height: 12),
                      Text(l.desktopOnlyApproval),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    if (_submitting)
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator()),
                  ]),
            )),
        actions: [
          if (!request.resolvable)
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.close)),
          if (request.allowCancel)
            TextButton(
                onPressed: enabled ? () => _submit('cancel') : null,
                child: Text(l.cancel)),
          TextButton(
              onPressed: enabled ? () => _submit('decline') : null,
              child: Text(l.reject)),
          if (request.allowAcceptForSession)
            OutlinedButton(
                onPressed: enabled ? () => _submit('accept_for_session') : null,
                child: Text(l.approveForSession)),
          FilledButton(
              key: const Key('acceptance-approval-accept'),
              onPressed: enabled ? () => _submit('accept') : null,
              child: Text(l.approve)),
        ],
      ),
    );
  }
}
