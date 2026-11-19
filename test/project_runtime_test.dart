import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/project_runtime_screen.dart';

http.Response response(Object data) =>
    http.Response(jsonEncode({'data': data}), 200,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> target(String directory) => {
      'directory': directory,
      'configuration': {
        'language': 'typescript',
        'start_command': 'cd $directory && npm start'
      }
    };

Map<String, dynamic> runtime(String directory,
        {String phase = 'running', bool occupied = false}) =>
    {
      'directory': directory,
      'location': 'host',
      'phase': phase,
      'command': 'cd $directory && npm start',
      'working_directory': '/workspace',
      if (occupied)
        'lease': {
          'session_id': 'other-agent',
          'expires_at':
              DateTime.now().add(const Duration(minutes: 5)).toIso8601String()
        },
    };

Widget app(BridgeClient client) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ProjectRuntimeScreen(client: client, projectId: 'p'),
    );

void main() {
  testWidgets('subprojects can be added, renamed, edited and deleted',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final targets = <Map<String, dynamic>>[target('api')];
    final names = <String, String>{};
    final mutations = <String>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        mutations.add(request.url.path);
        if (request.url.path.endsWith('/targets')) {
          final value = body['target'] as Map<String, dynamic>;
          expect(body['create'], targets.length == 1);
          targets.removeWhere(
              (target) => target['directory'] == value['directory']);
          targets.add(value);
          names[value['directory'] as String] = body['name'] as String;
        } else if (request.url.path.endsWith('/rename')) {
          expect(body, {'directory': 'worker', 'name': 'Renamed worker'});
          names[body['directory'] as String] = body['name'] as String;
        } else {
          expect(request.url.path, '/v2/projects/p/runtime/targets/delete');
          expect(body, {'directory': 'worker'});
          targets.removeWhere((target) => target['directory'] == 'worker');
          names.remove('worker');
        }
        return response({'saved': true});
      }
      expect(request.url.path, '/v2/projects/p/runtime');
      return response({
        'preferences': {'names': names},
        'targets': targets,
        'runtimes': []
      });
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('runtime-add-target')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('runtime-target-save')));
    await tester.pumpAndSettle();
    expect(find.text('This field is required.'), findsNWidgets(2));
    expect(mutations, isEmpty);
    await tester.enterText(
        find.byKey(const Key('runtime-target-name')), 'Background worker');
    await tester.enterText(
        find.byKey(const Key('runtime-target-directory')), 'worker');
    final start = find.byKey(const Key('runtime-target-start_command'));
    await tester.ensureVisible(start);
    await tester.enterText(start, 'cd worker && ./serve');
    await tester.tap(find.byKey(const Key('runtime-target-save')));
    await tester.pumpAndSettle();
    expect(find.text('Background worker'), findsOneWidget);
    expect(find.text('worker'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('runtime-start-worker')))
            .onPressed,
        isNotNull);

    await tester.tap(find.byKey(const ValueKey('runtime-target-menu-worker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('runtime-target-start_command')), findsNothing);
    await tester.enterText(
        find.byKey(const Key('runtime-target-name')), 'Renamed worker');
    await tester.tap(find.byKey(const Key('runtime-target-save')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    expect(find.text('Renamed worker'), findsOneWidget);
    expect(targets.last['directory'], 'worker');
    expect(
        targets.last['configuration']['start_command'], 'cd worker && ./serve');

    await tester.tap(find.byKey(const ValueKey('runtime-target-menu-worker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit settings'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const Key('runtime-target-directory')))
            .initialValue,
        'worker');
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const Key('runtime-target-directory')),
                matching: find.byType(TextField)))
            .readOnly,
        true);
    await tester.ensureVisible(start);
    await tester.enterText(start, 'cd worker && ./serve --port 3001');
    await tester.tap(find.byKey(const Key('runtime-target-save')));
    await tester.pumpAndSettle();
    expect(targets.last['configuration']['start_command'],
        'cd worker && ./serve --port 3001');

    await tester.tap(find.byKey(const ValueKey('runtime-target-menu-worker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete subproject'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Renamed worker?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(targets.length, 2);
    expect(mutations.length, 3);
    await tester.tap(find.byKey(const ValueKey('runtime-target-menu-worker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete subproject'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('runtime-target-confirm-delete')));
    await tester.pumpAndSettle();
    expect(targets.length, 1);
    expect(find.byKey(const ValueKey('runtime-start-worker')), findsNothing);
    expect(mutations.length, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failed saves keep the editor open and block duplicate submissions',
      (tester) async {
    final pending = Completer<http.Response>();
    var saves = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        saves++;
        return pending.future;
      }
      return response({
        'targets': [target('api')],
        'runtimes': []
      });
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('runtime-target-menu-api')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('runtime-target-name')), 'API service');
    await tester.tap(find.byKey(const Key('runtime-target-save')));
    await tester.pump();
    expect(saves, 1);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('runtime-target-save')))
            .onPressed,
        isNull);
    pending.complete(http.Response(
        jsonEncode({'error': 'Could not save profile'}), 400,
        headers: {'content-type': 'application/json'}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('runtime-target-name')), findsOneWidget);
    expect(find.textContaining('Could not save profile'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('runtime-target-save')))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'one click configures all subprojects, preserves Docker settings and shows missing commands',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var targets = <Map<String, dynamic>>[
      {
        'directory': 'api',
        'configuration': {'start_command': ''}
      },
      {
        'directory': 'client',
        'configuration': {'start_command': './custom-client'}
      },
    ];
    final proposal = [
      target('api'),
      targets[1],
      {
        'directory': 'shared',
        'reason': 'Shared library has no independent start command.',
        'configuration': {'start_command': ''}
      },
    ];
    final detection = Completer<http.Response>();
    var detections = 0;
    Map<String, dynamic>? saved;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/runtime')) {
        expect(request.method, 'GET');
        return response({
          'preferences': {
            'locations': {'api': 'docker'}
          },
          'targets': targets,
          'runtimes': []
        });
      }
      if (request.url.path.endsWith('/environment/detect')) {
        detections++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['agent'], true);
        expect(body['all_targets'], true);
        expect(body['current_targets'][1]['configuration']['start_command'],
            './custom-client');
        expect(body.containsKey('target_directory'), false);
        expect(body.containsKey('requirements'), false);
        return detection.future;
      }
      expect(request.url.path, '/v2/projects/p/environment');
      if (request.method == 'POST') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        targets =
            (saved!['build_targets'] as List).cast<Map<String, dynamic>>();
        return response({'config': saved});
      }
      return response({
        'config': {
          'mode': 'image',
          'image': 'local/custom-image:latest',
          'dockerfile': 'FROM local/base',
          'build_targets': targets,
        }
      });
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('runtime-start-required-api')),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('runtime-start-api')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const Key('runtime-auto-configure')));
    await tester.pump();
    expect(detections, 1);
    expect(
        find.text(
            'Identifying subproject settings from project files; Agent will fill unresolved settings if needed…'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('runtime-auto-configure')))
            .onPressed,
        isNull);
    expect(saved, isNull);
    detection.complete(response({
      'targets': proposal,
      'reasoning': 'Configure the full project; shared is a library.',
    }));
    await tester.pumpAndSettle();
    expect(detections, 1);
    expect(saved!['mode'], 'image');
    expect(saved!['image'], 'local/custom-image:latest');
    expect(saved!['dockerfile'], 'FROM local/base');
    expect(saved!['rebuild'], false);
    expect((saved!['build_targets'] as List).length, 3);
    expect(saved!['build_targets'][1]['configuration']['start_command'],
        './custom-client');
    expect(
        find.text('Saved settings for 3 subprojects; 2 have a start command.'),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('runtime-start-required-api')), findsNothing);
    expect(find.byKey(const ValueKey('runtime-location-api-docker')),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('runtime-start-api')))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('runtime-start-shared')))
            .onPressed,
        isNull);
    expect(find.text('Shared library has no independent start command.'),
        findsOneWidget);
    expect(find.text('Configure the full project; shared is a library.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auto-configuration errors remain visible after status polling',
      (tester) async {
    var saves = 0;
    var detections = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/runtime')) {
        return response({
          'targets': [target('api')],
          'runtimes': []
        });
      }
      if (request.url.path.endsWith('/detect')) {
        detections++;
        return http.Response(jsonEncode({'error': 'No model configured'}), 400,
            headers: {'content-type': 'application/json'});
      }
      if (request.method == 'POST') saves++;
      return response({
        'config': {
          'build_targets': [target('api')]
        }
      });
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('runtime-auto-configure')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No model configured'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('No model configured'), findsOneWidget);
    expect(saves, 0);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('runtime-auto-configure')))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(const Key('runtime-auto-configure')));
    await tester.pumpAndSettle();
    expect(detections, 2);
    expect(saves, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('location is saved per subproject and restored when reopening',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final locations = <String, String>{};
    var starts = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/start')) {
          starts++;
          expect(body, {'directory': 'api'});
        } else {
          expect(request.url.path, '/v2/projects/p/runtime');
          locations[body['directory'] as String] = body['location'] as String;
        }
        return response({'saved': true});
      }
      return response({
        'preferences': {'locations': locations},
        'targets': [target('api'), target('client')],
        'runtimes': []
      });
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('runtime-location-api-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acceptance Docker environment').last);
    await tester.pumpAndSettle();
    expect(locations, {'api': 'docker'});
    expect(find.byKey(const ValueKey('runtime-location-client-host')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('runtime-location-api-docker')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('runtime-start-api')));
    await tester.pumpAndSettle();
    expect(starts, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'occupied and uncertain runtimes block duplicate starts and show their state',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = BridgeClient(
        httpClient: MockClient((request) async => response({
              'preferences': {'locations': {}},
              'targets': [target('api'), target('client')],
              'runtimes': [
                runtime('api', occupied: true),
                runtime('client', phase: 'unknown')
              ]
            })));
    addTearDown(client.dispose);
    await tester.pumpWidget(app(client));
    await tester.pumpAndSettle();
    expect(find.text('Leased by Agent: other-agent'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('runtime-start-api')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('runtime-stop-api')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('runtime-start-client')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('runtime-target-menu-api')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PopupMenuItem<String>>(find.widgetWithText(
                PopupMenuItem<String>, 'Stop before deleting'))
            .enabled,
        false);
    expect(
        tester
            .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, 'Rename'))
            .enabled,
        true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
