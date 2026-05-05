import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/services/notification_service.dart';
import 'src/services/push_service.dart';
import 'src/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettingsController.load();
  runApp(const OmniCodeApp());
  unawaited(_initializeServices());
}

Future<void> _initializeServices() async {
  try {
    await notificationService.initialize();
  } catch (_) {}
  try {
    await pushService.initialize();
  } catch (_) {}
}
