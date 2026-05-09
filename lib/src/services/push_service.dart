import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../bridge_client.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

class PushService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  bool _backgroundHandlerRegistered = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      if (!_backgroundHandlerRegistered) {
        FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler);
        _backgroundHandlerRegistered = true;
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      await _registerCurrentDevice(messaging);
      messaging.onTokenRefresh.listen((_) {
        unawaited(_registerCurrentDevice(messaging));
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessage);
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleRemoteMessage(initialMessage);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _registerCurrentDevice(FirebaseMessaging messaging) async {
    final token = await messaging.getToken();
    if (token == null || token.trim().isEmpty) {
      return;
    }

    String? manufacturer;
    String? model;
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      manufacturer = info.manufacturer;
      model = info.model;
    }

    try {
      await bridgeClient.registerPushDevice(
        platform: Platform.operatingSystem,
        manufacturer: manufacturer,
        model: model,
        appVersion: null,
        fcmToken: token,
        miPushRegId: null,
      );
    } catch (_) {
      return;
    }
  }

  void _handleRemoteMessage(RemoteMessage message) {
    final payload = message.data['payload_json'] as String?;
    if (payload == null || payload.trim().isEmpty) {
      return;
    }
    notificationService.handleNotificationPayload(payload);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final payload = message.data['payload_json'] as String?;
    final body = message.notification?.body;
    unawaited(
      notificationService.showRemoteAssistantReplyNotification(
        payload: payload,
        body: body,
      ),
    );
  }
}

final pushService = PushService();
