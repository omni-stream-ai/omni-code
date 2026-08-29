import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'src/app.dart';
import 'src/services/notification_service.dart';
import 'src/services/push_service.dart';
import 'src/services/sentry_service.dart';
import 'src/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await appSettingsController.load();
  await runWithSentry(
    _bootstrapApplication,
    reportingEnabled: appSettingsController.settings.errorReportingEnabled,
  );
}

void _bootstrapApplication() {
  runApp(SentryWidget(child: const OmniCodeApp()));
  unawaited(_initializeServices());
}

Future<void> _initializeServices() async {
  try {
    await notificationService.initialize();
  } catch (error, stackTrace) {
    await captureHandledException(
      error,
      stackTrace,
      service: 'notifications',
    );
  }
  try {
    await pushService.initialize();
  } catch (error, stackTrace) {
    await captureHandledException(error, stackTrace, service: 'push');
  }
}
