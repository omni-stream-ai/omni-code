import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/services/notification_delivery.dart';
import 'package:omni_code/src/services/notification_service.dart';
import 'package:omni_code/src/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NotificationPlatform platform;
  setUp(() {
    platform = _NotificationPlatform();
    FlutterLocalNotificationsPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Linux startup cleanup skips notifications that were never delivered',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final linuxPlatform = _LinuxNotificationPlatform();
    FlutterLocalNotificationsPlatform.instance = linuxPlatform;
    final service = NotificationService();
    for (var index = 0; index < 1000; index++) {
      await service.cancelSessionActivityNotifications('session-$index');
      await service.cancelApprovalRequestNotification('session-$index');
    }
    expect(linuxPlatform.cancelled, isEmpty);
  });

  test('Linux cleanup cancels delivered notifications and preserves others',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final replyId = NotificationService.activityNotificationId('session-1');
    final approvalId =
        NotificationService.approvalNotificationId('session-1', 'request-1');
    final otherReplyId =
        NotificationService.activityNotificationId('session-2');
    final linuxPlatform = _LinuxNotificationPlatform()
      ..systemIds.addAll({replyId: 1, approvalId: 2, otherReplyId: 3});
    FlutterLocalNotificationsPlatform.instance = linuxPlatform;
    final service = NotificationService();
    await service.cancelSessionActivityNotifications('session-1');
    expect(linuxPlatform.cancelled, [replyId]);
    expect(
        linuxPlatform.systemIds.keys, containsAll([approvalId, otherReplyId]));
    await service.cancelApprovalRequestNotification('session-1',
        requestId: 'request-1');
    expect(linuxPlatform.cancelled, [replyId, approvalId]);
    expect(linuxPlatform.systemIds.keys, [otherReplyId]);
  });

  test('iOS remote cleanup carries the exact approval request', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('omni_code/notification_cleanup');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await NotificationService()
        .cancelApprovalRequestNotification('session-1', requestId: 'request-1');
    expect(calls.single.method, 'clear');
    expect(calls.single.arguments, {
      'session_id': 'session-1',
      'kind': 'approval',
      'request_id': 'request-1',
    });
  });

  test('startup clears delivered local approvals after resolution', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    platform.active = [
      const ActiveNotification(
          id: 1,
          payload:
              '{"session":{"id":"session-1","status":"awaiting_approval"}}'),
      const ActiveNotification(
          id: 2,
          payload:
              '{"session":{"id":"session-2","status":"awaiting_approval"}}'),
    ];
    await NotificationService().cancelApprovalRequestNotification('session-1');
    expect(platform.cancelled, contains((1, null)));
    expect(platform.cancelled.any((item) => item.$1 == 2), isFalse);
  });

  test('viewing a session clears its replies and errors, preserving approvals',
      () async {
    platform.active = [
      const ActiveNotification(id: 100, tag: 'session-1'),
      const ActiveNotification(id: 101, tag: 'session-1::approval::request-1'),
      const ActiveNotification(id: 102, tag: 'session-2'),
    ];
    await NotificationService().cancelSessionActivityNotifications('session-1');
    expect(platform.cancelled, contains(('session-1'.hashCode, null)));
    expect(platform.cancelled, contains(('session-1::error'.hashCode, null)));
    expect(platform.cancelled, contains((100, 'session-1')));
    expect(platform.cancelled.any((item) => item.$1 == 101 || item.$1 == 102),
        isFalse);
  });

  test('clearing an old approval preserves the new request notification',
      () async {
    platform.active = [
      const ActiveNotification(id: 100, tag: 'session-1::approval::old'),
      const ActiveNotification(id: 101, tag: 'session-1::approval::new'),
    ];
    await NotificationService()
        .cancelApprovalRequestNotification('session-1', requestId: 'old');
    expect(platform.cancelled, contains((100, 'session-1::approval::old')));
    expect(platform.cancelled.any((item) => item.$1 == 101), isFalse);
    expect(NotificationService.approvalNotificationId('session-1', 'old'),
        isNot(NotificationService.approvalNotificationId('session-1', 'new')));
  });

  test(
      'reading before a queued notification is delivered prevents reappearance',
      () async {
    final delivery = _GatedDelivery();
    final service = NotificationService(delivery: delivery);
    final session = SessionSummary(
        id: 'session-1',
        projectId: 'project-1',
        title: 'Session',
        agentId: 'codex',
        briefReplyMode: false,
        status: SessionStatus.idle,
        updatedAt: DateTime(2026),
        unreadCount: 1);
    final pending = service.showAssistantReplyNotification(session, 'Finished');
    await service.cancelSessionActivityNotifications(session.id);
    delivery.ready.complete();
    await pending;
    expect(platform.shown, isEmpty);
  });
  test('notification sound mode respects notification importance', () {
    expect(
      shouldPlayNotificationSound(NotificationSoundMode.all, important: false),
      isTrue,
    );
    expect(
      shouldPlayNotificationSound(
        NotificationSoundMode.importantOnly,
        important: false,
      ),
      isFalse,
    );
    expect(
      shouldPlayNotificationSound(
        NotificationSoundMode.importantOnly,
        important: true,
      ),
      isTrue,
    );
    expect(
      shouldPlayNotificationSound(
        NotificationSoundMode.muted,
        important: true,
      ),
      isFalse,
    );
  });

  test('truncateNotificationBody keeps short text unchanged', () {
    expect(truncateNotificationBody('hello', 10), 'hello');
  });

  test('truncateNotificationBody trims and truncates long text', () {
    expect(
      truncateNotificationBody('  1234567890  ', 8),
      '12345...',
    );
  });

  test('truncateNotificationBody handles very small limits', () {
    expect(truncateNotificationBody('123456', 3), '123');
  });
}

class _GatedDelivery implements NotificationDelivery {
  final ready = Completer<void>();
  @override
  Future<void> deliver(
      String key, Duration retention, Future<void> Function() show) async {
    await ready.future;
    await show();
  }
}

class _LinuxNotificationPlatform extends LinuxFlutterLocalNotificationsPlugin {
  final Map<int, int> systemIds = {};
  final List<int> cancelled = [];

  @override
  Future<Map<int, int>> getSystemIdMap() async => Map.of(systemIds);

  @override
  Future<void> cancel({required int id}) async {
    cancelled.add(id);
    systemIds.remove(id);
  }
}

class _NotificationPlatform extends AndroidFlutterLocalNotificationsPlugin {
  final List<(int, String?)> cancelled = [];
  final List<int> shown = [];
  List<ActiveNotification> active = [];
  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add((id, tag));
  }

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => active;
  @override
  Future<void> show(
      {required int id,
      String? title,
      String? body,
      AndroidNotificationDetails? notificationDetails,
      String? payload}) async {
    shown.add(id);
  }
}
