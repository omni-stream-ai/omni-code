import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/project_detail_screen.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/widgets/create_session_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
  });

  testWidgets('project detail refresh keeps expanded sessions visible',
      (tester) async {
    var requestCount = 0;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/projects/project-1/sessions') {
          requestCount += 1;
          return http.Response(
            jsonEncode({
              'data': [
                for (var i = 8; i >= 1; i--)
                  _sessionJson(
                    id: 'session-$i',
                    projectId: 'project-1',
                    title: requestCount == 1
                        ? 'Session $i'
                        : 'Refreshed Session $i',
                    updatedAt: '2026-05-05T${10 + i}:00:00.000',
                    preview: 'Preview $i',
                  ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: ProjectDetailScreen(
          client: client,
          project: _project(
            id: 'project-1',
            name: 'Project One',
            updatedAt: DateTime(2026, 5, 5, 11),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ProjectDetailScreen)),
    )!;
    final loadMore = find.text(l10n.loadMoreSessionsLabel);

    expect(find.text('Session 8'), findsOneWidget);
    expect(find.text('Session 2'), findsOneWidget);
    expect(find.text('Session 1'), findsNothing);
    expect(loadMore, findsOneWidget);

    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('Session 2'), findsOneWidget);
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text(l10n.loadMoreSessionsLabel), findsNothing);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 800));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(requestCount, 2);
    expect(find.text('Refreshed Session 2'), findsOneWidget);
    expect(find.text('Refreshed Session 1'), findsOneWidget);
    expect(find.text(l10n.loadMoreSessionsLabel), findsNothing);
  });

  testWidgets('create session dialog includes provider selection',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [
                  {
                    'id': 'codex-provider',
                    'name': 'Codex Provider',
                    'base_url': 'https://example.com/v1',
                    'format': 'codex',
                    'enabled': true,
                    'priority': 0,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<CreateSessionDialogResult>(
                    context: context,
                    builder: (_) => CreateSessionDialog(client: client),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;
    expect(find.text(l10n.providerSessionLabel), findsOneWidget);
    expect(find.text(l10n.providerAuto), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.providerAuto).last, findsOneWidget);
    expect(find.text(l10n.providerDefault).last, findsOneWidget);
    await tester.tap(find.text('Codex Provider').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Session');
    await tester.tap(find.text(l10n.create));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('create session dialog defaults to last selected provider for project',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        lastSelectedProviderByProject: const {
          'project-1': 'provider-2',
        },
      ),
    );
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [
                  {
                    'id': 'provider-1',
                    'name': 'Provider One',
                    'base_url': 'https://example.com/v1',
                    'format': 'codex',
                    'enabled': true,
                    'priority': 0,
                  },
                  {
                    'id': 'provider-2',
                    'name': 'Provider Two',
                    'base_url': 'https://example.com/v2',
                    'format': 'codex',
                    'enabled': true,
                    'priority': 1,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<CreateSessionDialogResult>(
                    context: context,
                    builder: (_) => CreateSessionDialog(
                      client: client,
                      initialProviderId: appSettingsController
                          .settings.lastSelectedProviderByProject['project-1'],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Provider Two'), findsOneWidget);
  });

  testWidgets('create session dialog defaults to auto when project has no saved provider',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [
                  {
                    'id': 'provider-1',
                    'name': 'Provider One',
                    'base_url': 'https://example.com/v1',
                    'format': 'codex',
                    'enabled': true,
                    'priority': 0,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<CreateSessionDialogResult>(
                    context: context,
                    builder: (_) => CreateSessionDialog(
                      client: client,
                      initialProviderId: appSettingsController
                          .settings.lastSelectedProviderByProject['project-1'],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)))!;
    expect(find.text(l10n.providerAuto), findsOneWidget);
  });

}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.home});

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

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

ProjectSummary _project({
  required String id,
  required String name,
  required DateTime updatedAt,
}) {
  return ProjectSummary(
    id: id,
    name: name,
    rootPath: '/tmp/$id',
    updatedAt: updatedAt,
    sessionCount: 0,
    lastSessionPreview: null,
  );
}

Map<String, Object?> _sessionJson({
  required String id,
  required String projectId,
  required String title,
  required String updatedAt,
  String? preview,
}) {
  return {
    'id': id,
    'project_id': projectId,
    'title': title,
    'agent': 'codex',
    'brief_reply_mode': false,
    'status': 'idle',
    'updated_at': updatedAt,
    'unread_count': 0,
    'last_message_preview': preview,
    'pending_approval': null,
  };
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      nextRequest.body = request.body;
      nextRequest.encoding = request.encoding;
    }
    final response = await _handler(nextRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
