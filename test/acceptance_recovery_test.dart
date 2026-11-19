import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/acceptance_models.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/acceptance_screen.dart';
import 'package:omni_code/src/widgets/acceptance_recovery_card.dart';

Map<String, dynamic> failedRun() => {
      'id': 'run-repair',
      'project_id': 'project-a',
      'revision': 'frozen-source',
      'command': './app',
      'phase': 'failed',
      'created_at': '2026-11-15T00:00:00Z',
      'automatic': true,
      'automation': 'failed',
      'artifacts': [],
      'error': 'GL context failed',
      'startup': {'kind': 'desktop', 'command': './app', 'app': 'Fixture'},
      'recovery': {
        'stage': 'startup',
        'session_id': 'acceptance-repair-agent',
        'attempt': 3,
        'max_attempts': 3,
        'waiting_for_user': true,
        'failures': [
          for (var i = 1; i <= 3; i++)
            {'attempt': i, 'error': 'Actual failure $i'}
        ]
      },
    };
http.Response reply(Object data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data}), status,
        headers: {'content-type': 'application/json'});
Widget localized(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child);

void main() {
  test(
      'environment handoff selects its conversation after earlier startup repair',
      () {
    final data = failedRun();
    data['environment'] = {
      'id': 'env',
      'name': 'Env',
      'phase': 'failed',
      'agent_session_id': 'environment-agent',
      'recovery': {
        'stage': 'environment',
        'session_id': 'environment-agent',
        'attempt': 3,
        'max_attempts': 3,
        'waiting_for_user': true,
        'failures': []
      }
    };
    final run = AcceptanceRun.fromJson(data);
    expect(run.repairSessionId, 'environment-agent');
    expect(run.repair!.stage, 'environment');
  });

  testWidgets(
      'handoff shows history and offers conversation and manual actions',
      (tester) async {
    var chats = 0;
    final run = AcceptanceRun.fromJson(failedRun());
    await tester.pumpWidget(localized(Scaffold(
        body: SingleChildScrollView(
            child: AcceptanceRecoveryCard(
                run: run,
                onChat: () => chats++,
                onEditStartup: () {},
                onEditEnvironment: () {},
                onRetry: () {})))));
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('acceptance-repair-chat')));
    expect(chats, 1);
    await tester.tap(find.byKey(const Key('acceptance-repair-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Actual failure 3'), findsOneWidget);
    expect(find.byKey(const Key('acceptance-repair-startup')), findsOneWidget);
    expect(
        find.byKey(const Key('acceptance-repair-environment')), findsOneWidget);
  });

  testWidgets('automatic repair keeps manual conversation disabled',
      (tester) async {
    final run = AcceptanceRun.fromJson(
        {...failedRun(), 'phase': 'running', 'automation': 'starting_app'});
    await tester.pumpWidget(
        localized(Scaffold(body: AcceptanceRecoveryCard(run: run))));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-repair-chat')))
            .onPressed,
        isNull);
    expect(find.byKey(const Key('acceptance-retry-run')), findsNothing);
  });

  testWidgets(
      'manual startup validates JSON and retries the same run with the edit',
      (tester) async {
    Map<String, dynamic>? submitted;
    final data = failedRun();
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, '/v2/acceptance/run-repair/retry');
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return reply(data);
    }));
    await tester.pumpWidget(localized(AcceptanceDetailScreen(
        run: AcceptanceRun.fromJson(data), client: client)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('acceptance-repair-startup')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('acceptance-repair-startup')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('acceptance-repair-startup-json'));
    await tester.enterText(field, '[]');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pump();
    expect(submitted, isNull);
    expect(
        find.text('Enter a valid JSON object for the startup configuration.'),
        findsOneWidget);
    await tester.enterText(
        field,
        jsonEncode({
          'kind': 'desktop',
          'command': 'env GRAPHICS=correct ./app',
          'app': 'Fixture'
        }));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect((submitted!['startup'] as Map)['command'],
        'env GRAPHICS=correct ./app');
    expect(submitted!.containsKey('use_current_environment'), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'saving manual environment applies settings to this retry explicitly',
      (tester) async {
    Map<String, dynamic>? submitted;
    var saves = 0;
    final data = failedRun();
    final settings = {
      'config': {'mode': 'base'},
      'available': []
    };
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/acceptance-environment')) {
        if (request.method == 'POST') saves++;
        return reply(settings);
      }
      if (request.method == 'POST') {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return reply(data);
    }));
    await tester.pumpWidget(localized(AcceptanceDetailScreen(
        run: AcceptanceRun.fromJson(data), client: client)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('acceptance-repair-environment')), 250,
        scrollable: find.byType(Scrollable).first);
    await tester
        .ensureVisible(find.byKey(const Key('acceptance-repair-environment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptance-repair-environment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptance-environment-save')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(submitted, {'use_current_environment': true});
    await tester.pumpWidget(const SizedBox());
  });
}
