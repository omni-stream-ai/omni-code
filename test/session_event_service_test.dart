import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/services/notification_service.dart';
import 'package:omni_code/src/services/session_event_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remote approval resolution clears only the completed request',
      () async {
    final client = _SessionClient([_waitingSession('approval-1')]);
    final notifications = _RecordingNotifications();
    final service =
        SessionEventService(client: client, notifications: notifications);
    addTearDown(() async {
      service.dispose();
      await client.close();
    });
    await service.synchronizeForTest();
    client.sessions = [_waitingSession('approval-2')];
    await service.synchronizeForTest();
    expect(notifications.cancelledApprovals,
        contains(('session-1', 'approval-1')));
    expect(notifications.cancelledApprovals,
        isNot(contains(('session-1', 'approval-2'))));
    client.sessions = [
      client.sessions.single.copyWith(clearPendingApproval: true)
    ];
    await service.synchronizeForTest();
    expect(notifications.cancelledApprovals,
        isNot(contains(('session-1', 'approval-2'))));
    client.sessions = [
      client.sessions.single
          .copyWith(status: SessionStatus.running, clearPendingApproval: true)
    ];
    await service.synchronizeForTest();
    expect(notifications.cancelledApprovals,
        contains(('session-1', 'approval-2')));
  });

  test('another client marking a reply read clears the notification', () async {
    final unread = _waitingSession('approval-1').copyWith(
        status: SessionStatus.idle, clearPendingApproval: true, unreadCount: 1);
    final client = _SessionClient([unread]);
    final notifications = _RecordingNotifications();
    final service =
        SessionEventService(client: client, notifications: notifications);
    addTearDown(() async {
      service.dispose();
      await client.close();
    });
    await service.synchronizeForTest();
    expect(notifications.viewedSessions, isEmpty);
    client.sessions = [unread.copyWith(unreadCount: 0)];
    await service.synchronizeForTest();
    expect(notifications.viewedSessions, ['session-1']);
  });

  test('initial sync recovers a pending approval notification', () async {
    final client = _SessionClient([_waitingSession('approval-1')]);
    final notifications = _RecordingNotifications();
    final service = SessionEventService(
      client: client,
      notifications: notifications,
    );
    addTearDown(() async {
      service.dispose();
      await client.close();
    });

    await service.synchronizeForTest();

    expect(notifications.approvalRequestIds, ['approval-1']);
  });

  test('reconnect deduplicates approval notifications by request id', () async {
    final client = _SessionClient([_waitingSession('approval-1')]);
    final notifications = _RecordingNotifications();
    final service = SessionEventService(
      client: client,
      notifications: notifications,
    );
    addTearDown(() async {
      service.dispose();
      await client.close();
    });

    await service.synchronizeForTest();
    await service.synchronizeForTest();
    client.sessions = [_waitingSession('approval-2')];
    await service.synchronizeForTest();

    expect(notifications.approvalRequestIds, [
      'approval-1',
      'approval-2',
    ]);
  });

  test('coalesces refreshes while a session refresh is in flight', () async {
    final client = _DelayedSessionClient();
    final service = SessionEventService(client: client);
    addTearDown(service.dispose);

    service.refreshSessionForTest('session-1');
    await Future<void>.delayed(Duration.zero);
    service.refreshSessionForTest('session-1');
    service.refreshSessionForTest('session-1');

    expect(client.detailLoadCount, 1);
    client.completeNextDetail();
    await Future<void>.delayed(Duration.zero);

    expect(client.detailLoadCount, 2);
    client.completeNextDetail();
  });

  test('a session event refreshes only that session instead of the full list',
      () async {
    final client = _SessionClient([_waitingSession('approval-1')]);
    final service = SessionEventService(
        client: client, notifications: _RecordingNotifications());
    addTearDown(() async {
      service.dispose();
      await client.close();
      client.dispose();
    });

    final initialRevision = client.sessionCacheRevision.value;
    service.refreshSessionForTest('session-1');
    await Future<void>.delayed(Duration.zero);

    expect(client.sessionDetailIds, ['session-1']);
    expect(client.sessionListLoads, 0);
    expect(client.sessionCacheRevision.value, initialRevision + 1);
  });

  test('the initial reset synchronizes without reopening the event stream',
      () async {
    final client = _ResetOnSubscribeClient();
    final service = SessionEventService(
        client: client, notifications: _RecordingNotifications());
    addTearDown(() async {
      service.dispose();
      await client.close();
      client.dispose();
    });

    await service.synchronizeForTest();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(client.subscriptions, 1);
    expect(client.sessionListLoads, 2);
  });

  test('streaming text avoids metadata requests while final replies notify',
      () async {
    final running = _waitingSession('approval-1')
        .copyWith(status: SessionStatus.running, clearPendingApproval: true);
    final client = _SessionClient([running]);
    final notifications = _RecordingNotifications();
    final service =
        SessionEventService(client: client, notifications: notifications);
    addTearDown(() async {
      service.dispose();
      await client.close();
      client.dispose();
    });
    await service.synchronizeForTest();
    Map<String, dynamic> event(SessionSummary session, String status) => {
          'event_type': 'message.updated',
          'session_id': session.id,
          'payload': {
            'session': {
              'id': session.id,
              'title': session.title,
              'status': status,
              'unread_count': session.unreadCount,
              'last_message_preview': session.lastMessagePreview,
              'pending_approval_id': null,
            },
          },
        };
    for (var index = 0; index < 100; index++) {
      client._events.add(event(running, 'running'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(client.sessionDetailIds, isEmpty);
    expect(client.sessionListLoads, 1);

    final completed = running.copyWith(
        status: SessionStatus.idle, unreadCount: 1, lastMessagePreview: 'Done');
    client.sessions = [completed];
    client._events.add(event(completed, 'idle'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(client.sessionDetailIds, ['session-1']);
    expect(client.sessionListLoads, 1);
    expect(notifications.replies, ['Done']);
  });

  test('a reset received during synchronization is handled afterward',
      () async {
    final client = _ResetOnSubscribeClient();
    final service = SessionEventService(
        client: client, notifications: _RecordingNotifications());
    addTearDown(() async {
      service.dispose();
      await client.close();
      client.dispose();
    });
    await service.synchronizeForTest();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(client.sessionListLoads, 2);
    final pending = Completer<List<SessionSummary>>();
    client.pendingLoad = pending;
    final synchronization = service.synchronizeForTest();
    client._events.add({'event_type': 'stream.reset_required'});
    await Future<void>.delayed(Duration.zero);
    expect(client.sessionListLoads, 3);
    client.pendingLoad = null;
    pending.complete([]);
    await synchronization;
    await Future<void>.delayed(Duration.zero);
    expect(client.sessionListLoads, 4);
    expect(client.subscriptions, 1);
  });

  test('a failed event stream reconnects without a reset loop', () async {
    final client = _ResetOnSubscribeClient();
    final service = SessionEventService(
        client: client, notifications: _RecordingNotifications());
    addTearDown(() async {
      service.dispose();
      await client.close();
      client.dispose();
    });
    await service.synchronizeForTest();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    client._events.addError(StateError('connection lost'));
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(client.subscriptions, 2);
    expect(client.sessionListLoads, 4);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(client.subscriptions, 2);
  });

  test('does not start overlapping global synchronizations', () async {
    final client = _DelayedSessionClient();
    final service = SessionEventService(client: client);
    addTearDown(service.dispose);

    final first = service.synchronizeForTest();
    final second = service.synchronizeForTest();
    await Future<void>.delayed(Duration.zero);

    expect(client.sessionLoadCount, 1);
    client.completeNextLoad();
    await Future.wait([first, second]);
  });

  testWidgets('pending approval opens an in-app dialog and submits the choice',
      (tester) async {
    final client = _SessionClient(
      [_waitingSession('approval-1')],
      projectCached: false,
    );
    final notifications = _RecordingNotifications();
    final service = SessionEventService(
      client: client,
      notifications: notifications,
    );
    addTearDown(() async {
      service.dispose();
      await client.close();
    });
    await tester.pumpWidget(MaterialApp(
      navigatorKey: notifications.navigatorKey,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Text('Session list')),
    ));

    await service.synchronizeForTest();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Project name: Drawing Agent'), findsOneWidget);
    expect(client.projectLoads, 1);
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Needs permission'), findsOneWidget);
    expect(find.text('AI recommends your review'), findsOneWidget);
    expect(find.text('The command needs human review'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(client.approvalSubmissions, [
      ('session-1', 'approval-1', 'accept'),
    ]);
  });

  testWidgets('current session approval does not open a global dialog',
      (tester) async {
    final client = _SessionClient([_waitingSession('approval-1')]);
    final notifications = _RecordingNotifications();
    final service = SessionEventService(
      client: client,
      notifications: notifications,
    );
    addTearDown(() async {
      service.dispose();
      await client.close();
    });
    service.didPush(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: '/projects/project-1/sessions/session-1',
        ),
        builder: (_) => const SizedBox.shrink(),
      ),
      null,
    );
    await tester.pumpWidget(MaterialApp(
      navigatorKey: notifications.navigatorKey,
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Text('Session detail')),
    ));

    await service.synchronizeForTest();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}

SessionSummary _waitingSession(String requestId) => SessionSummary(
      id: 'session-1',
      projectId: 'project-1',
      title: 'Session',
      agentId: 'codex',
      briefReplyMode: false,
      status: SessionStatus.awaitingApproval,
      updatedAt: DateTime.utc(2026, 8, 18),
      unreadCount: 0,
      pendingApproval: ApprovalRequest(
        requestId: requestId,
        kind: 'command_execution',
        command: 'flutter test',
        reason: 'Needs permission',
        autoApprovalReason: 'The command needs human review',
        allowAcceptForSession: true,
        allowCancel: true,
        resolvable: true,
      ),
    );

class _SessionClient extends BridgeClient {
  _SessionClient(this.sessions, {this.projectCached = true});

  List<SessionSummary> sessions;
  final bool projectCached;
  int projectLoads = 0;
  int sessionListLoads = 0;
  final List<String> sessionDetailIds = [];
  final List<(String, String, String)> approvalSubmissions = [];
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  ProjectSummary _project(String projectId) => ProjectSummary(
        id: projectId,
        name: 'Drawing Agent',
        rootPath: '/data/code/drawing-agent',
        updatedAt: DateTime.utc(2026, 8, 18),
        sessionCount: 1,
      );

  @override
  ProjectSummary? peekProject(String projectId) =>
      projectCached ? _project(projectId) : null;

  @override
  Future<ProjectSummary> getProject(
    String projectId, {
    bool forceRefresh = false,
  }) async {
    projectLoads += 1;
    return _project(projectId);
  }

  @override
  Future<SessionDetail> getSession(String sessionId) async {
    sessionDetailIds.add(sessionId);
    return SessionDetail(
        session: sessions.firstWhere((session) => session.id == sessionId));
  }

  @override
  List<SessionSummary>? peekSessions() => sessions;

  @override
  Future<List<SessionSummary>> listDomainSessions({
    String? projectId,
    String? profileId,
    bool forceRefresh = false,
  }) async {
    sessionListLoads += 1;
    return sessions;
  }

  @override
  Stream<Map<String, dynamic>> subscribeToAllDomainSessionEvents() =>
      _events.stream;

  @override
  Future<void> submitApproval(
    String sessionId,
    String requestId,
    String choice,
  ) async {
    approvalSubmissions.add((sessionId, requestId, choice));
  }

  Future<void> close() => _events.close();
}

class _DelayedSessionClient extends BridgeClient {
  int sessionLoadCount = 0;
  int detailLoadCount = 0;
  final List<Completer<List<SessionSummary>>> _pendingLoads = [];
  final List<Completer<SessionDetail>> _pendingDetails = [];

  @override
  Future<SessionDetail> getSession(String sessionId) {
    detailLoadCount += 1;
    final completer = Completer<SessionDetail>();
    _pendingDetails.add(completer);
    return completer.future;
  }

  void completeNextDetail() {
    _pendingDetails.removeAt(0).complete(SessionDetail(
        session: _waitingSession('approval-1').copyWith(
            status: SessionStatus.running, clearPendingApproval: true)));
  }

  @override
  Future<List<SessionSummary>> listDomainSessions({
    String? projectId,
    String? profileId,
    bool forceRefresh = false,
  }) {
    sessionLoadCount += 1;
    final completer = Completer<List<SessionSummary>>();
    _pendingLoads.add(completer);
    return completer.future;
  }

  void completeNextLoad() {
    _pendingLoads.removeAt(0).complete(const <SessionSummary>[]);
  }

  @override
  Stream<Map<String, dynamic>> subscribeToAllDomainSessionEvents() =>
      const Stream<Map<String, dynamic>>.empty();
}

class _ResetOnSubscribeClient extends _SessionClient {
  _ResetOnSubscribeClient() : super([]);

  int subscriptions = 0;
  Completer<List<SessionSummary>>? pendingLoad;

  @override
  Future<List<SessionSummary>> listDomainSessions({
    String? projectId,
    String? profileId,
    bool forceRefresh = false,
  }) {
    final pending = pendingLoad;
    if (pending != null) {
      sessionListLoads += 1;
      return pending.future;
    }
    return super.listDomainSessions(
        projectId: projectId, profileId: profileId, forceRefresh: forceRefresh);
  }

  @override
  Stream<Map<String, dynamic>> subscribeToAllDomainSessionEvents() {
    subscriptions += 1;
    final sendReset = subscriptions <= 4;
    return Stream<Map<String, dynamic>>.multi((controller) {
      final resetTimer = Timer(Duration.zero, () {
        if (sendReset) {
          controller.add({'event_type': 'stream.reset_required'});
        }
      });
      final subscription = _events.stream.listen(controller.add,
          onError: controller.addError, onDone: controller.close);
      controller.onCancel = () {
        resetTimer.cancel();
        return subscription.cancel();
      };
    });
  }
}

class _RecordingNotifications extends NotificationService {
  final List<String> approvalRequestIds = [];
  final List<String> replies = [];
  final List<(String, String?)> cancelledApprovals = [];
  final List<String> viewedSessions = [];

  @override
  Future<void> showAssistantReplyNotification(
      SessionSummary session, String body) async {
    replies.add(body);
  }

  @override
  Future<void> cancelApprovalRequestNotification(String sessionId,
      {String? requestId}) async {
    cancelledApprovals.add((sessionId, requestId));
  }

  @override
  Future<void> cancelSessionActivityNotifications(String sessionId) async {
    viewedSessions.add(sessionId);
  }

  @override
  Future<void> showApprovalRequestNotification(
    SessionSummary session, {
    required String title,
    required String body,
  }) async {
    approvalRequestIds.add(session.pendingApproval!.requestId);
  }
}
