import 'dart:async';

import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../../l10n/generated/app_localizations.dart';
import '../models.dart';
import 'notification_service.dart';
import 'push_service.dart';

class SessionEventService extends NavigatorObserver {
  SessionEventService({
    BridgeClient? client,
    NotificationService? notifications,
  })  : _client = client ?? bridgeClient,
        _notifications = notifications ?? notificationService;

  final BridgeClient _client;
  final NotificationService _notifications;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _reconnectTimer;
  Future<void>? _synchronizeInFlight;
  final Map<String, Timer> _refreshTimers = {};
  final Set<String> _refreshesInFlight = {};
  final Set<String> _refreshesPending = {};
  final Map<String, String> _notifiedApprovalRequestIds = {};
  final Map<String, (SessionSummary, ApprovalRequest)> _approvalDialogQueue =
      {};
  final Set<String> _shownApprovalDialogKeys = {};
  Timer? _approvalDialogRetryTimer;
  bool _approvalDialogOpen = false;
  String? _activeSessionId;
  int _reconnectAttempt = 0;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_synchronizeAndSubscribe());
  }

  Future<void> _synchronizeAndSubscribe() {
    final inFlight = _synchronizeInFlight;
    if (inFlight != null) return inFlight;

    final future = _synchronizeAndSubscribeOnce();
    _synchronizeInFlight = future;
    return future.whenComplete(() {
      if (identical(_synchronizeInFlight, future)) {
        _synchronizeInFlight = null;
      }
    });
  }

  Future<void> _synchronizeAndSubscribeOnce() async {
    try {
      final previousById = {
        for (final session
            in _client.peekSessions() ?? const <SessionSummary>[])
          session.id: session,
      };
      final sessions = await _client.listDomainSessions(forceRefresh: true);
      if (_disposed) return;
      for (var session in sessions) {
        session = await _hydratePendingApproval(session);
        await _handleSessionTransition(previousById[session.id], session);
      }
      _reconnectAttempt = 0;
      await _subscription?.cancel();
      _subscription = _client.subscribeToAllDomainSessionEvents().listen(
          _handleEvent,
          onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['event_type'] == 'stream.reset_required') {
      unawaited(_synchronizeAndSubscribe());
      return;
    }
    final sessionId = event['session_id'] as String?;
    if (sessionId == null) return;
    _refreshTimers.remove(sessionId)?.cancel();
    _refreshTimers[sessionId] = Timer(const Duration(milliseconds: 100), () {
      _refreshTimers.remove(sessionId);
      _enqueueSessionRefresh(sessionId);
    });
  }

  void _enqueueSessionRefresh(String sessionId) {
    if (_disposed) return;
    if (!_refreshesInFlight.add(sessionId)) {
      _refreshesPending.add(sessionId);
      return;
    }
    unawaited(_refreshSessionSerially(sessionId));
  }

  Future<void> _refreshSessionSerially(String sessionId) async {
    try {
      do {
        _refreshesPending.remove(sessionId);
        await _refreshSession(sessionId);
      } while (!_disposed && _refreshesPending.contains(sessionId));
    } finally {
      _refreshesInFlight.remove(sessionId);
      _refreshesPending.remove(sessionId);
    }
  }

  Future<void> _refreshSession(String sessionId) async {
    final previous = _client
        .peekSessions()
        ?.where((session) => session.id == sessionId)
        .firstOrNull;
    try {
      var current = (await _client.listDomainSessions(forceRefresh: true))
          .where((session) => session.id == sessionId)
          .firstOrNull;
      if (current == null) return;
      current = await _hydratePendingApproval(current);
      await _handleSessionTransition(previous, current);
    } catch (_) {
      // The next global event or reconnect performs another authoritative sync.
    }
  }

  /// The list endpoint can briefly expose the awaiting status before the
  /// persisted approval payload is attached. Fetch the authoritative detail
  /// so startup/reconnect does not require switching sessions to show it.
  Future<SessionSummary> _hydratePendingApproval(SessionSummary session) async {
    if (session.status != SessionStatus.awaitingApproval ||
        session.pendingApproval != null) {
      return session;
    }
    try {
      return (await _client.getSession(session.id)).session;
    } catch (_) {
      return session;
    }
  }

  Future<void> _handleSessionTransition(
    SessionSummary? previous,
    SessionSummary current,
  ) async {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final l10n = lookupAppLocalizations(
      AppLocalizations.supportedLocales.firstWhere(
        (item) => item.languageCode == locale.languageCode,
        orElse: () => AppLocalizations.supportedLocales.first,
      ),
    );
    final request = current.pendingApproval;
    if (current.status == SessionStatus.awaitingApproval && request != null) {
      if (current.id == _activeSessionId) {
        _removeQueuedApprovalDialogs(current.id);
      } else {
        _queueApprovalDialog(current, request);
      }
      final lastRequestId = _notifiedApprovalRequestIds[current.id];
      if (lastRequestId != request.requestId) {
        _notifiedApprovalRequestIds[current.id] = request.requestId;
        try {
          await _notifications.showApprovalRequestNotification(
            current,
            title: l10n.sessionStatusAwaitingApproval,
            body: request.reason ??
                request.command ??
                l10n.sessionStatusAwaitingApproval,
          );
        } catch (_) {
          if (_notifiedApprovalRequestIds[current.id] == request.requestId) {
            _notifiedApprovalRequestIds.remove(current.id);
          }
          rethrow;
        }
      }
      return;
    }
    _notifiedApprovalRequestIds.remove(current.id);
    _removeQueuedApprovalDialogs(current.id);

    if (previous == null || current.id == _activeSessionId) return;
    if (pushService.remoteNotificationsRegistered) return;
    if (previous.status != SessionStatus.failed &&
        current.status == SessionStatus.failed) {
      await _notifications.showSessionErrorNotification(
        current,
        current.errorMessage ??
            current.lastMessagePreview ??
            l10n.sessionFailedGeneric,
        title: l10n.sessionFailedGeneric,
      );
    } else if (previous.unreadCount == 0 && current.unreadCount > 0) {
      final body = current.lastMessagePreview?.trim();
      if (body?.isNotEmpty == true) {
        await _notifications.showAssistantReplyNotification(current, body!);
      }
    }
  }

  void _queueApprovalDialog(
    SessionSummary session,
    ApprovalRequest request,
  ) {
    final key = '${session.id}::${request.requestId}';
    if (_shownApprovalDialogKeys.contains(key) ||
        _approvalDialogQueue.containsKey(key)) {
      return;
    }
    _approvalDialogQueue[key] = (session, request);
    _drainApprovalDialogQueue();
  }

  void _removeQueuedApprovalDialogs(String sessionId) {
    final prefix = '$sessionId::';
    _approvalDialogQueue.removeWhere((key, _) => key.startsWith(prefix));
  }

  void _drainApprovalDialogQueue() {
    if (_disposed || _approvalDialogOpen || _approvalDialogQueue.isEmpty) {
      return;
    }
    final context = _notifications.navigatorKey.currentContext;
    if (context == null) {
      if (!(_approvalDialogRetryTimer?.isActive ?? false)) {
        _approvalDialogRetryTimer = Timer(
          const Duration(milliseconds: 250),
          _drainApprovalDialogQueue,
        );
      }
      return;
    }

    final entry = _approvalDialogQueue.entries.first;
    _approvalDialogQueue.remove(entry.key);
    _shownApprovalDialogKeys.add(entry.key);
    _approvalDialogOpen = true;
    unawaited(_showApprovalDialog(context, entry.value.$1, entry.value.$2));
  }

  Future<void> _showApprovalDialog(
    BuildContext context,
    SessionSummary session,
    ApprovalRequest request,
  ) async {
    final l10n = AppLocalizations.of(context) ??
        lookupAppLocalizations(AppLocalizations.supportedLocales.first);
    var projectName = _client.peekProject(session.projectId)?.name;
    if (projectName == null || projectName.trim().isEmpty) {
      try {
        projectName = (await _client.getProject(session.projectId)).name;
      } catch (_) {
        projectName = session.projectId;
      }
    }
    if (!context.mounted) {
      _approvalDialogOpen = false;
      _shownApprovalDialogKeys.remove('${session.id}::${request.requestId}');
      _queueApprovalDialog(session, request);
      return;
    }
    final agentLabel = _client.agentLabelFor(session.agentId);
    final summary = request.reason ?? request.command ?? request.kind;
    final brightness = Theme.of(context).brightness;
    final autoApprovalReason = request.autoApprovalReason?.trim();
    String? choice;
    try {
      choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.approval_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.sessionStatusAwaitingApproval)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.projectName}: $projectName',
                    key: const Key('approval-dialog-project-name'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.title,
                    key: const Key('approval-dialog-session-title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.agentAwaitingPermission(agentLabel),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summary,
                    key: const Key('approval-dialog-request-reason'),
                  ),
                  if (autoApprovalReason?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(
                      _autoApprovalReasonTitle(l10n, request),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _autoApprovalReasonBody(l10n, request),
                      key: const Key('approval-dialog-auto-approval-reason'),
                    ),
                  ],
                  if (request.command?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: SelectableText(request.command!.trim()),
                    ),
                  ],
                  if (!request.resolvable) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.desktopOnlyApproval,
                      style: TextStyle(
                        color: brightness == Brightness.dark
                            ? Colors.amber.shade200
                            : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (request.allowCancel)
              TextButton(
                onPressed: request.resolvable
                    ? () => Navigator.of(dialogContext).pop('cancel')
                    : null,
                child: Text(l10n.cancel),
              ),
            TextButton(
              onPressed: request.resolvable
                  ? () => Navigator.of(dialogContext).pop('decline')
                  : null,
              child: Text(l10n.reject),
            ),
            if (request.command?.trim().isNotEmpty == true)
              TextButton(
                onPressed: request.resolvable
                    ? () => Navigator.of(dialogContext).pop('always_allow')
                    : null,
                child: Text(l10n.alwaysAllow),
              ),
            if (request.allowAcceptForSession)
              TextButton(
                onPressed: request.resolvable
                    ? () =>
                        Navigator.of(dialogContext).pop('accept_for_session')
                    : null,
                child: Text(l10n.approveForSession),
              ),
            FilledButton(
              onPressed: request.resolvable
                  ? () => Navigator.of(dialogContext).pop('accept')
                  : null,
              child: Text(l10n.approve),
            ),
          ],
        ),
      );
      if (choice != null) {
        await _client.submitApproval(session.id, request.requestId, choice);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l10n.approvalSubmitFailed('$error'))),
        );
      }
    } finally {
      _approvalDialogOpen = false;
      _drainApprovalDialogQueue();
    }
  }

  String _autoApprovalReasonTitle(
    AppLocalizations l10n,
    ApprovalRequest request,
  ) {
    return switch (request.autoApprovalReasonKind) {
      'risk_threshold' => l10n.autoApprovalRiskThresholdTitle,
      'hard_block' => l10n.autoApprovalHardBlockTitle,
      'review_failed' => l10n.autoApprovalReviewFailedTitle,
      _ => l10n.autoApprovalAiReviewTitle,
    };
  }

  String _autoApprovalReasonBody(
    AppLocalizations l10n,
    ApprovalRequest request,
  ) {
    return switch (request.autoApprovalReasonKind) {
      'hard_block' => l10n.autoApprovalHardBlockReason,
      'review_failed' => l10n.autoApprovalReviewFailedReason,
      _ => request.autoApprovalReason!.trim(),
    };
  }

  void _scheduleReconnect() {
    if (_disposed || (_reconnectTimer?.isActive ?? false)) return;
    final exponent = _reconnectAttempt.clamp(0, 5);
    _reconnectAttempt++;
    _reconnectTimer = Timer(
      Duration(milliseconds: 500 * (1 << exponent)),
      () => unawaited(_synchronizeAndSubscribe()),
    );
  }

  void _trackRoute(Route<dynamic>? route) {
    _activeSessionId = AppRoutes.parse(route?.settings.name).sessionId;
    final activeSessionId = _activeSessionId;
    if (activeSessionId != null) {
      _removeQueuedApprovalDialogs(activeSessionId);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _trackRoute(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _trackRoute(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _trackRoute(newRoute);

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _reconnectTimer?.cancel();
    _approvalDialogRetryTimer?.cancel();
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
    _refreshesInFlight.clear();
    _refreshesPending.clear();
    _notifiedApprovalRequestIds.clear();
    _approvalDialogQueue.clear();
    _shownApprovalDialogKeys.clear();
  }

  @visibleForTesting
  Future<void> synchronizeForTest() => _synchronizeAndSubscribe();

  @visibleForTesting
  void refreshSessionForTest(String sessionId) =>
      _enqueueSessionRefresh(sessionId);
}

final sessionEventService = SessionEventService();
