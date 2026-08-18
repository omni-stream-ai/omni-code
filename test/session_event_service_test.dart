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
  List<SessionSummary>? peekSessions() => sessions;

  @override
  Future<List<SessionSummary>> listDomainSessions({
    String? projectId,
    bool forceRefresh = false,
  }) async =>
      sessions;

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

class _RecordingNotifications extends NotificationService {
  final List<String> approvalRequestIds = [];

  @override
  Future<void> showApprovalRequestNotification(
    SessionSummary session, {
    required String title,
    required String body,
  }) async {
    approvalRequestIds.add(session.pendingApproval!.requestId);
  }
}
