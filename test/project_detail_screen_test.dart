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

Map<String, dynamic> _agentJson({
  required String id,
  required String label,
  required bool installed,
  required List<String> aliases,
  required List<String> compatibleFormats,
  bool selectable = true,
  bool defaultSelected = false,
  String? installedPath,
  String installHint = '',
}) {
  return {
    'id': id,
    'label': label,
    'aliases': aliases,
    'selectable': selectable,
    'default_selected': defaultSelected,
    'compatible_formats': compatibleFormats,
    'installed': installed,
    'installed_path': installedPath,
    'install_hint': installHint,
  };
}

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
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                _agentJson(
                  id: 'codex',
                  label: 'Codex',
                  aliases: const ['codex'],
                  compatibleFormats: const ['codex'],
                  defaultSelected: true,
                  installed: true,
                  installedPath: '/usr/local/bin/codex',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'claude_code',
                  label: 'Claude Code',
                  aliases: const ['claude_code', 'claudecode'],
                  compatibleFormats: const ['anthropic-messages'],
                  installed: true,
                  installedPath: '/usr/local/bin/claude',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'open_code',
                  label: 'OpenCode',
                  aliases: const ['open_code', 'opencode'],
                  compatibleFormats: const [
                    'openai-compatible',
                    'anthropic-messages',
                    'codex',
                  ],
                  installed: false,
                  installHint: 'install via brew',
                ),
                _agentJson(
                  id: 'custom',
                  label: 'Custom Agent',
                  aliases: const ['fallback'],
                  compatibleFormats: const ['openai-compatible'],
                  selectable: false,
                  installed: false,
                  installHint: 'n/a',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
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
    expect(find.text(l10n.agentInstalledStatus), findsNothing);

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

  testWidgets('create session dialog blocks create until agent is installed',
      (tester) async {
    var installCalls = 0;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                _agentJson(
                  id: 'codex',
                  label: 'Codex',
                  aliases: const ['codex'],
                  compatibleFormats: const ['codex'],
                  defaultSelected: true,
                  installed: false,
                  installHint: 'npm install -g @openai/codex',
                ),
                _agentJson(
                  id: 'claude_code',
                  label: 'Claude Code',
                  aliases: const ['claude_code', 'claudecode'],
                  compatibleFormats: const ['anthropic-messages'],
                  installed: true,
                  installedPath: '/usr/local/bin/claude',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'open_code',
                  label: 'OpenCode',
                  aliases: const ['open_code', 'opencode'],
                  compatibleFormats: const [
                    'openai-compatible',
                    'anthropic-messages',
                    'codex',
                  ],
                  installed: true,
                  installedPath: '/usr/local/bin/opencode',
                  installHint: 'manual',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/agents/install') {
          installCalls += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'agent': 'codex',
                'success': true,
                'message': 'installed successfully',
                'installed_path': '/usr/local/bin/codex',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [],
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
    expect(find.text(l10n.agentNotInstalledStatus), findsOneWidget);
    expect(find.text('npm install -g @openai/codex'), findsOneWidget);
    expect(
        find.text('Codex (${l10n.agentNotInstalledStatus})'), findsOneWidget);

    final installButton = tester.widget<FilledButton>(
      find.byKey(const Key('create-or-install-agent-button')),
    );
    expect(installButton.onPressed, isNotNull);
    expect(find.text(l10n.installAgent), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-or-install-agent-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(installCalls, 1);
    expect(find.text(l10n.agentInstalledStatus), findsNothing);

    final enabledCreateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.create),
    );
    expect(enabledCreateButton.onPressed, isNotNull);
  });

  testWidgets(
      'create session dialog shows install error and keeps install button',
      (tester) async {
    var installCalls = 0;
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                _agentJson(
                  id: 'codex',
                  label: 'Codex',
                  aliases: const ['codex'],
                  compatibleFormats: const ['codex'],
                  defaultSelected: true,
                  installed: false,
                  installHint: 'npm install -g @openai/codex',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/agents/install') {
          installCalls += 1;
          return http.Response(
            jsonEncode({
              'data': {
                'agent': 'codex',
                'success': false,
                'message': 'install failed',
                'installed_path': null,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [],
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
    await tester.tap(find.byKey(const Key('create-or-install-agent-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(installCalls, 1);
    expect(find.text('install failed'), findsOneWidget);
    expect(find.byKey(const Key('agent-install-error')), findsOneWidget);
    expect(find.text(l10n.installAgent), findsOneWidget);
    expect(find.text(l10n.agentNotInstalledStatus), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
      'create session dialog defaults to last selected provider for project',
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
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                _agentJson(
                  id: 'codex',
                  label: 'Codex',
                  aliases: const ['codex'],
                  compatibleFormats: const ['codex'],
                  defaultSelected: true,
                  installed: true,
                  installedPath: '/usr/local/bin/codex',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'claude_code',
                  label: 'Claude Code',
                  aliases: const ['claude_code', 'claudecode'],
                  compatibleFormats: const ['anthropic-messages'],
                  installed: true,
                  installedPath: '/usr/local/bin/claude',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'open_code',
                  label: 'OpenCode',
                  aliases: const ['open_code', 'opencode'],
                  compatibleFormats: const [
                    'openai-compatible',
                    'anthropic-messages',
                    'codex',
                  ],
                  installed: true,
                  installedPath: '/usr/local/bin/opencode',
                  installHint: 'manual',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
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

  testWidgets(
      'create session dialog defaults to auto when project has no saved provider',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                _agentJson(
                  id: 'codex',
                  label: 'Codex',
                  aliases: const ['codex'],
                  compatibleFormats: const ['codex'],
                  defaultSelected: true,
                  installed: true,
                  installedPath: '/usr/local/bin/codex',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'claude_code',
                  label: 'Claude Code',
                  aliases: const ['claude_code', 'claudecode'],
                  compatibleFormats: const ['anthropic-messages'],
                  installed: true,
                  installedPath: '/usr/local/bin/claude',
                  installHint: 'manual',
                ),
                _agentJson(
                  id: 'open_code',
                  label: 'OpenCode',
                  aliases: const ['open_code', 'opencode'],
                  compatibleFormats: const [
                    'openai-compatible',
                    'anthropic-messages',
                    'codex',
                  ],
                  installed: true,
                  installedPath: '/usr/local/bin/opencode',
                  installHint: 'manual',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
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

  testWidgets('create session dialog uses selectable agents and server default',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(lastSelectedAgent: 'unknown-agent'),
    );
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' && request.url.path == '/agents') {
          return http.Response(
            jsonEncode({
              'data': [
                _agentJson(
                  id: 'custom',
                  label: 'Custom Agent',
                  aliases: const ['fallback'],
                  compatibleFormats: const ['openai-compatible'],
                  selectable: false,
                  installed: false,
                  installHint: 'n/a',
                ),
                _agentJson(
                  id: 'open_code',
                  label: 'OpenCode',
                  aliases: const ['open_code', 'opencode'],
                  compatibleFormats: const [
                    'openai-compatible',
                    'anthropic-messages',
                    'codex',
                  ],
                  defaultSelected: true,
                  installed: true,
                  installedPath: '/usr/local/bin/opencode',
                  installHint: 'manual',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/settings') {
          return http.Response(
            jsonEncode({
              'data': {
                'model_providers': [],
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

    expect(find.text('OpenCode'), findsOneWidget);
    expect(find.text('Custom Agent'), findsNothing);
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
