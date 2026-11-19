import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/bridge_setup_agent_screen.dart';
import 'package:omni_code/src/services/bridge_setup_agent_model.dart';
import 'package:omni_code/src/services/local_bridge_setup.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';

import 'support/bridge_setup_agent_fakes.dart';

void main() {
  late FakeBridgeSetupHost host;
  late FakeBridgeSetupModel model;
  late BridgeAgentMemoryStore store;
  setUp(() {
    host = FakeBridgeSetupHost();
    model = FakeBridgeSetupModel();
    store = BridgeAgentMemoryStore();
    appSettingsController.debugReplaceStore(store);
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  Future<void> pump(WidgetTester tester,
      {List<ModelProviderConfig> remote = const [], Widget? home}) async {
    final client = BridgeClient(
        httpClient:
            MockClient((request) async => request.url.path == '/settings'
                ? http.Response(
                    jsonEncode({
                      'data': {
                        'model_providers': [
                          for (final provider in remote) provider.toJson()
                        ]
                      }
                    }),
                    200)
                : http.Response('Bridge unavailable', 503)));
    addTearDown(client.dispose);
    final screen = BridgeSetupAgentScreen(
        failure: LocalBridgeSetupFailure.unsupportedPlatform,
        client: client,
        host: host,
        model: model,
        setup: FakeBridgeSetupInstaller());
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home ?? screen,
      routes: {'/agent': (_) => screen},
    ));
    await tester.pumpAndSettle();
  }

  Future<void> fillModel(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const Key('provider-editor-name')), 'Recovery model');
    await tester.enterText(find.byKey(const Key('provider-editor-url')),
        'https://model.example/v1');
    await tester.enterText(find.byKey(const Key('provider-editor-key')),
        'private-model-credential');
    final modelField = find.byKey(const Key('provider-editor-model'));
    await tester.ensureVisible(modelField);
    await tester.enterText(modelField, 'test-model');
  }

  testWidgets('without models opens configuration before any model request',
      (tester) async {
    await pump(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('保存并继续'), findsOneWidget);
    expect(model.requests, isEmpty);
    expect(host.diagnoses, 0);
  });

  testWidgets(
      'saving a model persists it locally and automatically continues without Bridge',
      (tester) async {
    await pump(tester);
    await fillModel(tester);
    await tester.tap(find.text('保存并继续'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(model.requests, hasLength(1));
    expect(find.text('Agent diagnosis ready'), findsOneWidget);
    final restored =
        AppSettings.fromJson(jsonDecode(store.value!) as Map<String, dynamic>);
    expect(restored.localModelProviders.single.model, 'test-model');
    expect(
        restored.localModelProviders.single.apiKey, 'private-model-credential');
  });

  testWidgets('canceling configuration never starts the agent', (tester) async {
    await pump(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(model.requests, isEmpty);
    expect(find.textContaining('还没有可用的模型配置'), findsOneWidget);
  });

  testWidgets('requires an explicit model name before continuing',
      (tester) async {
    host.providers = [setupAgentProvider.copyWith(clearModel: true)];
    await pump(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('保存并继续'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(model.requests, isEmpty);
  });

  testWidgets('uses existing encrypted local model configuration directly',
      (tester) async {
    appSettingsController.debugReplaceSettings(AppSettings.defaults()
        .copyWith(localModelProviders: [setupAgentProvider]));
    await pump(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(model.requests, hasLength(1));
  });

  testWidgets(
      'detects an existing local Bridge configuration while Bridge is unavailable',
      (tester) async {
    host.providers = [setupAgentProvider];
    await pump(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(model.requests, hasLength(1));
  });

  testWidgets('can reuse a configured model from an accessible Bridge',
      (tester) async {
    await pump(tester, remote: [setupAgentProvider]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(model.requests, hasLength(1));
  });

  testWidgets('a failed settings save does not call the model', (tester) async {
    store.fail = true;
    await pump(tester);
    await fillModel(tester);
    await tester.tap(find.text('保存并继续'));
    await tester.pumpAndSettle();
    expect(model.requests, isEmpty);
    expect(find.textContaining('模型配置未能保存'), findsOneWidget);
  });

  testWidgets(
      'shows a proposed command and executes only after the user clicks run',
      (tester) async {
    host.providers = [setupAgentProvider];
    model = FakeBridgeSetupModel(
        handler: (_, call) async => call == 1
            ? const BridgeAgentMessage('assistant', '检查环境', calls: [
                BridgeAgentToolCall(
                    id: 'check',
                    name: 'run_command',
                    arguments: {'command': 'uname -m', 'reason': '检查处理器'})
              ])
            : const BridgeAgentMessage('assistant', '检查完成'));
    await pump(tester);
    expect(host.commands, isEmpty);
    final run = find.byKey(const Key('bridge-agent-approve'));
    await tester.ensureVisible(run);
    await tester.tap(run);
    await tester.pumpAndSettle();
    expect(host.commands, ['uname -m']);
    expect(find.text('检查完成'), findsOneWidget);
  });

  testWidgets('verified connection returns its result to the caller',
      (tester) async {
    host.providers = [setupAgentProvider];
    model = FakeBridgeSetupModel(
        handler: (_, __) async => const BridgeAgentMessage('assistant', '',
                calls: [
                  BridgeAgentToolCall(
                      id: 'connect', name: 'connect_bridge', arguments: {})
                ]));
    LocalBridgeSetupResult? connected;
    await pump(tester,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      connected = await Navigator.of(context)
                          .pushNamed<dynamic>('/agent');
                    },
                    child: const Text('Open assistant')))));
    await tester.tap(find.text('Open assistant'));
    await tester.pumpAndSettle();
    expect(host.connections, 1);
    expect(connected, setupAgentResult);
    expect(find.byType(BridgeSetupAgentScreen), findsNothing);
  });
}
