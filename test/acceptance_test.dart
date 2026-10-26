import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/acceptance_models.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/screens/acceptance_screen.dart';
import 'package:omni_code/src/screens/acceptance_environment_screen.dart';

http.Response response(Object? data, {int status = 200}) => http.Response(
      jsonEncode({'data': data}),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test(
      'project environment requests preserve project scope and custom configuration',
      () async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.url.path, '/v2/projects/project-a/acceptance-environment');
      if (request.method == 'POST') {
        final body = jsonDecode(request.body);
        expect(body['mode'], 'dockerfile');
        expect(body['dockerfile'], 'FROM {{BASE_IMAGE}}\nUSER x11box');
        expect(body['rebuild'], true);
        expect(body.containsKey('generation'), false);
        return response({'config': body});
      }
      return response({
        'config': {'mode': 'auto'},
        'available': [
          {'name': 'Flutter', 'image_id': 'sha256:fixture'}
        ]
      });
    }));
    final settings = await client.getAcceptanceEnvironment('project-a');
    expect(settings.config.mode, 'auto');
    expect(settings.available.single.name, 'Flutter');
    await client.saveAcceptanceEnvironment(
        'project-a',
        const AcceptanceEnvironmentConfig(
            mode: 'dockerfile', dockerfile: 'FROM {{BASE_IMAGE}}\nUSER x11box'),
        rebuild: true);
    final legacy = AcceptanceRun.fromJson(runJson());
    expect(legacy.environment, isNull);
    expect(legacy.environmentReused, false);
  });

  testWidgets(
      'project environment supports manual Dockerfiles and rebuild on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? saved;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return response({
        'config': {'mode': 'auto'},
        'available': []
      });
    }));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceEnvironmentScreen(client: client, projectId: 'project-a'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptance-environment-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Dockerfile').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('acceptance-environment-dockerfile')),
        'FROM {{BASE_IMAGE}}\nUSER x11box');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('acceptance-environment-save')));
    await tester.tap(find.byKey(const Key('acceptance-environment-save')));
    await tester.pumpAndSettle();
    expect(saved!['mode'], 'dockerfile');
    expect(saved!['dockerfile'], contains('{{BASE_IMAGE}}'));
    expect(saved!['rebuild'], true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed environment shows build diagnostics in the run details',
      (tester) async {
    final data = {
      ...runJson(),
      'phase': 'failed',
      'environment': {
        'id': 'environment-a',
        'name': 'Flutter Linux',
        'phase': 'failed',
        'error': 'SDK verification failed',
        'log': 'Missing GTK development libraries',
        'dockerfile': 'FROM {{BASE_IMAGE}}',
      }
    };
    final client =
        BridgeClient(httpClient: MockClient((_) async => response(data)));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceDetailScreen(
          run: AcceptanceRun.fromJson(data), client: client),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Flutter Linux'), findsOneWidget);
    expect(find.text('SDK verification failed'), findsOneWidget);
    final logs = find.byKey(const Key('acceptance-environment-logs'));
    await tester.ensureVisible(logs);
    await tester.tap(logs);
    await tester.pumpAndSettle();
    expect(find.text('Missing GTK development libraries'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('environment preparation stays visibly busy until it finishes',
      (tester) async {
    Map<String, dynamic> data = {...runJson()};
    final client =
        BridgeClient(httpClient: MockClient((_) async => response(data)));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceDetailScreen(
          run: AcceptanceRun.fromJson(data), client: client),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('acceptance-journey-loading')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    data = {
      ...data,
      'environment': {
        'id': 'environment-a',
        'name': 'Flutter Linux',
        'phase': 'building',
        'progress': 'Installing Flutter dependencies',
      }
    };
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('acceptance-journey-loading')), findsOneWidget);
    expect(find.text('Installing Flutter dependencies'), findsOneWidget);

    data = {
      ...data,
      'phase': 'failed',
      'environment': {
        'id': 'environment-a',
        'name': 'Flutter Linux',
        'phase': 'failed',
        'error': 'Dependency installation failed',
      }
    };
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Dependency installation failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('requirement summaries remain readable with legacy run responses', () {
    expect(AcceptanceRun.fromJson(runJson()).requirementBrief, isNull);
    final run = AcceptanceRun.fromJson({
      ...runJson(),
      'session_id': 'session-a',
      'requirement_brief': {
        'source_message_count': 42,
        'requirements': [
          {
            'id': 'export',
            'description': 'Only export PDF after checking permissions',
            'source_message_ids': ['u1', 'u42']
          }
        ],
        'notes': 'CSV was cancelled in a later request',
      },
    });
    expect(run.sessionId, 'session-a');
    expect(run.requirementBrief!.sourceMessageCount, 42);
    expect(run.requirementBrief!.requirements.single.description,
        contains('Only export PDF'));
    expect(run.requirementBrief!.notes, contains('CSV was cancelled'));
  });

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

  test('video playback keeps authentication on the artifact origin', () {
    final original = appSettingsController.settings;
    addTearDown(() => appSettingsController.debugReplaceSettings(original));
    appSettingsController.debugReplaceSettings(original.copyWith(
        bridgeUrl: 'http://bridge.example:8788',
        bridgeToken: 'test-token',
        clientId: 'test-client'));
    final source =
        BridgeClient().acceptanceVideoSource('run-a', 'recording.mp4');
    expect(source.uri.origin, 'http://bridge.example:8788');
    expect(source.uri.path, '/v2/acceptance/run-a/artifacts/recording.mp4');
    expect(source.uri.queryParameters, isEmpty);
    expect(source.headers['Authorization'], 'Bearer test-token');
    expect(source.headers['X-Omni-Code-Client-Id'], 'test-client');
  });

  test('evidence can be generated without stopping the desktop', () async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v2/acceptance/run-a/evidence');
      return response({
        ...runJson(),
        'phase': 'running',
        'artifacts': [
          {
            'name': 'recording.mp4',
            'content_type': 'video/mp4',
            'bytes': 2048,
          }
        ]
      });
    }));
    final run = await client.saveAcceptanceEvidence('run-a');
    expect(run.running, true);
    expect(run.artifacts.single.contentType, 'video/mp4');
  });

  test('desktop URL cannot redirect to an external origin', () async {
    final client = BridgeClient(
        httpClient: MockClient(
            (_) async => response({'url': 'https://other.example/desktop'})));
    await expectLater(
        client.acceptanceDesktopUrl('run'), throwsFormatException);
  });

  test('evidence download preserves ticket and stays on Bridge origin',
      () async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'POST');
      expect(
          request.url.path, '/v2/acceptance/run/evidence-ticket/recording.mp4');
      return response(
          {'url': '/v2/acceptance/run/evidence/recording.mp4?ticket=one-use'});
    }));
    final uri = await client.acceptanceEvidenceUrl('run', 'recording.mp4',
        download: true);
    expect(uri.queryParameters['ticket'], 'one-use');
    expect(uri.queryParameters['download'], 'true');
    expect(uri.path, '/v2/acceptance/run/evidence/recording.mp4');
  });

  test('evidence URL rejects an external origin', () async {
    final client = BridgeClient(
        httpClient:
            MockClient((_) async => response({'url': '//other.example/file'})));
    await expectLater(client.acceptanceEvidenceUrl('run', 'recording.mp4'),
        throwsFormatException);
  });

  test('uninstall issues DELETE and surfaces cleanup failures', () async {
    var fail = false;
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/v2/runtime-plugins/x11box-acceptance');
      return fail
          ? http.Response(jsonEncode({'error': 'cleanup needs retry'}), 409)
          : http.Response('', 204);
    }));
    await client.uninstallAcceptancePlugin();
    fail = true;
    await expectLater(
        client.uninstallAcceptancePlugin(),
        throwsA(
            predicate((e) => e.toString().contains('cleanup needs retry'))));
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

  testWidgets('automatic startup accepts an empty command', (tester) async {
    String? command;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path == '/v2/runtime-plugins/x11box-acceptance') {
        return response({
          'installation': {'phase': 'ready'}
        });
      }
      if (request.url.path == '/projects') {
        return response([
          {
            'id': 'project-a',
            'name': 'Native example',
            'root_path': '/project',
            'updated_at': '2026-10-19T00:00:00Z',
            'session_count': 0,
          }
        ]);
      }
      if (request.url.path == '/v2/acceptance') {
        if (request.method == 'POST') {
          command = (jsonDecode(request.body)
              as Map<String, dynamic>)['command'] as String;
          return response({...runJson(), 'phase': 'completed'}, status: 202);
        }
        return response([]);
      }
      if (request.url.path == '/v2/acceptance/run-a') {
        return response({...runJson(), 'phase': 'completed'});
      }
      throw StateError(request.url.path);
    }));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceScreen(client: client),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start acceptance'));
    await tester.pumpAndSettle();
    final start = find.widgetWithText(FilledButton, 'Start acceptance');
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(command, '');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
      theme: AppTheme.lightTheme,
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
    final readyTile = find.ancestor(
        of: find.text('Ready'), matching: find.byType(ExpansionTile));
    final leading = find.descendant(
        of: readyTile,
        matching: find.byIcon(Icons.check_circle_outline_rounded));
    final trailing = find.descendant(
        of: readyTile, matching: find.byIcon(Icons.expand_more));
    expect(tester.getTopLeft(leading).dx - tester.getTopLeft(readyTile).dx,
        greaterThanOrEqualTo(16));
    expect(tester.getTopRight(readyTile).dx - tester.getTopRight(trailing).dx,
        greaterThanOrEqualTo(16));
    expect(find.text('Start acceptance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
        'acceptance creation blocks repeats and clears loading on ${fails ? 'failure' : 'success'}',
        (tester) async {
      final creation = Completer<http.Response>();
      var creations = 0;
      final client = BridgeClient(httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/v2/runtime-plugins/x11box-acceptance':
            return response({
              'installation': {'phase': 'ready'}
            });
          case '/projects':
            return response([
              {
                'id': 'project-a',
                'name': 'Example',
                'root_path': '/project',
                'updated_at': '2026-10-22T00:00:00Z',
                'session_count': 1,
              }
            ]);
          case '/v2/acceptance':
            if (request.method == 'POST') {
              creations++;
              return creation.future;
            }
            return response([]);
          case '/v2/acceptance/run-a':
            return response({...runJson(), 'phase': 'completed'});
        }
        throw StateError(request.url.path);
      }));
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AcceptanceScreen(client: client),
      ));
      await tester.pumpAndSettle();
      final start = tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed!;
      await tester.tap(find.text('Start acceptance'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start acceptance'));
      await tester.pump();
      expect(
          find.byKey(const Key('acceptance-creation-loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Preparing acceptance'), findsOneWidget);
      expect(
          tester
              .widget<FloatingActionButton>(find.byType(FloatingActionButton))
              .onPressed,
          isNull);
      expect(find.byWidgetPredicate((w) => w is PopScope && !w.canPop),
          findsOneWidget);
      start();
      await tester.pump(const Duration(milliseconds: 350));
      expect(creations, 1);

      creation.complete(fails
          ? http.Response(
              jsonEncode({'error': 'Requirement history is unavailable'}), 409)
          : response({...runJson(), 'phase': 'completed'}, status: 202));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('acceptance-creation-loading'),
              skipOffstage: false),
          findsNothing);
      if (fails) {
        expect(find.byType(AcceptanceDetailScreen), findsNothing);
        expect(find.textContaining('Requirement history is unavailable'),
            findsOneWidget);
      } else {
        expect(find.byType(AcceptanceDetailScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(
          tester
              .widget<FloatingActionButton>(find.byType(FloatingActionButton))
              .onPressed,
          isNotNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'session acceptance isolates history and submits an explicit focus',
      (tester) async {
    Map<String, dynamic>? submitted;
    final complete = {
      ...runJson(),
      'phase': 'completed',
      'session_id': 'session-a'
    };
    final client = BridgeClient(httpClient: MockClient((request) async {
      switch (request.url.path) {
        case '/v2/runtime-plugins/x11box-acceptance':
          return response({
            'installation': {'phase': 'ready'}
          });
        case '/projects':
          return response([
            {
              'id': 'project-a',
              'name': 'Example',
              'root_path': '/project',
              'updated_at': '2026-10-22T00:00:00Z',
              'session_count': 2,
            }
          ]);
        case '/v2/acceptance':
          if (request.method == 'POST') {
            submitted = jsonDecode(request.body) as Map<String, dynamic>;
            return response(complete, status: 202);
          }
          return response([
            {...complete, 'automation_progress': 'Current session record'},
            {
              ...complete,
              'id': 'other-run',
              'session_id': 'session-b',
              'automation_progress': 'Unrelated session record'
            },
          ]);
        case '/v2/acceptance/run-a':
          return response(complete);
      }
      throw StateError(request.url.path);
    }));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceScreen(
          client: client, projectId: 'project-a', sessionId: 'session-a'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Current session record'), findsOneWidget);
    expect(find.text('Unrelated session record'), findsNothing);
    await tester.tap(find.text('Start acceptance'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('acceptance-requirements-input')),
        'Only verify PDF export and permissions');
    await tester.tap(find.widgetWithText(FilledButton, 'Start acceptance'));
    await tester.pumpAndSettle();
    expect(submitted!['session_id'], 'session-a');
    expect(
        submitted!['requirements'], 'Only verify PDF export and permissions');
    expect(submitted!['automatic'], isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'acceptance detail displays the extracted requirements and scope notes',
      (tester) async {
    final data = {
      ...runJson(),
      'phase': 'completed',
      'requirement_brief': {
        'source_message_count': 42,
        'requirements': [
          {'id': 'export', 'description': 'Verify PDF export permissions'}
        ],
        'notes': 'CSV is outside the final scope',
      },
    };
    final client =
        BridgeClient(httpClient: MockClient((_) async => response(data)));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AcceptanceDetailScreen(
          run: AcceptanceRun.fromJson(data), client: client),
    ));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('acceptance-requirement-brief')));
    expect(find.text('Acceptance requirements'), findsOneWidget);
    expect(find.text('Based on 42 user messages'), findsOneWidget);
    expect(find.text('1. Verify PDF export permissions'), findsOneWidget);
    expect(find.text('CSV is outside the final scope'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
