import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_routes.dart';
import '../models.dart';
import '../settings/app_settings.dart';
import 'notification_delivery.dart';
import 'notification_delivery_stub.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  notificationService.handleNotificationPayload(response.payload);
}

String truncateNotificationBody(String body, int maxChars) {
  final trimmed = body.trim();
  if (trimmed.isEmpty || maxChars <= 0 || trimmed.length <= maxChars) {
    return trimmed;
  }
  if (maxChars <= 3) {
    return trimmed.substring(0, maxChars);
  }
  return '${trimmed.substring(0, maxChars - 3)}...';
}

class NotificationService {
  NotificationService({NotificationDelivery? delivery}) : _delivery = delivery;

  NotificationDelivery? _delivery;
  final NotificationDelivery _fallbackDelivery = MemoryNotificationDelivery();
  final Map<int, int> _notificationEpochs = {};

  Future<void> _deliverOnce(SessionSummary session, String kind, String body,
      Future<void> Function() show) {
    final requestId =
        kind == 'approval' ? session.pendingApproval?.requestId : null;
    final key = sha256
        .convert(utf8.encode(jsonEncode([
          appSettingsController.settings.bridgeUrl,
          session.id,
          kind,
          requestId ?? body.trim(),
        ])))
        .toString();
    final id = kind == 'approval'
        ? approvalNotificationId(session.id, requestId)
        : activityNotificationId(session.id, error: kind == 'error');
    final epoch = _notificationEpochs[id] ?? 0;
    return (_delivery ?? _fallbackDelivery).deliver(
      key,
      requestId == null ? const Duration(seconds: 10) : const Duration(days: 1),
      () async {
        if ((_notificationEpochs[id] ?? 0) == epoch) await show();
      },
    );
  }

  static const _replyChannelId = 'omni_code_replies_v2';
  static const _silentReplyChannelId = 'omni_code_replies_silent_v2';
  static const _replyChannelName = 'Agent Replies';
  static const _replyChannelDescription =
      'Omni Code assistant reply notifications';
  static const _replyThreadId = 'omni_code_replies';
  static const _defaultActionName = 'Open Omni Code';
  static const _windowsAppUserModelId = 'OmniStreamAI.OmniCode.Client';
  static const _windowsGuid = 'b24469ed-9ea8-4dd6-b2b1-f52a92e10983';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  SessionSummary? _pendingSession;

  static int approvalNotificationId(String sessionId, String? requestId) {
    return _stableNotificationId('$sessionId::approval::$requestId');
  }

  static int activityNotificationId(String sessionId, {bool error = false}) =>
      _stableNotificationId('$sessionId::${error ? 'error' : 'reply'}');

