import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/settings_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/theme/app_theme.dart';

class _PromptServer {
  static const defaultPrompt =
      'Only identify explicit software development deliverables. Exclude ordinary questions and casual conversation.';
  String prompt = defaultPrompt;
  final savedPrompts = <String>[];
  int analyses = 0;
  bool failLoad = false;
  bool failSave = false;

  Future<http.Response> call(http.Request request) async {
    if (request.url.path == '/workspace-agent/analysis-settings') {
      if ((request.method == 'GET' && failLoad) ||
          (request.method == 'PUT' && failSave)) {
        return http.Response(
            jsonEncode({'error': 'Prompt service unavailable'}), 500);
      }
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final value = body['prompt'] as String;
        savedPrompts.add(value);
        prompt = value.trim().isEmpty ? defaultPrompt : value.trim();
      }
      return _ok({'prompt': prompt, 'default_prompt': defaultPrompt});
    }
    if (request.url.path.endsWith('/analyze')) analyses++;
    if (request.url.path == '/settings') {
      return _ok({'model_providers': []});
    }
    return _ok({'prompt': ''});
  }

  http.Response _ok(Object data) =>
      http.Response(jsonEncode({'data': data}), 200);
}

Widget _settings(BridgeClient client, {String language = 'en'}) => MaterialApp(
      locale: Locale(language),
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(client: client),
    );

Future<void> _openPrompt(WidgetTester tester) async {
  final entry = find.byKey(const Key('task-analysis-prompt-settings'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

void main() {
  setUp(
      () => appSettingsController.debugReplaceSettings(AppSettings.defaults()));
  tearDown(
      () => appSettingsController.debugReplaceSettings(AppSettings.defaults()));

  for (final width in [320.0, 1280.0]) {
    testWidgets('task prompt edits persist and reset explicitly at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      appSettingsController.debugReplaceSettings(
          AppSettings.defaults().copyWith(autoTaskAnalysisEnabled: false));
      final server = _PromptServer();
      final client = BridgeClient(httpClient: MockClient(server.call));
      addTearDown(client.dispose);
      await tester
          .pumpWidget(_settings(client, language: width == 320 ? 'zh' : 'en'));
      await tester.pumpAndSettle();
      await _openPrompt(tester);
      final field = find.byKey(const Key('task-analysis-prompt-field'));
      final save = find.byKey(const Key('task-analysis-prompt-save'));
      final reset = find.byKey(const Key('task-analysis-prompt-reset'));
      expect(tester.widget<TextField>(field).controller!.text,
          _PromptServer.defaultPrompt);
      if (width == 320) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      const custom = 'Include development, writing and research deliverables.';
      await tester.enterText(field, ' $custom ');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(server.prompt, custom);
      expect(server.savedPrompts, [custom]);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_settings(client));
      await tester.pumpAndSettle();
      await _openPrompt(tester);
      expect(tester.widget<TextField>(field).controller!.text, custom);
      await tester.tap(reset);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text,
          _PromptServer.defaultPrompt);
      expect(server.prompt, custom, reason: 'reset is an editable draft');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.savedPrompts, [custom]);

      await _openPrompt(tester);
      await tester.tap(reset);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(server.prompt, _PromptServer.defaultPrompt);
      expect(server.savedPrompts, [custom, _PromptServer.defaultPrompt]);
      await _openPrompt(tester);
      await tester.enterText(field, '   ');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(server.prompt, _PromptServer.defaultPrompt);
      expect(server.savedPrompts.last, '');
      expect(server.analyses, 0,
          reason: 'editing rules does not enable automatic analysis');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('load and save failures allow retries without losing the draft',
      (tester) async {
    final server = _PromptServer()..failLoad = true;
    final client = BridgeClient(httpClient: MockClient(server.call));
    addTearDown(client.dispose);
    await tester.pumpWidget(_settings(client));
    await tester.pumpAndSettle();
    await _openPrompt(tester);
    final field = find.byKey(const Key('task-analysis-prompt-field'));
    final save = find.byKey(const Key('task-analysis-prompt-save'));
    expect(find.textContaining('Prompt service unavailable'), findsOneWidget);
    expect(field, findsNothing);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    server.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Track documentation tasks too.');
    server.failSave = true;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text,
        'Track documentation tasks too.');
    expect(server.prompt, _PromptServer.defaultPrompt);
    server.failSave = false;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(server.prompt, 'Track documentation tasks too.');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
