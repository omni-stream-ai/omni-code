import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_routes.dart';
import '../models.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  notificationService.handleNotificationPayload(response.payload);
}

class NotificationService {
  static const _replyChannelId = 'omni_code_replies';
  static const _replyChannelName = 'Agent Replies';
  static const _replyChannelDescription =
      'Omni Code assistant reply notifications';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  SessionSummary? _pendingSession;

  Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initializationSettings,
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
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return;
    }
    await _plugin.show(
      session.id.hashCode,
      session.title,
      trimmedBody,
      const NotificationDetails(
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
