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

Future<void> open(WidgetTester tester, BridgeClient client) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AcceptanceEnvironmentScreen(client: client, projectId: 'project-a'),
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

void main() {
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
          'configuration': {'build_command': 'cargo build --release'}
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
