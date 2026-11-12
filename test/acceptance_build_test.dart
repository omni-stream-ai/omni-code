import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/acceptance_environment_screen.dart';
import 'package:omni_code/src/theme/app_theme.dart';

http.Response reply(Object data) =>
    http.Response(jsonEncode({'data': data}), 200,
        headers: {'content-type': 'application/json'});

Future<void> open(WidgetTester tester, BridgeClient client,
    {String? sessionId,
    String? requirements,
    bool reviewBeforeStart = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AcceptanceEnvironmentScreen(
        client: client,
        projectId: 'project-a',
        sessionId: sessionId,
        requirements: requirements,
        reviewBeforeStart: reviewBeforeStart),
  ));
  await tester.pumpAndSettle();
}

Finder field(String name) => find.byKey(Key('acceptance-build-$name'));
String value(WidgetTester tester, String name) =>
    tester.widget<TextField>(field(name)).controller!.text;

Future<void> identify(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final button = find.byKey(const Key('acceptance-build-agent'));
  await tester.scrollUntilVisible(button, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

Future<void> selectTarget(WidgetTester tester, String label) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final chip = find.widgetWithText(FilterChip, label);
  await tester.scrollUntilVisible(chip, -250,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  if (!tester.widget<FilterChip>(chip).selected) {
    await tester.tap(chip);
    await tester.pumpAndSettle();
    return;
  }
  final target = find.byKey(const Key('acceptance-build-target'));
  if (target.evaluate().isEmpty) return;
  await tester.scrollUntilVisible(target, -250,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'requirements automatically identify both projects and edits survive reload',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final candidates = [
      {
        'directory': 'client',
        'configuration': {
          'language': 'flutter',
          'build_command': "cd 'client' && flutter build linux"
        },
        'evidence': ['client/pubspec.yaml'],
      },
      {
        'directory': 'bridge',
        'configuration': {
          'language': 'rust',
          'build_command': "cd 'bridge' && cargo build"
        },
        'evidence': ['bridge/Cargo.toml'],
      },
      {
        'directory': 'omni-code-bridge/crates/omni-relay-connector',
        'configuration': {'language': 'javascript'}
      },
    ];
    final identified = [
      {
        ...candidates[0],
        'role': 'Client application',
        'reason': 'Shows the login result'
      },
      {
        ...candidates[1],
        'role': 'Backend service',
        'reason': 'Provides the login API'
      },
    ];
    Map<String, dynamic>? saved, submitted;
    var agentRequests = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/detect')) {
        agentRequests++;
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return reply({
          'configuration': candidates[0]['configuration'],
          'candidates': candidates,
          'targets': identified,
          'reasoning': 'Login needs both the client and Bridge',
        });
      }
      if (request.method == 'POST') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return reply({
        'config': saved ?? {},
        'detection': {'configuration': {}, 'candidates': candidates}
      });
    }));
    await open(tester, client,
        sessionId: 'source-session',
        requirements: 'Verify client and Bridge login together',
        reviewBeforeStart: true);
    expect(agentRequests, 1);
    expect(submitted!['session_id'], 'source-session');
    expect(
        submitted!['requirements'], 'Verify client and Bridge login together');
    expect(find.text('Review detected configuration'), findsNothing);
    expect(
        tester
            .widget<FilterChip>(
                find.byKey(const Key('acceptance-build-include-client')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<FilterChip>(
                find.byKey(const Key('acceptance-build-include-bridge')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<FilterChip>(find.byKey(const Key(
                'acceptance-build-include-omni-code-bridge/crates/omni-relay-connector')))
            .selected,
        isFalse);
    expect(value(tester, 'language'), 'flutter');
    await tester.enterText(
        field('build_command'), "cd 'client' && custom-flutter-build");
    await selectTarget(tester, 'bridge · rust');
    expect(value(tester, 'language'), 'rust');
    expect(
        find.text('Backend service · Provides the login API'), findsOneWidget);
    await tester.enterText(
        field('start_command'), "cd 'bridge' && ./start-api");
    await selectTarget(tester, 'client · flutter');
    expect(
        value(tester, 'build_command'), "cd 'client' && custom-flutter-build");
    await tester.tap(find.byKey(const Key('acceptance-environment-save')));
    await tester.pumpAndSettle();
    expect(saved!['build_targets'], hasLength(2));
    expect(saved!['build_targets'][0]['configuration']['build_command'],
        "cd 'client' && custom-flutter-build");
    expect(saved!['build_targets'][1]['configuration']['start_command'],
        "cd 'bridge' && ./start-api");
    expect(saved!['build_reasoning'], 'Login needs both the client and Bridge');
    await tester.pumpWidget(const SizedBox());
    await open(tester, client);
    expect(agentRequests, 1);
    expect(
        value(tester, 'build_command'), "cd 'client' && custom-flutter-build");
    await selectTarget(tester, 'bridge · rust');
    expect(value(tester, 'start_command'), "cd 'bridge' && ./start-api");
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'automatic identification failure preserves saved custom configuration',
      (tester) async {
    var requests = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/detect')) {
        requests++;
        return http.Response(jsonEncode({'error': 'Agent unavailable'}), 503);
      }
      return reply({
        'config': {
          'build': {'language': 'rust', 'build_command': 'custom-build'}
        },
        'detection': {
          'candidates': [
            {
              'directory': 'client',
              'configuration': {'language': 'flutter'}
            },
            {
              'directory': 'bridge',
              'configuration': {'language': 'rust'}
            },
          ]
        },
      });
    }));
    await open(tester, client,
        requirements: 'Verify client and Bridge together',
        reviewBeforeStart: true);
    expect(requests, 1);
    expect(value(tester, 'build_command'), 'custom-build');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-environment-save')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'multiple targets keep independent edits and are all passed to Agent detection',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final candidates = [
      {
        'directory': 'omni-code',
        'configuration': {
          'language': 'flutter',
          'package_manager': 'flutter pub',
          'install_command': "cd 'omni-code' && flutter pub get",
          'build_command': "cd 'omni-code' && flutter build linux --release",
        },
        'evidence': ['omni-code/pubspec.yaml'],
      },
      {
        'directory': 'omni-code-bridge',
        'configuration': {
          'language': 'rust',
          'package_manager': 'cargo',
          'install_command': "cd 'omni-code-bridge' && cargo fetch",
          'build_command': "cd 'omni-code-bridge' && cargo build --release",
        },
        'evidence': ['omni-code-bridge/Cargo.toml'],
      },
    ];
    Map<String, dynamic>? saved, agentRequest;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/detect')) {
        agentRequest = jsonDecode(request.body) as Map<String, dynamic>;
        return reply({
          'configuration': agentRequest!['current'],
          'candidates': candidates,
        });
      }
      if (request.method == 'POST') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return reply({
        'config': {},
        'detection': {
          'configuration': {},
          'candidates': candidates,
          'evidence': ['omni-code/pubspec.yaml', 'omni-code-bridge/Cargo.toml'],
          'warnings': ['Multiple projects; choose a target'],
        }
      });
    }));
    await open(tester, client);
    expect(value(tester, 'language'), '');
    await selectTarget(tester, 'omni-code · flutter');
    expect(value(tester, 'language'), 'flutter');
    expect(value(tester, 'package_manager'), 'flutter pub');
    expect(value(tester, 'build_command'),
        "cd 'omni-code' && flutter build linux --release");
    expect(find.widgetWithText(Chip, 'omni-code/pubspec.yaml'), findsOneWidget);
    expect(
        find.widgetWithText(Chip, 'omni-code-bridge/Cargo.toml'), findsNothing);
    await tester.enterText(field('start_command'), './manual-start');
    await tester.enterText(field('artifact_directory'), 'manual-output');
    await selectTarget(tester, 'omni-code-bridge · rust');
    expect(value(tester, 'language'), 'rust');
    expect(value(tester, 'build_command'),
        "cd 'omni-code-bridge' && cargo build --release");
    expect(value(tester, 'start_command'), '');
    expect(value(tester, 'artifact_directory'), '');
    expect(find.widgetWithText(Chip, 'omni-code/pubspec.yaml'), findsNothing);
    await identify(tester);
    await tester.pumpAndSettle();
    expect(agentRequest!['current_targets'], hasLength(2));
    expect(
        agentRequest!['current_targets'][0]['configuration']['start_command'],
        './manual-start');
    expect(agentRequest!['current_targets'][1]['configuration']['language'],
        'rust');
    expect(agentRequest!.containsKey('target_directory'), isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptance-environment-save')));
    await tester.pumpAndSettle();
    expect(saved!['build_targets'], hasLength(2));
    expect(saved!['build_targets'][1]['configuration']['language'], 'rust');
    expect(saved!['build_targets'][1]['configuration']['start_command'], '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incomplete scan still permits an explicit target choice',
      (tester) async {
    final client = BridgeClient(
        httpClient: MockClient((_) async => reply({
              'config': {},
              'detection': {
                'configuration': {},
                'warnings': ['Directory scan is incomplete'],
                'candidates': [
                  {
                    'directory': '.',
                    'configuration': {
                      'language': 'go',
                      'build_command': 'go build ./...',
                    },
                  }
                ],
              }
            })));
    await open(tester, client);
    expect(value(tester, 'language'), '');
    await selectTarget(tester, '. · go');
    expect(value(tester, 'language'), 'go');
    expect(value(tester, 'build_command'), 'go build ./...');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'program detection is editable and saving preserves intentionally empty fields on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? saved;
    var agentRequests = 0;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/detect')) agentRequests++;
      if (request.method == 'POST') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return reply({
        'config': {},
        'detection': {
          'configuration': {
            'language': 'typescript',
            'package_manager': 'pnpm',
            'install_command': 'pnpm install',
            'build_command': 'pnpm run build',
          },
          'evidence': ['package.json', 'pnpm-lock.yaml']
        }
      });
    }));
    await open(tester, client);
    expect(value(tester, 'language'), 'typescript');
    expect(value(tester, 'start_command'), '');
    await tester.enterText(field('build_command'), 'pnpm run bundle');
    await tester.enterText(field('install_command'), '');
    await tester.tap(find.byKey(const Key('acceptance-environment-save')));
    await tester.pumpAndSettle();
    expect(saved!['build']['build_command'], 'pnpm run bundle');
    expect(saved!['build']['install_command'], '');
    expect(saved!['build']['start_command'], '');
    expect(agentRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved blanks override new detection and Agent proposals require application',
      (tester) async {
    final pending = Completer<http.Response>();
    Map<String, dynamic>? submitted;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/detect')) {
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return pending.future;
      }
      return reply({
        'config': {
          'build': {'language': 'rust', 'build_command': ''}
        },
        'detection': {
          'configuration': {'build_command': 'cargo build --release'},
          'candidates': [
            {
              'directory': '.',
              'configuration': {
                'language': 'rust',
                'build_command': 'cargo build --release'
              },
            }
          ],
        }
      });
    }));
    await open(tester, client);
    expect(value(tester, 'build_command'), '');
    await tester.enterText(
        field('build_command'), 'cargo build --profile acceptance');
    await identify(tester);
    expect(submitted!['agent'], true);
    expect(submitted!['current']['build_command'],
        'cargo build --profile acceptance');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-environment-save')))
            .onPressed,
        isNull);
    pending.complete(reply({
      'configuration': {
        'language': 'rust',
        'build_command': 'cargo build --release'
      }
    }));
    await tester.pumpAndSettle();
    expect(find.text('Review detected configuration'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value(tester, 'build_command'), 'cargo build --profile acceptance');
    await identify(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('acceptance-build-apply')));
    await tester.pumpAndSettle();
    expect(value(tester, 'build_command'), 'cargo build --release');
    expect(value(tester, 'install_command'), '');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed Agent detection leaves edits available and can be retried',
      (tester) async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/detect')) {
        return http.Response(jsonEncode({'error': 'Agent unavailable'}), 503);
      }
      return reply({
        'config': {},
        'detection': {'configuration': {}}
      });
    }));
    await open(tester, client);
    await tester.enterText(field('build_command'), 'custom-build');
    await identify(tester);
    await tester.pumpAndSettle();
    expect(value(tester, 'build_command'), 'custom-build');
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('acceptance-build-agent')))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('acceptance-environment-save')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
