import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/services/notification_service.dart';
import 'src/services/push_service.dart';
import 'src/services/sentry_service.dart';
import 'src/services/video_playback.dart';
import 'src/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeVideoPlayback();
  usePathUrlStrategy();
  await appSettingsController.load();
  await runWithSentry(
    _bootstrapApplication,
    reportingEnabled: appSettingsController.settings.errorReportingEnabled,
  );
}

void _bootstrapApplication() {
  runApp(ProviderScope(child: SentryWidget(child: const OmniCodeApp())));
  // Optional platform services must start after this window has rendered.
  // A desktop process opening another window can initialize native plugins
  // while its first frame is still being scheduled.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeServices());
  });
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
