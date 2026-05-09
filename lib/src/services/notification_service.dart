import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_routes.dart';
import '../models.dart';
import '../settings/app_settings.dart';

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
  static const _replyChannelId = 'omni_code_replies';
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

  Future<void> initialize() async {
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
    await _plugin.show(
      id: session.id.hashCode,
      title: session.title,
      body: trimmedBody,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _replyChannelId,
          _replyChannelName,
          channelDescription: _replyChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ticker: 'Omni Code',
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          autoCancel: true,
          ongoing: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
          threadIdentifier: _replyThreadId,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
          presentList: true,
          threadIdentifier: _replyThreadId,
        ),
        linux: LinuxNotificationDetails(
          defaultActionName: _defaultActionName,
        ),
        windows: WindowsNotificationDetails(),
      ),
      payload: jsonEncode({
        'session': {
          'id': session.id,
          'project_id': session.projectId,
          'title': session.title,
          'agent': session.agent.name,
          'status': _statusName(session.status),
          'updated_at': session.updatedAt.toIso8601String(),
          'unread_count': session.unreadCount,
          'last_message_preview': session.lastMessagePreview,
        },
      }),
    );
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

  String _statusName(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return 'idle';
      case SessionStatus.running:
        return 'running';
      case SessionStatus.awaitingApproval:
        return 'awaiting_approval';
      case SessionStatus.waiting:
        return 'waiting';
      case SessionStatus.failed:
        return 'failed';
    }
  }
}

final notificationService = NotificationService();
