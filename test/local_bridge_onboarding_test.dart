import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/home_screen.dart';
import 'package:omni_code/src/services/local_bridge_setup.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets(
      'offers existing and local Bridge without starting an installation',
      (tester) async {
    final setup = _FakeSetup();
    await _pumpHome(tester, setup);
    expect(find.text('在这台电脑上运行 Bridge'), findsOneWidget);
    expect(find.text('连接已有 Bridge'), findsOneWidget);
    expect(setup.calls, 0);
  });

  testWidgets(
      'first launch with no running Bridge still shows installation choices',
      (tester) async {
    await _pumpHome(tester, _FakeSetup(), offline: true);
    expect(find.byKey(const Key('install-local-bridge')), findsOneWidget);
    expect(find.text('连接已有 Bridge'), findsOneWidget);
  });

  testWidgets('one click saves local connection and opens the workspace',
      (tester) async {
    appSettingsController.debugReplaceSettings(AppSettings.defaults().copyWith(
      bridgeUrl: 'http://other-computer:8787',
    ));
    final setup = _FakeSetup();
    final clientId = appSettingsController.settings.clientId;
    await _pumpHome(tester, setup);
    await tester.tap(find.byKey(const Key('install-local-bridge')));
    await tester.pumpAndSettle();

    expect(setup.calls, 1);
    expect(setup.clientId, clientId);
    expect(appSettingsController.settings.bridgeUrl, 'http://127.0.0.1:8787');
    expect(appSettingsController.settings.bridgeToken, 'local-token');
    expect(appSettingsController.settings.pendingClientAuthRequestId, isEmpty);
    expect(find.byKey(const Key('install-local-bridge')), findsNothing);
    expect(find.text('连接已有 Bridge'), findsNothing);
  });

  testWidgets(
      'installation shows progress and disables duplicate or competing actions',
      (tester) async {
    final completion = Completer<LocalBridgeSetupResult>();
    final setup = _FakeSetup(handler: (onProgress) {
      onProgress(const LocalBridgeSetupProgress(
          LocalBridgeSetupStage.downloading,
          fraction: 0.4));
      return completion.future;
    });
    await _pumpHome(tester, setup);
    final button = find.byKey(const Key('install-local-bridge'));
    await tester.tap(button);
    await tester.pump();

    expect(find.text('正在下载 Bridge…'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, l10n.authorizeThisDevice))
            .onPressed,
        isNull);
    await tester.tap(button);
    expect(setup.calls, 1);
    completion.complete(_result);
    await tester.pumpAndSettle();
  });

  testWidgets('failure keeps connection settings and supports retry',
      (tester) async {
    var fail = true;
    final setup = _FakeSetup(handler: (_) async {
      if (fail) {
        throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.downloadFailed);
      }
      return _result;
    });
    await _pumpHome(tester, setup);
    final button = find.byKey(const Key('install-local-bridge'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('未能下载适合此电脑'), findsOneWidget);
    expect(appSettingsController.settings.bridgeToken, isEmpty);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    fail = false;
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(setup.calls, 2);
    expect(appSettingsController.settings.bridgeToken, 'local-token');
  });

  testWidgets('mobile and web keep the existing remote connection flow',
      (tester) async {
    await _pumpHome(tester, _FakeSetup(supported: false));
    expect(find.byKey(const Key('install-local-bridge')), findsNothing);
    expect(find.text('下载 Bridge 服务'), findsOneWidget);
  });

  testWidgets('incompatible Bridge keeps onboarding and offers Agent help',
      (tester) async {
    final setup = _FakeSetup(
        handler: (_) async => throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.incompatibleVersion));
    await _pumpHome(tester, setup);
    await tester.tap(find.byKey(const Key('install-local-bridge')));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前 Bridge 版本与客户端不兼容'), findsOneWidget);
    expect(find.byKey(const Key('continue-bridge-with-agent')), findsOneWidget);
    expect(appSettingsController.settings.bridgeToken, isEmpty);
  });

  testWidgets(
      'offers Agent continuation after an unsupported environment failure',
      (tester) async {
    final setup = _FakeSetup(
        handler: (_) async => throw const LocalBridgeSetupException(
            LocalBridgeSetupFailure.unsupportedPlatform));
    await _pumpHome(tester, setup);
    expect(find.byKey(const Key('continue-bridge-with-agent')), findsNothing);
    await tester.tap(find.byKey(const Key('install-local-bridge')));
    await tester.pumpAndSettle();
    expect(find.text('通过 Agent 继续'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const Key('continue-bridge-with-agent')))
            .onPressed,
        isNotNull);
  });
}

const _result =
    LocalBridgeSetupResult(url: 'http://127.0.0.1:8787', token: 'local-token');

Future<void> _pumpHome(WidgetTester tester, LocalBridgeSetupService setup,
    {bool offline = false}) async {
  final client = BridgeClient(httpClient: MockClient((request) async {
    final connected =
        appSettingsController.settings.bridgeToken == 'local-token';
    if (!connected && offline) throw http.ClientException('Connection refused');
    if (!connected) return http.Response('unauthorized', 401);
    if (request.url.path == '/projects' ||
        request.url.path == '/v2/sessions' ||
        request.url.path == '/v2/codex/profiles') {
      expect(request.url.host, '127.0.0.1');
      return http.Response(jsonEncode({'data': []}), 200);
    }
    return http.Response('not found', 404);
  }));
  addTearDown(client.dispose);
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
    home: HomeScreen(client: client, localBridgeSetup: setup),
  ));
  await tester.pumpAndSettle();
}

class _FakeSetup implements LocalBridgeSetupService {
  _FakeSetup({this.supported = true, this.handler});
  final bool supported;
  final Future<LocalBridgeSetupResult> Function(
      void Function(LocalBridgeSetupProgress))? handler;
  int calls = 0;
  String? clientId;
  @override
  bool get isSupported => supported;
  @override
  Future<LocalBridgeSetupResult> installAndStart(
      {required String clientId,
      required void Function(LocalBridgeSetupProgress) onProgress}) {
    calls++;
    this.clientId = clientId;
    return handler?.call(onProgress) ?? Future.value(_result);
  }
}

class _MemoryStore implements AppSettingsStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}
