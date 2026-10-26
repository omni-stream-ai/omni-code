import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/acceptance_models.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/acceptance_plan_card.dart';
import 'package:omni_code/src/screens/acceptance_screen.dart';

Map<String, dynamic> draft(
        {int version = 1,
        String automation = 'awaiting_plan_approval',
        bool approved = false}) =>
    {
      'id': 'run-a',
      'project_id': 'project-a',
      'revision': 'abc',
      'command': '',
      'phase': approved ? 'starting' : 'planning',
      'created_at': '2026-10-23T00:00:00Z',
      'artifacts': [],
      'automatic': true,
      'automation': automation,
      'test_plan': {
        'version': version,
        'approved_version': approved ? version : null,
        'notes': '',
        'cases': [
          {
            'id': 'login',
            'title': 'Invalid login',
            'steps': ['Enter a wrong password', 'Tap login'],
            'expected': 'An error is shown'
          }
        ]
      },
      'plan_messages': [
        {
          'role': 'assistant',
          'content': 'Review these test cases before running.'
        }
      ],
    };

http.Response response(Map<String, dynamic> value) =>
    http.Response(jsonEncode({'data': value}), 200,
        headers: {'content-type': 'application/json'});

Future<void> showPlan(WidgetTester tester, BridgeClient client,
    {Map<String, dynamic>? value}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var run = AcceptanceRun.fromJson(value ?? draft());
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
            body: SingleChildScrollView(
                child: AcceptancePlanCard(
                    run: run,
                    client: client,
                    onUpdated: (updated) => setState(() => run = updated))))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'reopening a draft shows review and never requests a desktop or evidence',
      (tester) async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v2/acceptance/run-a');
      return response(draft());
    }));
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AcceptanceDetailScreen(
            run: AcceptanceRun.fromJson(draft()), client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Review test cases'), findsOneWidget);
    expect(find.byKey(const Key('acceptance-plan-confirm')), findsOneWidget);
    expect(find.text('Open remote desktop'), findsNothing);
    expect(find.text('Evidence'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'cases wait for explicit confirmation and preserve the confirmed version',
      (tester) async {
    var confirmations = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.url.path, '/v2/acceptance/run-a/test-plan/confirm');
      expect(jsonDecode(request.body), {'version': 1});
      confirmations++;
      return response(draft(approved: true));
    }));
    await showPlan(tester, client);
    expect(confirmations, 0);
    expect(find.text('Invalid login'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('acceptance-plan-confirm')));
    await tester.tap(find.byKey(const Key('acceptance-plan-confirm')));
    await tester.pumpAndSettle();
    expect(confirmations, 1);
    expect(find.text('Invalid login'), findsNothing);
    await tester.ensureVisible(find.byType(ExpansionTile));
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('Invalid login'), findsOneWidget);
    expect(find.byKey(const Key('acceptance-plan-confirm')), findsNothing);
    expect(find.text('Confirmed. Acceptance will follow these test cases.'),
        findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'manual editing submits readable steps and expected result without executing',
      (tester) async {
    Map<String, dynamic>? body;
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.url.path, '/v2/acceptance/run-a/test-plan');
      body = jsonDecode(request.body) as Map<String, dynamic>;
      final value = draft(version: 2);
      (value['test_plan'] as Map<String, dynamic>)['cases'] = body!['cases'];
      return response(value);
    }));
    await showPlan(tester, client);
    await tester.tap(find.byKey(const Key('acceptance-case-edit-login')));
    await tester.pumpAndSettle();
    final stepsField = tester
        .widget<TextFormField>(find.byKey(const Key('acceptance-case-steps')));
    expect(stepsField.controller!.text, 'Enter a wrong password\nTap login');
    await tester.enterText(
        find.byKey(const Key('acceptance-case-title')), 'Show login errors');
    await tester.enterText(find.byKey(const Key('acceptance-case-steps')),
        'Open login\nEnter an invalid password');
    await tester.enterText(find.byKey(const Key('acceptance-case-expected')),
        'Stay on the login screen');
    await tester.ensureVisible(find.byKey(const Key('acceptance-case-save')));
    await tester.tap(find.byKey(const Key('acceptance-case-save')));
    await tester.pumpAndSettle();
    expect(body!['version'], 1);
    expect(body!['cases'][0]['steps'],
        ['Open login', 'Enter an invalid password']);
    expect(find.text('Show login errors'), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'conversation submits feedback and blocks execution while Agent revises',
      (tester) async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.url.path, '/v2/acceptance/run-a/test-plan/messages');
      expect(jsonDecode(request.body),
          {'version': 1, 'message': 'Also test an empty password'});
      final value = draft(automation: 'revising_plan');
      (value['plan_messages'] as List)
          .add({'role': 'user', 'content': 'Also test an empty password'});
      return response(value);
    }));
    await showPlan(tester, client);
    await tester
        .ensureVisible(find.byKey(const Key('acceptance-plan-message')));
    await tester.enterText(find.byKey(const Key('acceptance-plan-message')),
        'Also test an empty password');
    await tester.ensureVisible(find.byKey(const Key('acceptance-plan-send')));
    await tester.tap(find.byKey(const Key('acceptance-plan-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-plan-confirm')))
            .onPressed,
        isNull);
    expect(find.text('Also test an empty password'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale version errors keep the draft visible for recovery',
      (tester) async {
    final client = BridgeClient(
        httpClient: MockClient((request) async => http.Response(
            jsonEncode(
                {'error': 'Test cases changed. Refresh and confirm again.'}),
            409)));
    await showPlan(tester, client);
    await tester
        .ensureVisible(find.byKey(const Key('acceptance-plan-confirm')));
    await tester.tap(find.byKey(const Key('acceptance-plan-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test cases changed.'), findsOneWidget);
    expect(find.text('Invalid login'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-plan-confirm')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
