import 'dart:convert';

import 'package:omni_code/src/bridge_client.dart';
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
        agent: AgentKind.claudecode.id,
        briefReplyMode: false,
      );

      expect(body['project_id'], 'project-1');
      expect(body['title'], 'Test');
      expect(body['agent'], AgentKind.claudecode.id);
      expect(session.agent, AgentKind.claudecode);
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

    test('force refresh replaces removed sessions instead of keeping stale cache',
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
          client.peekProjectSessions('project-1')?.map((item) => item.id).toList(),
          ['session-c'],
        );
      },
    );
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
    agent: AgentKind.codex,
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
