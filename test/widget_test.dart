import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_code/src/app.dart';
import 'package:omni_code/src/app_routes.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/session_detail_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets('Omni Code home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const OmniCodeApp());

    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('session route uses passed summary without route loader',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OmniCodeApp());
    await tester.pump();

    final session = SessionSummary(
      id: 'session-1',
      projectId: 'project-1',
      title: 'Session One',
      agentId: 'codex',
      briefReplyMode: false,
      status: SessionStatus.idle,
      updatedAt: DateTime(2026, 5, 5, 11),
      unreadCount: 0,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(
      AppRoutes.session(session.projectId, session.id),
      arguments: session,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('route-loading-skeleton')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
  });
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}
