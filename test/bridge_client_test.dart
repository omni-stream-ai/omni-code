import 'dart:convert';
import 'dart:io';

import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/bridge_speech_models.dart';
import 'package:omni_code/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('BridgeClient project ordering', () {
    test('sortProjectsForDisplay orders projects by updatedAt descending', () {
      final older = _project(
        id: 'older',
        updatedAt: DateTime(2026, 5, 5, 10),
      );
      final newer = _project(
        id: 'newer',
        updatedAt: DateTime(2026, 5, 5, 11),
      );

      final sorted = BridgeClient.sortProjectsForDisplay([older, newer]);

      expect(sorted.map((item) => item.id).toList(), ['newer', 'older']);
    });

    test('syncSessionSummary promotes active project to first', () {
      final client = BridgeClient();
      final older = _project(
        id: 'older',
        updatedAt: DateTime(2026, 5, 5, 10),
      );
      final newer = _project(
        id: 'newer',
        updatedAt: DateTime(2026, 5, 5, 11),
      );

      client.debugSeedProjects([older, newer]);
      client.syncSessionSummary(
        _session(
          id: 'session-1',
          projectId: 'older',
          updatedAt: DateTime(2026, 5, 5, 12),
          lastMessagePreview: 'latest activity',
        ),
      );

      final projects = client.peekProjects();
      expect(projects, isNotNull);
      expect(projects!.map((item) => item.id).toList(), ['older', 'newer']);
      expect(projects.first.lastSessionPreview, 'latest activity');
      expect(projects.first.sessionCount, 1);
      expect(projects.first.updatedAt, DateTime(2026, 5, 5, 12));
    });

    test(
      'listProjects keeps newer local project state when network is older',
      () async {
        final client = BridgeClient(
          httpClient: _FakeHttpClient((request) async {
            expect(request.url.path, '/projects');
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'alpha',
                    'name': 'Alpha',
                    'root_path': '/tmp/alpha',
                    'updated_at': '2026-05-05T11:00:00.000',
                    'session_count': 0,
                    'last_session_preview': null,
                  },
                  {
                    'id': 'beta',
                    'name': 'Beta',
                    'root_path': '/tmp/beta',
                    'updated_at': '2026-05-05T10:00:00.000',
                    'session_count': 0,
                    'last_session_preview': null,
                  },
                ],
              }),
              200,
            );
          }),
        );

        client.debugSeedProjects([
          _project(
            id: 'alpha',
            updatedAt: DateTime(2026, 5, 5, 11),
          ),
          _project(
            id: 'beta',
            updatedAt: DateTime(2026, 5, 5, 10),
          ),
        ]);
        client.syncSessionSummary(
          _session(
            id: 'session-beta',
            projectId: 'beta',
            updatedAt: DateTime(2026, 5, 5, 12),
            lastMessagePreview: 'latest activity',
          ),
        );

        final projects = await client.listProjects(forceRefresh: true);

        expect(projects.map((item) => item.id).toList(), ['beta', 'alpha']);
        expect(projects.first.updatedAt, DateTime(2026, 5, 5, 12));
        expect(projects.first.lastSessionPreview, 'latest activity');
      },
    );
  });

  group('BridgeClient createSession', () {
    test('sends the requested agent id in the request body', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'session-1',
                'project_id': 'project-1',
                'title': 'Test',
                'agent': 'claude_code',
                'brief_reply_mode': false,
                'status': 'idle',
                'updated_at': '2026-05-05T11:00:00.000',
                'unread_count': 0,
                'last_message_preview': null,
                'pending_approval': null,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final session = await client.createSession(
        projectId: 'project-1',
        title: 'Test',
        agent: 'claude_code',
        briefReplyMode: false,
      );

      expect(body['project_id'], 'project-1');
      expect(body['title'], 'Test');
      expect(body['agent'], 'claude_code');
      expect(body.containsKey('provider_id'), isFalse);
      expect(session.agentId, 'claude_code');
    });

    test('includes provider id when specified', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'session-2',
                'project_id': 'project-1',
                'title': 'Provider Session',
                'agent': 'codex',
                'brief_reply_mode': false,
                'status': 'idle',
                'updated_at': '2026-05-05T11:00:00.000',
                'unread_count': 0,
                'last_message_preview': null,
                'pending_approval': null,
                'provider_id': 'openai',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final session = await client.createSession(
        projectId: 'project-1',
        title: 'Provider Session',
        agent: 'codex',
        providerId: 'openai',
      );

      expect(body['provider_id'], 'openai');
      expect(session.providerId, 'openai');
    });

    test('includes AUTO provider id for provider auto mode', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'session-3',
                'project_id': 'project-1',
                'title': 'Auto Provider Session',
                'agent': 'codex',
                'brief_reply_mode': false,
                'status': 'idle',
                'updated_at': '2026-05-05T11:00:00.000',
                'unread_count': 0,
                'last_message_preview': null,
                'pending_approval': null,
                'provider_id': 'AUTO',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final session = await client.createSession(
        projectId: 'project-1',
        title: 'Auto Provider Session',
        agent: 'codex',
        providerId: autoProviderId,
      );

      expect(body['provider_id'], 'AUTO');
      expect(session.providerId, 'AUTO');
    });
  });

  group('BridgeClient cancelReply', () {
    test('accepts bridge cancel result bodies', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions/session-1/cancel');
          return http.Response(
            jsonEncode({
              'data': {'cancelled': true},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final cancelled = await client.cancelReply('session-1');

      expect(cancelled, isTrue);
    });

    test('returns false when bridge reports no active turn was cancelled',
        () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions/session-1/cancel');
          return http.Response(
            jsonEncode({
              'data': {'cancelled': false},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final cancelled = await client.cancelReply('session-1');

      expect(cancelled, isFalse);
    });

    test('keeps accepting legacy empty cancel responses', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions/session-1/cancel');
          return http.Response('', 204);
        }),
      );

      final cancelled = await client.cancelReply('session-1');

      expect(cancelled, isTrue);
    });
  });

  group('SessionStatus parsing', () {
    test('parses interrupted sessions', () {
      expect(parseSessionStatus('interrupted'), SessionStatus.interrupted);
    });
  });

  group('BridgeClient agents', () {
    test('listAgents decodes install status', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/agents');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'codex',
                  'label': 'Codex',
                  'aliases': ['codex'],
                  'selectable': true,
                  'default_selected': true,
                  'compatible_formats': ['codex'],
                  'installed': true,
                  'installed_path': '/usr/local/bin/codex',
                  'install_hint': 'manual hint',
                },
                {
                  'id': 'open_code',
                  'label': 'OpenCode',
                  'aliases': ['open_code', 'opencode'],
                  'selectable': true,
                  'default_selected': false,
                  'compatible_formats': [
                    'openai-compatible',
                    'anthropic-messages',
                    'codex',
                  ],
                  'installed': false,
                  'installed_path': null,
                  'install_hint': 'install via brew',
                },
                {
                  'id': 'custom',
                  'label': 'Custom Agent',
                  'aliases': ['fallback'],
                  'selectable': false,
                  'default_selected': false,
                  'compatible_formats': ['openai-compatible'],
                  'installed': false,
                  'installed_path': null,
                  'install_hint': 'n/a',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final agents = await client.listAgents();

      expect(agents, hasLength(3));
      expect(agents.first.id, 'codex');
      expect(agents.first.installed, isTrue);
      expect(agents[1].id, 'open_code');
      expect(agents[1].installed, isFalse);
      expect(agents[2].selectable, isFalse);
      expect(client.agentDescriptorFor('claudecode').id, 'claudecode');
      expect(client.agentDescriptorFor('custom').label, 'Custom Agent');
    });

    test('listAgentCommands decodes slash metadata', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/agents/commands');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'kind': 'codex',
                  'commands': [
                    {
                      'name': '/review',
                      'description': 'Review the diff',
                      'aliases': ['/rev'],
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final commands = await client.listAgentCommands();

      expect(commands, hasLength(1));
      expect(commands.first.name, '/review');
      expect(commands.first.description, 'Review the diff');
      expect(commands.first.agentId, 'codex');
      expect(commands.first.aliases, ['/rev']);
    });

    test('listFileCompletions sends prefix and session id', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/files/completions');
          expect(request.url.queryParameters['prefix'], 'lib/src/scr');
          expect(request.url.queryParameters['session_id'], 'session-1');
          expect(request.url.queryParameters['limit'], '8');
          return http.Response(
            jsonEncode({
              'data': [
                {'path': 'lib/src/screens/', 'is_dir': true},
                {
                  'path': 'lib/src/screens/session_detail_screen.dart',
                  'is_dir': false
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final items = await client.listFileCompletions(
        prefix: 'lib/src/scr',
        sessionId: 'session-1',
        limit: 8,
      );

      expect(items, hasLength(2));
      expect(items.first.path, 'lib/src/screens/');
      expect(items.first.isDir, isTrue);
      expect(items.last.path, 'lib/src/screens/session_detail_screen.dart');
      expect(items.last.isDir, isFalse);
    });

    test('installAgent posts selected agent and decodes result', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/agents/install');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'agent': 'claude_code',
                'success': true,
                'message': 'installed',
                'installed_path': '/usr/local/bin/claude',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.installAgent('claude_code');

      expect(body['agent'], 'claude_code');
      expect(result.agentId, 'claude_code');
      expect(result.success, isTrue);
      expect(result.installedPath, '/usr/local/bin/claude');
    });

    test('includes provider id when specified', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'session-2',
                'project_id': 'project-1',
                'title': 'Provider Session',
                'agent': 'codex',
                'brief_reply_mode': false,
                'status': 'idle',
                'updated_at': '2026-05-05T11:00:00.000',
                'unread_count': 0,
                'last_message_preview': null,
                'pending_approval': null,
                'provider_id': 'openai',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final session = await client.createSession(
        projectId: 'project-1',
        title: 'Provider Session',
        agent: 'codex',
        providerId: 'openai',
      );

      expect(body['provider_id'], 'openai');
      expect(session.providerId, 'openai');
    });

    test('includes AUTO provider id for provider auto mode', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sessions');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'session-3',
                'project_id': 'project-1',
                'title': 'Auto Provider Session',
                'agent': 'codex',
                'brief_reply_mode': false,
                'status': 'idle',
                'updated_at': '2026-05-05T11:00:00.000',
                'unread_count': 0,
                'last_message_preview': null,
                'pending_approval': null,
                'provider_id': 'AUTO',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final session = await client.createSession(
        projectId: 'project-1',
        title: 'Auto Provider Session',
        agent: 'codex',
        providerId: autoProviderId,
      );

      expect(body['provider_id'], 'AUTO');
      expect(session.providerId, 'AUTO');
    });
  });

  group('BridgeClient readFile', () {
    test('uses session_id for relative paths', () async {
      late Uri requestUri;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          requestUri = request.url;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );

      final response = await client.readFile(
        'assets/logo.png',
        sessionId: 'session-1',
      );

      expect(requestUri.path, '/files');
      expect(requestUri.queryParameters, {
        'path': 'assets/logo.png',
        'session_id': 'session-1',
      });
      expect(response.contentType, 'image/png');
      expect(response.bytes, [1, 2, 3]);
    });

    test('does not send session_id for absolute paths', () async {
      late Uri requestUri;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          requestUri = request.url;
          return http.Response.bytes(
            [1],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );

      await client.readFile('/tmp/output.jpg', sessionId: 'session-1');

      expect(requestUri.queryParameters, {
        'path': '/tmp/output.jpg',
      });
    });
  });

  group('BridgeClient uploadFile', () {
    test('posts multipart file and parses upload response', () async {
      final dir = await Directory.systemTemp.createTemp('omni-code-test-');
      final file = File('${dir.path}/photo.png');
      await file.writeAsBytes([1, 2, 3]);

      late http.Request capturedRequest;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'uuid-photo.png',
                'file_name': 'photo.png',
                'content_type': 'image/png',
                'size_bytes': 12345,
                'url': '/uploads/uuid-photo.png',
                'absolute_url': 'http://127.0.0.1:8787/uploads/uuid-photo.png',
                'local_path': '/tmp/uuid-photo.png',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final upload = await client.uploadFile(file.path);

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.path, '/uploads');
      expect(
        capturedRequest.headers['content-type'],
        contains('multipart/form-data'),
      );
      expect(capturedRequest.body, contains('name="file"'));
      expect(capturedRequest.body, contains('filename="photo.png"'));
      expect(upload.fileName, 'photo.png');
      expect(upload.contentType, 'image/png');
      expect(
          upload.absoluteUrl, 'http://127.0.0.1:8787/uploads/uuid-photo.png');
      expect(upload.localPath, '/tmp/uuid-photo.png');
    });
  });

  group('BridgeClient listSessions', () {
    test('sorts sessions by updatedAt descending and seeds cache', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.url.path, '/sessions');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'session-oldest',
                  'project_id': 'project-1',
                  'title': 'Oldest',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T09:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
                {
                  'id': 'session-newest',
                  'project_id': 'project-1',
                  'title': 'Newest',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
                {
                  'id': 'session-middle',
                  'project_id': 'project-2',
                  'title': 'Middle',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T10:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final sessions = await client.listSessions();

      expect(
        sessions.map((item) => item.id).toList(),
        ['session-newest', 'session-middle', 'session-oldest'],
      );
      expect(
        client.peekSessions()?.map((item) => item.id).toList(),
        ['session-newest', 'session-middle', 'session-oldest'],
      );
    });

    test('parses fork source session id from session summaries', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/sessions');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'child-session',
                  'project_id': 'project-1',
                  'title': 'Child',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                  'forked_from_session_id': 'parent-session',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final sessions = await client.listSessions();

      expect(sessions.single.forkedFromSessionId, 'parent-session');
    });

    test(
        'force refresh replaces removed sessions instead of keeping stale cache',
        () async {
      var requestCount = 0;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.url.path, '/sessions');
          requestCount += 1;
          if (requestCount == 1) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'session-a',
                    'project_id': 'project-1',
                    'title': 'Session A',
                    'agent': 'codex',
                    'brief_reply_mode': false,
                    'status': 'idle',
                    'updated_at': '2026-05-05T11:00:00.000',
                    'unread_count': 0,
                    'last_message_preview': 'A',
                    'pending_approval': null,
                  },
                  {
                    'id': 'session-b',
                    'project_id': 'project-1',
                    'title': 'Session B',
                    'agent': 'codex',
                    'brief_reply_mode': false,
                    'status': 'idle',
                    'updated_at': '2026-05-05T10:00:00.000',
                    'unread_count': 0,
                    'last_message_preview': 'B',
                    'pending_approval': null,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'session-c',
                  'project_id': 'project-1',
                  'title': 'Session C',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T12:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': 'C',
                  'pending_approval': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await client.listSessions();
      final refreshed = await client.listSessions(forceRefresh: true);

      expect(refreshed.map((item) => item.id).toList(), ['session-c']);
      expect(client.peekSessions()?.map((item) => item.id).toList(), [
        'session-c',
      ]);
    });

  });

  group('BridgeClient route lookups', () {
    test('getProject returns a cached project by id', () async {
      final client = BridgeClient();
      final project = _project(
        id: 'alpha',
        updatedAt: DateTime(2026, 5, 5, 11),
      );
      client.debugSeedProjects([project]);

      final result = await client.getProject('alpha');

      expect(result.id, 'alpha');
    });

    test('getProjectSession loads a session by project and session id',
        () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.url.path, '/projects/project-1/sessions');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'session-1',
                  'project_id': 'project-1',
                  'title': 'Test Session',
                  'agent': 'codex',
                  'brief_reply_mode': false,
                  'status': 'idle',
                  'updated_at': '2026-05-05T11:00:00.000',
                  'unread_count': 0,
                  'last_message_preview': null,
                  'pending_approval': null,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final session = await client.getProjectSession('project-1', 'session-1');

      expect(session.id, 'session-1');
      expect(session.projectId, 'project-1');
    });
  });

  group('BridgeClient listProjectSessions', () {
    test(
      'force refresh replaces removed project sessions instead of keeping stale cache',
      () async {
        var requestCount = 0;
        final client = BridgeClient(
          httpClient: _FakeHttpClient((request) async {
            expect(request.url.path, '/projects/project-1/sessions');
            requestCount += 1;
            if (requestCount == 1) {
              return http.Response(
                jsonEncode({
                  'data': [
                    {
                      'id': 'session-a',
                      'project_id': 'project-1',
                      'title': 'Session A',
                      'agent': 'codex',
                      'brief_reply_mode': false,
                      'status': 'idle',
                      'updated_at': '2026-05-05T11:00:00.000',
                      'unread_count': 0,
                      'last_message_preview': 'A',
                      'pending_approval': null,
                    },
                    {
                      'id': 'session-b',
                      'project_id': 'project-1',
                      'title': 'Session B',
                      'agent': 'codex',
                      'brief_reply_mode': false,
                      'status': 'idle',
                      'updated_at': '2026-05-05T10:00:00.000',
                      'unread_count': 0,
                      'last_message_preview': 'B',
                      'pending_approval': null,
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'session-c',
                    'project_id': 'project-1',
                    'title': 'Session C',
                    'agent': 'codex',
                    'brief_reply_mode': false,
                    'status': 'idle',
                    'updated_at': '2026-05-05T12:00:00.000',
                    'unread_count': 0,
                    'last_message_preview': 'C',
                    'pending_approval': null,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        await client.listProjectSessions('project-1');
        final refreshed = await client.listProjectSessions(
          'project-1',
          forceRefresh: true,
        );

        expect(refreshed.map((item) => item.id).toList(), ['session-c']);
        expect(
          client
              .peekProjectSessions('project-1')
              ?.map((item) => item.id)
              .toList(),
          ['session-c'],
        );
      },
    );
  });

  group('BridgeClient speech APIs', () {
    test('getSpeechStatus parses bridge speech status payload', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/speech');
          return http.Response(
            jsonEncode({
              'data': {
                'root_dir': '/tmp/bridge/speech',
                'profiles': {
                  'asr_batch': 'sensevoice-small-int8',
                  'tts_default': 'vits-melo-tts-zh-en',
                },
                'voices': {
                  'tts_by_model': {
                    'vits-melo-tts-zh-en': '0',
                  },
                },
                'models': [
                  {
                    'id': 'sensevoice-small-int8',
                    'kind': 'asr',
                    'display_name': 'SenseVoice Small',
                    'description': 'Local batch ASR model',
                    'languages': ['zh', 'en'],
                    'runtime': 'offline',
                    'backend': 'onnx',
                    'capabilities': {
                      'streaming': false,
                      'realtime_asr': false,
                      'batch_asr': true,
                      'speech_synthesis': false,
                      'vad': false,
                      'endpointing': true,
                      'punctuation': true,
                      'inverse_text_normalization': true,
                      'multilingual': true,
                    },
                    'features': ['punctuation'],
                    'supports_profiles': ['asr_batch'],
                    'recommended_profiles': ['asr_batch'],
                    'download_url': 'https://example.com/model',
                    'installed': true,
                    'selected_by': ['asr_batch'],
                    'voices': [],
                  },
                  {
                    'id': 'vits-melo-tts-zh-en',
                    'kind': 'tts',
                    'display_name': 'VITS Melo TTS',
                    'description': 'Local bilingual TTS model',
                    'languages': ['zh', 'en'],
                    'runtime': 'offline',
                    'backend': 'onnx',
                    'capabilities': {
                      'streaming': false,
                      'realtime_asr': false,
                      'batch_asr': false,
                      'speech_synthesis': true,
                      'vad': false,
                      'endpointing': false,
                      'punctuation': false,
                      'inverse_text_normalization': false,
                      'multilingual': true,
                    },
                    'features': ['female-voice'],
                    'supports_profiles': ['tts_default'],
                    'recommended_profiles': ['tts_default'],
                    'download_url': 'https://example.com/tts',
                    'default_voice': '0',
                    'installed': true,
                    'selected_by': ['tts_default'],
                    'voices': ['0'],
                    'voice_details': [
                      {
                        'id': '0',
                        'name': 'MeloTTS Chinese-English Female',
                        'language': 'zh/en',
                        'accent': 'Chinese + English',
                        'gender': 'female',
                      },
                    ],
                  },
                ],
                'downloads': [
                  {
                    'task_id': 'task-1',
                    'model_id': 'silero-vad',
                    'status': 'downloading',
                    'progress_bytes': 50,
                    'total_bytes': 100,
                    'created_at': '2026-05-11T10:00:00.000',
                    'updated_at': '2026-05-11T10:00:05.000',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final status = await client.getSpeechStatus();

      expect(status.rootDir, '/tmp/bridge/speech');
      expect(status.profiles.asrBatch, 'sensevoice-small-int8');
      expect(status.profiles.ttsDefault, 'vits-melo-tts-zh-en');
      expect(status.voices.voiceForModel('vits-melo-tts-zh-en'), '0');
      expect(status.models, hasLength(2));
      expect(status.models.first.kind, SpeechModelKind.asr);
      expect(status.models.first.capabilities.batchAsr, isTrue);
      final ttsModel = status.models.last;
      expect(ttsModel.kind, SpeechModelKind.tts);
      expect(ttsModel.voiceDetails, hasLength(1));
      expect(
          ttsModel.voiceDetails.single.name, 'MeloTTS Chinese-English Female');
      expect(ttsModel.voiceDetails.single.language, 'zh/en');
      expect(ttsModel.voiceDetails.single.gender, 'female');
      expect(status.activeDownloads, hasLength(1));
      expect(
        status.activeDownloads.single.status,
        SpeechDownloadStatus.downloading,
      );
      expect(status.activeDownloads.single.progress, 0.5);
    });

    test('updateSpeechModelVoice stores a per-model TTS voice', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path,
              '/speech/models/kokoro-int8-multi-lang-v1_1/voice');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'tts_by_model': {
                  'kokoro-int8-multi-lang-v1_1': 'af_heart',
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final voices = await client.updateSpeechModelVoice(
        'kokoro-int8-multi-lang-v1_1',
        voice: 'af_heart',
      );

      expect(body['voice'], 'af_heart');
      expect(voices.voiceForModel('kokoro-int8-multi-lang-v1_1'), 'af_heart');
    });

    test('deleteSpeechModel sends delete request for model id', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'DELETE');
          expect(
              request.url.path, '/speech/models/kokoro-int8-multi-lang-v1_1');
          return http.Response('', 204);
        }),
      );

      await client.deleteSpeechModel('kokoro-int8-multi-lang-v1_1');
    });

    test('listSpeakers parses enrolled speaker records', () async {
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/speech/speakers');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'speaker-1',
                  'name': 'Jun',
                  'embedding_model_id': '3dspeaker-speech-eres2net-base',
                  'embedding_count': 2,
                  'created_at': '2026-05-18T10:00:00.000',
                  'updated_at': '2026-05-18T10:05:00.000',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final speakers = await client.listSpeakers();

      expect(speakers, hasLength(1));
      expect(speakers.single.id, 'speaker-1');
      expect(speakers.single.name, 'Jun');
      expect(speakers.single.embeddingCount, 2);
    });

    test('updateSpeakerFilter sends target speaker settings', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/speech/speaker-filter');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'enabled': true,
                'speaker_id': 'speaker-1',
                'threshold': 0.7,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final settings = await client.updateSpeakerFilter(
        const SpeakerFilterSettings(
          enabled: true,
          speakerId: 'speaker-1',
          threshold: 0.7,
        ),
      );

      expect(body['enabled'], isTrue);
      expect(body['speaker_id'], 'speaker-1');
      expect(body['threshold'], 0.7);
      expect(settings.enabled, isTrue);
      expect(settings.speakerId, 'speaker-1');
      expect(settings.threshold, 0.7);
    });

    test('synthesizeSpeech sends the selected voice', () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/audio/speech');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'audio/wav'},
          );
        }),
      );

      await client.synthesizeSpeech(
        'hello',
        model: 'vits-melo-tts-zh-en',
        voice: '2',
      );

      expect(body['model'], 'vits-melo-tts-zh-en');
      expect(body['input'], 'hello');
      expect(body['voice'], '2');
      expect(body['response_format'], 'wav');
    });

    test('synthesizeSpeech sanitizes punctuation and emoji for local TTS',
        () async {
      late Map<String, dynamic> body;
      final client = BridgeClient(
        httpClient: _FakeHttpClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'audio/wav'},
          );
        }),
      );

      await client.synthesizeSpeech('他说：“为什么❓”');

      expect(body['input'], '他说："为什么"');
      expect(body.containsKey('voice'), isFalse);
    });
  });
}

ProjectSummary _project({
  required String id,
  required DateTime updatedAt,
}) {
  return ProjectSummary(
    id: id,
    name: id,
    rootPath: '/tmp/$id',
    updatedAt: updatedAt,
    sessionCount: 0,
    lastSessionPreview: null,
  );
}

SessionSummary _session({
  required String id,
  required String projectId,
  required DateTime updatedAt,
  String? lastMessagePreview,
}) {
  return SessionSummary(
    id: id,
    projectId: projectId,
    title: id,
    agentId: 'codex',
    briefReplyMode: false,
    status: SessionStatus.idle,
    updatedAt: updatedAt,
    unreadCount: 0,
    lastMessagePreview: lastMessagePreview,
    pendingApproval: null,
  );
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
    } else {
      nextRequest.bodyBytes = await request.finalize().toBytes();
      nextRequest.headers
        ..clear()
        ..addAll(request.headers);
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
