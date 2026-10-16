import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/acceptance_screen.dart';

http.Response response(Object? data, {int status = 200}) => http.Response(
      jsonEncode({'data': data}),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('creation preserves idempotency key and project/session binding',
      () async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v2/acceptance');
      final body = jsonDecode(request.body);
      expect(body['id'], 'same-request-id');
      expect(body['project_id'], 'project-a');
      expect(body['session_id'], 'session-a');
      return response(runJson(), status: 202);
    }));
    final run = await client.createAcceptanceRun(
        id: 'same-request-id',
        projectId: 'project-a',
        sessionId: 'session-a',
        command: 'chromium about:blank');
    expect(run.phase, 'starting');
    expect(run.terminal, false);
  });

  test('desktop URL cannot redirect to an external origin', () async {
    final client = BridgeClient(
        httpClient: MockClient(
            (_) async => response({'url': 'https://other.example/desktop'})));
    await expectLater(
        client.acceptanceDesktopUrl('run'), throwsFormatException);
  });

  test('control conflicts surface the server error', () async {
    final client = BridgeClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'error': 'another client holds desktop control'}),
              409,
              headers: {'content-type': 'application/json'},
            )));
    await expectLater(client.setAcceptanceControl('run', acquire: true),
        throwsA(predicate((e) => e.toString().contains('another client'))));
  });

  testWidgets('installation progresses to ready on a narrow mobile screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var phase = 'not_installed';
    var installs = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path == '/v2/runtime-plugins/x11box-acceptance') {
        if (request.method == 'POST') {
          installs++;
          phase = 'preparing';
          return response({'phase': phase}, status: 202);
        }
        return response({
          'installation': {'phase': phase}
        });
      }
      if (request.url.path == '/projects') {
        return response([
          {
            'id': 'project-a',
            'name': 'Example',
            'root_path': '/project',
            'updated_at': '2026-10-16T00:00:00Z',
            'session_count': 0,
          }
        ]);
      }
      if (request.url.path == '/v2/acceptance') return response([]);
      throw StateError('Unexpected request');
    }));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceScreen(client: client),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Install environment'), findsOneWidget);
    await tester.tap(find.text('Install environment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(installs, 1);
    expect(find.text('Preparing environment'), findsOneWidget);
    phase = 'ready';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Start acceptance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> runJson() => {
      'id': 'run-a',
      'project_id': 'project-a',
      'revision': 'abc123',
      'command': 'chromium about:blank',
      'phase': 'starting',
      'created_at': '2026-10-16T00:00:00Z',
      'artifacts': [],
    };
