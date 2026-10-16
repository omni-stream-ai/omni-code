import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets(
    'uses the same value text style for settings dropdowns and text fields',
    (tester) async {
      await tester.pumpWidget(
        const _TestApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      final dropdown = tester.widget<DropdownButton<String>>(
        find
            .byWidgetPredicate(
              (widget) => widget is DropdownButton<String>,
            )
            .first,
      );

      expect(textField.style, isNotNull);
      expect(dropdown.style, equals(textField.style));
    },
  );

  testWidgets('saves notification sound preference', (tester) async {
    await tester.pumpWidget(const _TestApp(home: SettingsScreen()));
    await tester.pump();

    final dropdown = find.byKey(const Key('notification-sound-mode'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muted').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      appSettingsController.settings.notificationSoundMode,
      NotificationSoundMode.muted,
    );
  });

  testWidgets('can disable anonymous error diagnostics', (tester) async {
    await tester.pumpWidget(const _TestApp(home: SettingsScreen()));
    await tester.pump();

    final toggle = find.byKey(const Key('error-reporting-toggle'));
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pump();

    expect(appSettingsController.settings.errorReportingEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('does not restore target update version from saved settings',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(updateTargetVersion: '0.2.1'),
    );

    await tester.pumpWidget(
      const _TestApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    final matchingFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      matchingFields.any(
        (field) => field.controller?.text == '0.2.1',
      ),
      isFalse,
    );
  });

  testWidgets('shows compressed reply max chars instead of notification chars',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(compressAssistantReplyMaxChars: 75),
    );

    await tester.pumpWidget(
      const _TestApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Compressed reply max chars'), findsOneWidget);
    expect(find.text('Notification max chars'), findsNothing);

    final matchingFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      matchingFields.any(
        (field) => field.controller?.text == '75',
      ),
      isTrue,
    );
  });

  testWidgets('desktop settings form does not overflow at narrow widths',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const _TestApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('SETTINGS DESK'), findsOneWidget);
  });

  testWidgets('shows an error instead of throwing when bridge sync fails',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SettingsScreen(client: _FailingSettingsBridgeClient()),
      ),
    );
    await tester.pump();

    final approvalToggle = find.text('Enable AI-assisted approval');
    await tester.ensureVisible(approvalToggle);
    await tester.tap(approvalToggle);
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Failed to save settings'), findsOneWidget);
    expect(appSettingsController.settings.aiApprovalEnabled, isFalse);
  });

  testWidgets('selects a configured model for AI approval', (tester) async {
    final client = _RecordingSettingsBridgeClient();
    await tester.pumpWidget(
      _TestApp(home: SettingsScreen(client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approval model'), findsOneWidget);
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('API Key'), findsNothing);
    expect(find.byKey(const Key('ai-approval-prompt-entry')), findsOneWidget);
    expect(find.byKey(const Key('ai-approval-prompt-field')), findsNothing);

    final approvalModel = find.byKey(
      const ValueKey('ai-approval-provider-'),
    );
    await tester.ensureVisible(approvalModel);
    await tester.tap(approvalModel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primary').last);
    await tester.pumpAndSettle();
    expect(find.text('gpt-test'), findsWidgets);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(client.includeAiApproval, isTrue);
    expect(client.aiApprovalProvider?.id, 'primary');
    expect(client.aiApprovalProvider?.model, 'gpt-test');
    expect(appSettingsController.settings.aiApprovalProviderId, 'primary');
    expect(appSettingsController.settings.aiApprovalApiKey, isEmpty);
  });

  testWidgets('ordinary save does not overwrite bridge AI approval',
      (tester) async {
    final client = _RecordingSettingsBridgeClient();
    await tester.pumpWidget(
      _TestApp(home: SettingsScreen(client: client)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(client.updateCalls, 0);
    expect(client.connectionChecks, 0);
  });

  testWidgets('saving a new bridge URL connects before leaving settings',
      (tester) async {
    const nextUrl = 'http://10.0.0.8:8787';
    final connection = Completer<http.Response>();
    final requests = <Uri>[];
    final client = BridgeClient(
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/projects') {
          if (request.url != Uri.parse('$nextUrl/projects')) {
            return http.Response(jsonEncode({'data': []}), 200);
          }
          expect(appSettingsController.settings.bridgeUrl, nextUrl);
          return connection.future;
        }
        return _settingsResponse();
      }),
    );
    await client.listProjects();
    requests.clear();
    await _openSettings(tester, client);

    await _saveBridgeUrl(tester, nextUrl);

    expect(requests, contains(Uri.parse('$nextUrl/projects')));
    expect(find.byType(SettingsScreen), findsOneWidget);
    final connecting = find.widgetWithText(FilledButton, 'Connecting...');
    expect(connecting, findsOneWidget);
    expect(tester.widget<FilledButton>(connecting).onPressed, isNull);

    connection.complete(http.Response(jsonEncode({'data': []}), 200));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings saved. Connected to Bridge.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed bridge connection returns to the home connect state',
      (tester) async {
    const nextUrl = 'http://10.0.0.8:8787';
    var attempts = 0;
    final client = BridgeClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/projects') {
          expect(request.url, Uri.parse('$nextUrl/projects'));
          attempts++;
          if (attempts == 1) throw http.ClientException('bridge unavailable');
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return _settingsResponse();
      }),
    );
    await _openSettings(tester, client);

    await _saveBridgeUrl(tester, nextUrl);
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(appSettingsController.settings.bridgeUrl, nextUrl);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(attempts, 1);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bridge connection timeout returns to the home connect state',
      (tester) async {
    const nextUrl = 'http://10.0.0.8:8787';
    final connection = Completer<http.Response>();
    final client = BridgeClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/projects') return connection.future;
        return _settingsResponse();
      }),
    );
    await _openSettings(tester, client);

    await _saveBridgeUrl(tester, nextUrl);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(appSettingsController.settings.bridgeUrl, nextUrl);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openSettings(WidgetTester tester, BridgeClient client) async {
  await tester.pumpWidget(
    const _TestApp(home: Scaffold(body: Text('Home'))),
  );
  unawaited(
    Navigator.of(tester.element(find.text('Home'))).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(client: client),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _saveBridgeUrl(WidgetTester tester, String url) async {
  final field = find.byKey(const Key('settings-bridge-url'));
  await tester.ensureVisible(field);
  await tester.enterText(field, url);
  await tester.ensureVisible(find.text('Save'));
  await tester.tap(find.text('Save'));
  await tester.pump();
}

http.Response _settingsResponse() {
  return http.Response(
    jsonEncode({
      'data': {'model_providers': [], 'prompt': ''},
    }),
    200,
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.home,
  });

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: home,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class _FailingSettingsBridgeClient extends BridgeClient {
  @override
  Future<List<ModelProviderConfig>> getModelProviders() async => [
        const ModelProviderConfig(
          id: 'primary',
          name: 'Primary',
          baseUrl: 'https://example.test/v1',
        ),
      ];

  @override
  Future<List<String>> getProviderModels(ModelProviderConfig provider) async =>
      ['gpt-test'];

  @override
  Future<void> updateBridgeSettings(
    AppSettings settings, {
    List<ModelProviderConfig>? modelProviders,
    bool includeAiApproval = false,
    ModelProviderConfig? aiApprovalProvider,
    String? aiApprovalPrompt,
  }) async {
    throw Exception('bridge unavailable');
  }
}

class _RecordingSettingsBridgeClient extends BridgeClient {
  int updateCalls = 0;
  int connectionChecks = 0;
  bool? includeAiApproval;
  ModelProviderConfig? aiApprovalProvider;

  @override
  Future<List<ProjectSummary>> listProjects({bool forceRefresh = false}) async {
    connectionChecks++;
    return [];
  }

  @override
  Future<List<ModelProviderConfig>> getModelProviders() async => [
        const ModelProviderConfig(
          id: 'primary',
          name: 'Primary',
          baseUrl: 'https://example.test/v1',
          apiKey: 'bridge-secret',
        ),
      ];

  @override
  Future<List<String>> getProviderModels(ModelProviderConfig provider) async =>
      ['gpt-test'];

  @override
  Future<void> updateBridgeSettings(
    AppSettings settings, {
    List<ModelProviderConfig>? modelProviders,
    bool includeAiApproval = false,
    ModelProviderConfig? aiApprovalProvider,
    String? aiApprovalPrompt,
  }) async {
    updateCalls++;
    this.includeAiApproval = includeAiApproval;
    this.aiApprovalProvider = aiApprovalProvider;
  }
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? _body;

  @override
  Future<String?> read() async => _body;

  @override
  Future<void> write(String body) async {
    _body = body;
  }
}
