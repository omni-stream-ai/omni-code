import 'dart:async';

import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../settings/app_settings.dart';
import '../relay/relay_http_client.dart';
import '../relay/relay_settings.dart';
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
  bool _synchronizePending = false;
  final Map<String, Timer> _refreshTimers = {};
  final Set<String> _refreshesInFlight = {};
  final Set<String> _refreshesPending = {};
  final Map<String, String> _notifiedApprovalRequestIds = {};
  final Map<String, SessionSummary> _observedSessions = {};
  final Map<String, (SessionSummary, ApprovalRequest)> _approvalDialogQueue =
      {};
  final Set<String> _shownApprovalDialogKeys = {};
  Timer? _approvalDialogRetryTimer;
  bool _approvalDialogOpen = false;
  String? _activeSessionId;
  int _reconnectAttempt = 0;
  bool _started = false;
  bool _disposed = false;
  int _generation = 0;
  String _scope = bridgeConnectionScope();
  bool _blocked = false;
  BuildContext? _approvalContext;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _scope = bridgeConnectionScope();
    appSettingsController.addListener(_connectionChanged);
    unawaited(_synchronizeAndSubscribe());
  }

  void refreshConnection() {
    if (_started && !_disposed) _restartConnection();
  }

  void _connectionChanged() {
    if (_scope != bridgeConnectionScope()) _restartConnection();
  }

  void _restartConnection() {
    _scope = bridgeConnectionScope();
    _generation++;
    _blocked = false;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _approvalDialogRetryTimer?.cancel();
    _approvalDialogRetryTimer = null;
    for (final timer in _refreshTimers.values) {
      timer.cancel();
    }
    _refreshTimers.clear();
    _refreshesInFlight.clear();
    _refreshesPending.clear();
    _notifiedApprovalRequestIds.clear();
    _observedSessions.clear();
    _approvalDialogQueue.clear();
    _shownApprovalDialogKeys.clear();
    final context = _approvalContext;
    _approvalContext = null;
    _approvalDialogOpen = false;
    if (context != null && context.mounted) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
    _synchronizeInFlight = null;
    _synchronizePending = false;
    unawaited(_synchronizeAndSubscribe());
  }

  void _streamFailure(Object error) {
    if (error is RelayException && error.blocksReconnect) {
      _blocked = true;
      return;
    }
    _scheduleReconnect();
  }

  Future<void> _synchronizeAndSubscribe() {
    if (_disposed || _blocked) return Future<void>.value();
    final inFlight = _synchronizeInFlight;
    if (inFlight != null) return inFlight;

    final future = _synchronizeAndSubscribeOnce();
    _synchronizeInFlight = future;
    return future.whenComplete(() {
      if (identical(_synchronizeInFlight, future)) {
        _synchronizeInFlight = null;
        if (_synchronizePending) {
          _synchronizePending = false;
          unawaited(_synchronizeAndSubscribe());
        }
      }
    });
  }

  Future<void> _synchronizeAndSubscribeOnce() async {
    final generation = _generation;
    try {
      final previousById = {
        for (final session
            in _client.peekSessions() ?? const <SessionSummary>[])
          session.id: session,
      };
      final sessions = await _client.listDomainSessions(forceRefresh: true);
      if (_disposed || generation != _generation) return;
      for (var session in sessions) {
        session = await _hydratePendingApproval(session);
        if (generation != _generation) return;
        await _handleSessionTransition(previousById[session.id], session);
        if (generation != _generation) return;
      }
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      // Every connection starts with reset_required. Refresh the snapshot on
      // that signal while retaining the stream, or it reconnects indefinitely.
      if (_subscription != null || generation != _generation || _disposed) {
        return;
      }
      late final StreamSubscription<Map<String, dynamic>> subscription;
      subscription =
          _client.subscribeToAllDomainSessionEvents().listen((event) {
        if (generation == _generation &&
            identical(_subscription, subscription)) {
          _handleEvent(event);
        }
      }, onError: (Object error) {
        if (generation == _generation &&
            identical(_subscription, subscription)) {
          _subscription = null;
          _streamFailure(error);
        }
      }, onDone: () {
        if (generation == _generation &&
            identical(_subscription, subscription)) {
          _subscription = null;
          _scheduleReconnect();
        }
      }, cancelOnError: true);
      _subscription = subscription;
    } catch (error) {
      if (generation == _generation) _streamFailure(error);
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['event_type'] == 'stream.reset_required') {
      if (_synchronizeInFlight != null) {
        _synchronizePending = true;
      } else {
        unawaited(_synchronizeAndSubscribe());
      }
      return;
    }
    final sessionId = event['session_id'] as String?;
    if (sessionId == null) return;
    final eventType = event['event_type'];
    if (eventType == 'message.updated' ||
        eventType == 'activity.updated' ||
        eventType == 'artifact.updated' ||
        eventType == 'turn.execution_changed') {
      final payload = event['payload'];
      final session = payload is Map ? payload['session'] : null;
      final previous = _observedSessions[sessionId];
      // Transcript updates already reach the open session's controller. Only
      // refresh global metadata when a notification or sidebar field changes.
      if (session is Map &&
          previous != null &&
          session['id'] == sessionId &&
          session['title'] == previous.title &&
          session['status'] is String &&
          parseSessionStatus(session['status'] as String) == previous.status &&
          session['unread_count'] == previous.unreadCount &&
          session['last_message_preview'] == previous.lastMessagePreview &&
          session['pending_approval_id'] ==
              previous.pendingApproval?.requestId) {
        return;
      }
    }
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
    final generation = _generation;
    try {
      do {
        _refreshesPending.remove(sessionId);
        await _refreshSession(sessionId);
      } while (!_disposed &&
          generation == _generation &&
          _refreshesPending.contains(sessionId));
    } finally {
      if (generation == _generation) {
        _refreshesInFlight.remove(sessionId);
        _refreshesPending.remove(sessionId);
      }
    }
  }

  Future<void> _refreshSession(String sessionId) async {
    final generation = _generation;
    final previous = _client
        .peekSessions()
        ?.where((session) => session.id == sessionId)
        .firstOrNull;
    try {
      final current = (await _client.getSession(sessionId)).session;
      if (_disposed || generation != _generation) return;
      _client.syncSessionSummary(current, authoritative: true);
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
    final generation = _generation;
    previous = _observedSessions[current.id] ?? previous;
    _observedSessions[current.id] = current;
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    final l10n = lookupAppLocalizations(
      AppLocalizations.supportedLocales.firstWhere(
        (item) => item.languageCode == locale.languageCode,
        orElse: () => AppLocalizations.supportedLocales.first,
      ),
    );
    if (current.unreadCount == 0 &&
        (previous == null || previous.unreadCount > 0)) {
      await _notifications.cancelSessionActivityNotifications(current.id);
    }
    final request = current.pendingApproval;
    if (generation != _generation) return;
    if (current.status == SessionStatus.awaitingApproval && request != null) {
      final oldRequestId = _notifiedApprovalRequestIds[current.id] ??
          previous?.pendingApproval?.requestId;
      if (oldRequestId != null && oldRequestId != request.requestId) {
        await _notifications.cancelApprovalRequestNotification(current.id,
            requestId: oldRequestId);
      }
      if (current.id == _activeSessionId) {
        _removeQueuedApprovalDialogs(current.id);
      } else {
        _queueApprovalDialog(current, request);
      }
      final lastRequestId = _notifiedApprovalRequestIds[current.id];
      if (lastRequestId != request.requestId &&
          !pushService.remoteNotificationsRegistered) {
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
      _notifiedApprovalRequestIds[current.id] = request.requestId;
      return;
    }
    // An awaiting status without a hydrated payload is not a resolution.
    if (current.status == SessionStatus.awaitingApproval) return;
    final resolvedRequestId = _notifiedApprovalRequestIds.remove(current.id) ??
        previous?.pendingApproval?.requestId;
    await _notifications.cancelApprovalRequestNotification(current.id,
        requestId: resolvedRequestId);
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
    final generation = _generation;
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
    if (generation != _generation) return;
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
        builder: (dialogContext) {
          _approvalContext = dialogContext;
          return AlertDialog(
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
          );
        },
      );
      if (choice != null && generation == _generation) {
        await _client.submitApproval(session.id, request.requestId, choice);
        await _notifications.cancelApprovalRequestNotification(session.id,
            requestId: request.requestId);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(l10n.approvalSubmitFailed('$error'))),
        );
      }
    } finally {
      if (generation == _generation) {
        _approvalContext = null;
        _approvalDialogOpen = false;
        _drainApprovalDialogQueue();
      }
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
    if (_disposed || _blocked || (_reconnectTimer?.isActive ?? false)) return;
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
    _generation++;
    appSettingsController.removeListener(_connectionChanged);
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
    _observedSessions.clear();
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
