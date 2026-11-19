import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/widgets/composer_settings_dropdown.dart';
import 'package:omni_code/src/widgets/workspace_dispatch_panel.dart';

http.Response ok(Object data) => http.Response(jsonEncode({'data': data}), 200,
    headers: {'content-type': 'application/json'});

void main() {
  for (final compact in [false, true]) {
    testWidgets(
        'scheduled tasks poll and pause resume cancel independently (compact: $compact)',
        (tester) async {
      var status = 'running';
      final actions = <String>[];
      var failRead = false;
      final client = BridgeClient(httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/control')) {
          final action = jsonDecode(request.body)['action'] as String;
          actions.add(action);
          status = switch (action) {
            'pause' => 'paused',
            'resume' => 'running',
            _ => 'cancelled'
          };
          return ok({});
        }
        if (failRead) return http.Response('unavailable', 503);
        return ok({
          'dispatch_tasks': [
            {
              'id': 'task',
              'request_id': 'request',
              'session_id': 'session',
              'project_id': 'project',
              'title': 'Implement export',
              'status': status,
              'summary': 'Checking exported columns',
              'agent': 'pi',
              'dependencies': []
            }
          ]
        });
      }));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        WorkspaceDispatchPanel(client: client, compact: compact),
        const TextField(key: Key('new-request')),
      ]))));
      await tester.pumpAndSettle();
      if (compact) {
        expect(find.text('Implement export'), findsNothing);
        await tester.tap(find.text('Scheduled tasks'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Implement export'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('new-request')), 'Another request');
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Another request'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      failRead = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Implement export'), findsOneWidget);
      expect(find.text('Progress unavailable. Retrying…'), findsOneWidget);
      failRead = false;
      await tester.tap(find.text('Cancel task'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel task'), findsNothing);
      expect(actions, ['pause', 'resume', 'cancel']);
      await tester.pumpWidget(const SizedBox());
      client.dispose();
    });
  }

  testWidgets('task agent defaults to Pi and restores the saved choice',
      (tester) async {
    var agent = 'pi';
    var saves = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.url.path.endsWith('/dispatch/settings'), isTrue);
      if (request.method == 'PUT') {
        agent = jsonDecode(request.body)['agent'] as String;
      }
      return ok({'agent': agent});
    }));
    Widget app() => MaterialApp(
        home: Scaffold(
            body: WorkspaceDispatchAgentOptions(
                client: client, onSaved: () => saves++)));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    bool selected(String value) => tester
        .widget<ComposerSettingsOption>(
            find.byKey(ValueKey('agent-dispatch-option-$value')))
        .selected;
    expect(selected('pi'), isTrue);
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(agent, 'codex');
    expect(saves, 1);
    expect(selected('codex'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(selected('codex'), isTrue);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });

  testWidgets('narrow task cards keep controls reachable with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = BridgeClient(
        httpClient: MockClient((_) async => ok({
              'dispatch_tasks': [
                {
                  'id': 'task',
                  'session_id': 'session',
                  'project_id': 'project',
                  'title':
                      'A long task title that should wrap without hiding the controls',
                  'status': 'running',
                  'summary':
                      'A long progress update about checking the requested result',
                  'agent': 'claude_code',
                  'dependencies': []
                }
              ]
            })));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child:
          SingleChildScrollView(child: WorkspaceDispatchPanel(client: client)),
    ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Cancel task'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.dispose();
  });
}