  static int _stableNotificationId(String value) {
    final bytes = sha256.convert(utf8.encode(value)).bytes;
    return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) &
        0x7fffffff;
  }

  Future<void> _cancel(int id, {String? tag}) async {
    _notificationEpochs[id] = (_notificationEpochs[id] ?? 0) + 1;
    try {
      await _plugin.cancel(id: id, tag: tag);
    } catch (_) {
      // Notification cleanup must not interrupt reading or approval handling.
    }
  }

  Future<void> _cancelAndroidTags(bool Function(String) matches) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      for (final notification in await _plugin.getActiveNotifications()) {
        final tag = notification.tag;
        final id = notification.id;
        if (tag != null && id != null && matches(tag)) {
          await _cancel(id, tag: tag);
        }
      }
    } catch (_) {
      // Some platform implementations cannot enumerate delivered notifications.
    }
  }

  Future<void> cancelSessionActivityNotifications(String sessionId) async {
    await cancelAssistantReplyNotification(sessionId);
    await _cancel(activityNotificationId(sessionId, error: true));
    await _cancel('$sessionId::error'.hashCode);
    await _cancelAndroidTags((tag) => tag == sessionId);
    await _cancelIosPush(sessionId, 'activity');
  }

  Future<void> cancelApprovalRequestNotification(String sessionId,
      {String? requestId}) async {
    await _cancel(approvalNotificationId(sessionId, requestId),
        tag: '$sessionId::approval::${requestId ?? ''}');
    await _cancel('$sessionId::approval'.hashCode);
    final prefix = '$sessionId::approval::';
    await _cancelAndroidTags((tag) => requestId == null
        ? tag.startsWith(prefix)
        : tag == '$prefix$requestId');
    if (requestId == null &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      try {
        for (final notification in await _plugin.getActiveNotifications()) {
          final payload = notification.payload;
          if (notification.id == null || payload == null) continue;
          try {
            final decoded = jsonDecode(payload);
            final session = decoded is Map ? decoded['session'] : null;
            if (session is Map &&
                session['id'] == sessionId &&
                session['status'] == 'awaiting_approval') {
              await _cancel(notification.id!);
            }
          } on FormatException {
            // Ignore notifications from other integrations.
          }
        }
      } catch (_) {
        // Enumeration is optional on older platform implementations.
      }
    }
    await _cancelIosPush(sessionId, 'approval', requestId: requestId);
  }

  Future<void> _cancelIosPush(String sessionId, String kind,
      {String? requestId}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await const MethodChannel('omni_code/notification_cleanup')
          .invokeMethod<void>('clear', {
        'session_id': sessionId,
        'kind': kind,
        'request_id': requestId,
      });
    } catch (_) {
      // Older native clients may not expose cleanup for remote notifications.
    }
  }

  Future<void> initialize() async {
    _delivery ??= createNotificationDelivery();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
      defaultPresentBanner: true,
      defaultPresentList: true,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: _defaultActionName,
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Omni Code',
      appUserModelId: _windowsAppUserModelId,
      guid: _windowsGuid,
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        handleNotificationPayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _replyChannelId,
        _replyChannelName,
        description: _replyChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _silentReplyChannelId,
        'Silent Agent Replies',
        description: _replyChannelDescription,
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final macosPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      handleNotificationPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }
  }

  void handleNotificationPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final session = SessionSummary.fromJson(
      json['session'] as Map<String, dynamic>,
    );
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingSession = session;
      return;
    }
    navigator.pushNamed(
      AppRoutes.session(session.projectId, session.id),
      arguments: session,
    );
  }

  void flushPendingNavigation() {
    final session = _pendingSession;
    final navigator = navigatorKey.currentState;
    if (session == null || navigator == null) {
      return;
    }
    _pendingSession = null;
    navigator.pushNamed(
      AppRoutes.session(session.projectId, session.id),
      arguments: session,
    );
  }

  Future<void> showAssistantReplyNotification(
    SessionSummary session,
    String body,
  ) async {
    final trimmedBody = truncateNotificationBody(
      body,
      appSettingsController.settings.notificationMaxChars,
    );
    if (trimmedBody.isEmpty) {
      return;
    }
    final playSound = shouldPlayNotificationSound(
      appSettingsController.settings.notificationSoundMode,
      important: false,
    );
    await _deliverOnce(
        session,
        'reply',
        body,
        () => _plugin.show(
              id: activityNotificationId(session.id),
              title: session.title,
              body: trimmedBody,
              notificationDetails: _notificationDetails(
                playSound: playSound,
                approval: false,
              ),
              payload: jsonEncode({
                'session': {
                  'id': session.id,
                  'project_id': session.projectId,
                  'title': session.title,
                  'agent': session.agentId,
                  'status': _statusName(session.status),
                  'updated_at': session.updatedAt.toIso8601String(),
                  'unread_count': session.unreadCount,
                  'last_message_preview': session.lastMessagePreview,
                },
              }),
            ));
  }

  Future<void> cancelAssistantReplyNotification(String sessionId) async {
    await _cancel(activityNotificationId(sessionId));
    await _cancel(sessionId.hashCode);
  }

  Future<void> showRemoteAssistantReplyNotification({
    required String? payload,
    required String? body,
  }) async {
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final session = SessionSummary.fromJson(
      json['session'] as Map<String, dynamic>,
    );
    final trimmedBody = body?.trim();
    final notificationBody = trimmedBody?.isNotEmpty == true
        ? trimmedBody!
        : session.lastMessagePreview;
    if (notificationBody == null || notificationBody.trim().isEmpty) {
      return;
    }
    await showAssistantReplyNotification(session, notificationBody);
  }

  Future<void> showRemoteApprovalRequestNotification({
    required String? payload,
    required String? title,
    required String? body,
  }) async {
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final session = SessionSummary.fromJson(
      json['session'] as Map<String, dynamic>,
    );
    final notificationBody = body?.trim();
    if (notificationBody == null || notificationBody.isEmpty) {
      return;
    }
    await showApprovalRequestNotification(
      session,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : 'Approval required',
      body: notificationBody,
    );
  }

  Future<void> showApprovalRequestNotification(
    SessionSummary session, {
    required String title,
    required String body,
  }) async {
    final trimmedBody = truncateNotificationBody(
      body,
      appSettingsController.settings.notificationMaxChars,
    );
    if (trimmedBody.isEmpty) {
      return;
    }
    final playSound = shouldPlayNotificationSound(
      appSettingsController.settings.notificationSoundMode,
      important: true,
    );
    await _deliverOnce(
        session,
        'approval',
        body,
        () => _plugin.show(
              id: approvalNotificationId(
                  session.id, session.pendingApproval?.requestId),
              title: title,
              body: trimmedBody,
              notificationDetails: _notificationDetails(
                playSound: playSound,
                approval: true,
                tag:
                    '${session.id}::approval::${session.pendingApproval?.requestId ?? ''}',
              ),
              payload: jsonEncode({
                'session': {
                  'id': session.id,
                  'project_id': session.projectId,
                  'title': session.title,
                  'agent': session.agentId,
                  'status': _statusName(session.status),
                  'updated_at': session.updatedAt.toIso8601String(),
                  'unread_count': session.unreadCount,
                  'last_message_preview': session.lastMessagePreview,
                },
              }),
            ));
  }

  Future<void> showSessionErrorNotification(
    SessionSummary session,
    String body, {
    required String title,
  }) async {
    final trimmedBody = truncateNotificationBody(
      body,
      appSettingsController.settings.notificationMaxChars,
    );
    if (trimmedBody.isEmpty) return;
    await _deliverOnce(
        session,
        'error',
        body,
        () => _plugin.show(
              id: activityNotificationId(session.id, error: true),
              title: title,
              body: trimmedBody,
              notificationDetails: _notificationDetails(
                playSound: shouldPlayNotificationSound(
                  appSettingsController.settings.notificationSoundMode,
                  important: true,
                ),
                approval: false,
              ),
              payload: jsonEncode({
                'session': {
                  'id': session.id,
                  'project_id': session.projectId,
                  'title': session.title,
                  'agent': session.agentId,
                  'status': _statusName(session.status),
                  'updated_at': session.updatedAt.toIso8601String(),
                  'unread_count': session.unreadCount,
                  'last_message_preview': session.lastMessagePreview,
                },
              }),
            ));
  }

  NotificationDetails _notificationDetails({
    required bool playSound,
    required bool approval,
    String? tag,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        playSound ? _replyChannelId : _silentReplyChannelId,
        playSound ? _replyChannelName : 'Silent Agent Replies',
        tag: tag,
        channelDescription: _replyChannelDescription,
        importance: playSound ? Importance.max : Importance.high,
        priority: Priority.high,
        playSound: playSound,
        enableVibration: playSound,
        ticker: 'Omni Code',
        category: approval
            ? AndroidNotificationCategory.status
            : AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        autoCancel: true,
        ongoing: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
        presentBanner: true,
        presentList: true,
        threadIdentifier: _replyThreadId,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: playSound,
        presentBanner: true,
        presentList: true,
        threadIdentifier: _replyThreadId,
      ),
      linux: LinuxNotificationDetails(
        defaultActionName: _defaultActionName,
        sound: playSound ? ThemeLinuxSound('message-new-instant') : null,
        suppressSound: !playSound,
      ),
      windows: WindowsNotificationDetails(
        audio: playSound ? null : WindowsNotificationAudio.silent(),
      ),
    );
  }

  String _statusName(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return 'idle';
      case SessionStatus.running:
        return 'running';
      case SessionStatus.awaitingApproval:
        return 'awaiting_approval';
      case SessionStatus.interrupted:
        return 'interrupted';
      case SessionStatus.waiting:
        return 'waiting';
      case SessionStatus.failed:
        return 'failed';
    }
  }
}

final notificationService = NotificationService();

bool shouldPlayNotificationSound(
  NotificationSoundMode mode, {
  required bool important,
}) {
  return switch (mode) {
    NotificationSoundMode.all => true,
    NotificationSoundMode.importantOnly => important,
    NotificationSoundMode.muted => false,
  };
}
