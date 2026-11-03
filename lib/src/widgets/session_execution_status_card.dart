import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../models.dart';
import '../theme/app_colors.dart';

class SessionExecutionStatusCard extends StatefulWidget {
  const SessionExecutionStatusCard(
      {super.key,
      required this.health,
      required this.onCheck,
      required this.onStopAndContinue,
      this.now});

  final ExecutionHealth health;
  final Future<bool> Function() onCheck;
  final Future<void> Function() onStopAndContinue;
  final DateTime Function()? now;

  @override
  State<SessionExecutionStatusCard> createState() =>
      _SessionExecutionStatusCardState();
}

class _SessionExecutionStatusCardState
    extends State<SessionExecutionStatusCard> {
  Timer? _timer;
  bool _checking = false;
  bool _recovering = false;
  DateTime? _quietUntil;
  String? _actionError;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SessionExecutionStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.health.lastProgressAt.isAfter(oldWidget.health.lastProgressAt)) {
      _quietUntil = null;
      _actionError = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _recovering) return;
    setState(() {
      _checking = true;
      _actionError = null;
    });
    try {
      final requested = await widget.onCheck();
      if (mounted && !requested) {
        setState(() => _actionError = context.l10n.executionCheckUnavailable);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = context.l10n.executionCheckFailed);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _stopAndContinue() async {
    if (_checking || _recovering) return;
    setState(() {
      _recovering = true;
      _actionError = null;
    });
    try {
      await widget.onStopAndContinue();
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = context.l10n.executionRecoveryFailed);
      }
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final health = widget.health;
    final now = _now;
    final attention = health.needsAttention(now) &&
        (_quietUntil == null || !now.isBefore(_quietUntil!));
    final elapsed = now.difference(health.lastProgressAt);
    final progress = elapsed.inMinutes > 0
        ? l10n.executionNoProgressMinutes(elapsed.inMinutes)
        : elapsed.inSeconds >= 15
            ? l10n.executionNoProgressSeconds(elapsed.inSeconds)
            : l10n.executionRecentProgress;
    final phase = switch (health.phase) {
      ExecutionPhase.starting => l10n.executionStarting,
      ExecutionPhase.thinking => l10n.executionThinking,
      ExecutionPhase.runningCommand => l10n.executionRunningCommand,
      ExecutionPhase.awaitingApproval => l10n.executionAwaitingApproval,
      ExecutionPhase.retrying => l10n.executionRetrying,
      ExecutionPhase.waitingForTool => l10n.executionWaitingForTool,
      ExecutionPhase.background => l10n.executionBackground,
      ExecutionPhase.unconfirmed => l10n.executionUnconfirmed,
    };
    final checkPending = health.checkStartedAt != null &&
        now.difference(health.checkStartedAt!).inSeconds < 30;
    final checking = _checking || checkPending;
    final providerReason = switch (health.checkError) {
      'provider_waiting_on_approval' => l10n.executionProviderApproval,
      'provider_waiting_on_user_input' => l10n.executionProviderInput,
      'provider_idle_without_turn_completion' => l10n.executionProviderIdle,
      'provider_system_error' || 'provider_thread_not_loaded' =>
        l10n.executionProviderError,
      _ => null,
    };
    final checkError = providerReason ?? (health.checkError == 'timeout' ||
            (health.checkStartedAt != null && !checkPending)
        ? l10n.executionCheckTimeout
        : health.checkError != null
            ? l10n.executionCheckFailed
            : null);
    final brightness = Theme.of(context).brightness;
    final color = attention
        ? AppColors.warningTextFor(brightness)
        : AppColors.mutedFor(brightness);
    return Container(
      key: const Key('session-execution-status'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: attention
            ? AppColors.warningSurfaceFor(brightness)
            : AppColors.surfaceAltFor(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: attention
                ? AppColors.warningBorderFor(brightness)
                : AppColors.outlineFor(brightness)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              attention
                  ? Icons.hourglass_disabled_outlined
                  : Icons.schedule_outlined,
              size: 18,
              color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(attention ? l10n.executionLongWait : phase,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w600)),
                Text(attention ? '$phase · $progress' : progress,
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          if (!attention)
            IconButton(
              key: const Key('session-execution-check'),
              tooltip: checking ? l10n.executionChecking : l10n.executionCheck,
              onPressed: checking || _recovering ? null : _check,
              icon: checking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 20),
            ),
        ]),
        if (_actionError ?? checkError case final String message)
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child:
                  Text(message, style: Theme.of(context).textTheme.bodySmall)),
        if (attention)
          Wrap(spacing: 8, runSpacing: 4, children: [
            TextButton.icon(
              key: const Key('session-execution-check'),
              onPressed: checking || _recovering ? null : _check,
              icon: checking
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 18),
              label:
                  Text(checking ? l10n.executionChecking : l10n.executionCheck),
            ),
            TextButton(
              key: const Key('session-execution-wait'),
              onPressed: _checking || _recovering
                  ? null
                  : () => setState(() {
                        _quietUntil = _now.add(const Duration(minutes: 5));
                        _actionError = null;
                      }),
              child: Text(l10n.executionKeepWaiting),
            ),
            OutlinedButton(
              key: const Key('session-execution-stop-continue'),
              onPressed: _checking || _recovering ? null : _stopAndContinue,
              child: Text(_recovering
                  ? l10n.executionRecovering
                  : l10n.executionStopContinue),
            ),
          ]),
      ]),
    );
  }
}
