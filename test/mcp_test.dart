import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/mcp_servers_screen.dart';
import 'package:omni_code/src/widgets/mcp_content_view.dart';
import 'package:omni_code/src/widgets/mcp_elicitation_dialog.dart';

void main() {
  test('MCP JSON schema validates typed required values and enum collections',
      () {
    final schema = <String, dynamic>{
      'type': 'object',
      'required': ['count', 'enabled', 'choices'],
      'properties': {
        'count': {'type': 'integer', 'minimum': 1, 'maximum': 5},
        'enabled': {'type': 'boolean'},
        'choices': {
          'type': 'array',
          'minItems': 1,
          'uniqueItems': true,
          'items': {
            'type': 'string',
            'enum': ['a', 'b']
          }
        },
      }
    };
    expect(
        validateMcpValue({
          'count': 3,
          'enabled': false,
          'choices': ['a']
        }, schema),
        isNull);
    for (final value in [
      {
        'count': '3',
        'enabled': false,
        'choices': ['a']
      },
      {
        'count': 0,
        'enabled': false,
        'choices': ['a']
      },
      {
        'count': 3,
        'choices': ['a']
      },
      {
        'count': 3,
        'enabled': false,
        'choices': ['a', 'a']
      },
      {
        'count': 3,
        'enabled': false,
        'choices': ['other']
      },
    ]) {
      expect(validateMcpValue(value, schema), isNotNull);
    }
  });
  test('MCP HTTP client preserves profile/session scope and reports failures',
      () async {
    final client = BridgeClient(httpClient: MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/v2/mcp/servers/work.api');
      expect(request.url.queryParameters,
          {'profile_id': 'work', 'session_id': 'session-id'});
      expect(jsonDecode(request.body), {
        'config': {'url': 'https://example.test/mcp'},
        'expected_revision': 'old'
      });
      return http.Response(
          jsonEncode({
            'data': {'revision': 'new', 'servers': {}}
          }),
          200);
    }));
    final result = await client.mcpRequest('servers/work.api',
        method: 'PUT',
        profileId: 'work',
        sessionId: 'session-id',
        body: {
          'config': {'url': 'https://example.test/mcp'},
          'expected_revision': 'old'
        });
    expect(result['revision'], 'new');
    final failure = BridgeClient(
        httpClient: MockClient((_) async => http.Response(
            jsonEncode({'error': 'Configuration changed'}), 409)));
    await expectLater(failure.mcpRequest('config'), throwsException);
  });
  test('MCP empty HTTP error identifies endpoint and missing Bridge API',
      () async {
    final client = BridgeClient(
        httpClient: MockClient((_) async => http.Response('', 404)));
    await expectLater(
        client.mcpRequest('config'),
        throwsA(predicate((error) =>
            error.toString().contains('HTTP 404 GET /v2/mcp/config') &&
            error.toString().contains('Update and restart'))));
  });
  testWidgets('MCP form sends typed answers and validates required inputs',
      (tester) async {
    Map<String, dynamic>? response;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      response = await showMcpElicitation(context, {
                        'mode': 'form',
                        'serverName': 'fixture',
                        'message': 'Count please',
                        'requestedSchema': {
                          'type': 'object',
                          'required': ['count', 'enabled'],
                          'properties': {
                            'count': {'type': 'integer', 'minimum': 1},
                            'enabled': {'type': 'boolean'}
                          }
                        }
                      });
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('count: Required'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mcp-field-count')), '3');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(response, {
      'action': 'accept',
      'content': {'count': 3, 'enabled': false},
      '_meta': null
    });
  });
  testWidgets('MCP form decline has a protocol action without fabricated data',
      (tester) async {
    Map<String, dynamic>? response;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      response = await showMcpElicitation(context, {
                        'mode': 'form',
                        'serverName': 'fixture',
                        'requestedSchema': {'type': 'object', 'properties': {}}
                      });
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(response, {'action': 'decline', 'content': null, '_meta': null});
  });
  testWidgets(
      'MCP result renders Markdown, structured output, errors and resource links',
      (tester) async {
    String? readUri;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: McpContentView(
                    value: {
          'isError': true,
          'content': [
            {'type': 'text', 'text': '**Tool response**'},
            {'type': 'resource_link', 'uri': 'fixture://notes', 'name': 'Notes'}
          ],
          'structuredContent': {'count': 3},
        },
                    onReadResource: (uri) async {
                      readUri = uri;
                    })))));
    expect(find.text('Tool response'), findsOneWidget);
    expect(find.textContaining('"count": 3'), findsOneWidget);
    expect(find.text('MCP tool returned an error'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    expect(readUri, 'fixture://notes');
  });
  testWidgets('MCP management edits a service in its profile and lists tools',
      (tester) async {
    final client = _McpClient();
    await tester.pumpWidget(
        MaterialApp(home: McpServersScreen(client: client, profileId: 'work')));
    await tester.pumpAndSettle();
    expect(find.text('fixture'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcp-server-fixture')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Echo tool'));
    expect(find.text('Echo tool'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('mcp-server-config')),
        jsonEncode({
          'command': 'python3',
          'args': ['changed.py'],
          'enabled': true
        }));
    await tester.tap(find.byKey(const Key('mcp-save-server')));
    await tester.pumpAndSettle();
    expect(client.saved.single['profile'], 'work');
    expect((client.saved.single['body'] as Map)['expected_revision'],
        'revision-1');
    expect(client.servers['fixture']['args'], ['changed.py']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('MCP config is usable while connection status is pending',
      (tester) async {
    final gate = Completer<void>();
    final client = _McpClient()..statusGate = gate;
    await tester
        .pumpWidget(MaterialApp(home: McpServersScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('fixture'), findsOneWidget);
    final add =
        tester.widget<FilledButton>(find.byKey(const Key('mcp-add-server')));
    expect(add.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('mcp-add-server')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add MCP service'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('MCP test connection does not claim chat tools are loaded',
      (tester) async {
    final client = _McpClient()
      ..chatRuntime = {'servers': [], 'observedAt': '2026-11-03T00:00:00Z'};
    await tester.pumpWidget(
        MaterialApp(home: McpServersScreen(client: client, sessionId: 'chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcp-server-fixture')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test connection: connected'), findsOneWidget);
    expect(find.text('Not loaded in the latest chat turn'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('MCP configuration remains editable when runtime is unavailable',
      (tester) async {
    final client = _McpClient()..runtimeUnavailable = true;
    await tester
        .pumpWidget(MaterialApp(home: McpServersScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Codex is unavailable'), findsOneWidget);
    expect(find.byKey(const Key('mcp-add-server')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mcp-add-server')));
    await tester.pumpAndSettle();
    expect(find.text('Add MCP service'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _McpClient extends BridgeClient {
  bool runtimeUnavailable = false;
  Completer<void>? statusGate;
  Map<String, dynamic>? chatRuntime;
  final saved = <Map<String, dynamic>>[];
  final servers = <String, dynamic>{
    'fixture': {
      'command': 'python3',
      'args': ['server.py'],
      'enabled': true
    }
  };
  @override
  Future<List<CodexProfileSummary>> listCodexProfiles(
          {bool forceRefresh = false}) async =>
      const [
        CodexProfileSummary(id: 'default', name: 'default'),
        CodexProfileSummary(id: 'work', name: 'Work')
      ];
  @override
  Future<Map<String, dynamic>> mcpRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      String profileId = 'default',
      String? sessionId}) async {
    if (path == 'config') {
      return {
        'servers': Map<String, dynamic>.from(servers),
        'revision': 'revision-1'
      };
    }
    if (path == 'status' || path == 'inventory') {
      if (runtimeUnavailable) throw StateError('Codex is unavailable');
      if (path == 'status') await statusGate?.future;
      return {
        'servers': [
          {
            'name': 'fixture',
            'runtimeStatus': 'connected',
            'authStatus': 'unsupported',
            'tools': {
              'echo': {
                'title': 'Echo tool',
                'inputSchema': {'type': 'object'}
              }
            },
            'resources': []
          }
        ],
        'connection': {'events': []},
        'sessionRuntime': chatRuntime
      };
    }
    if (path == 'requests') return {'requests': [], 'events': []};
    if (path.startsWith('servers/') && method == 'PUT') {
      saved.add({'profile': profileId, 'body': body});
      servers[path.substring('servers/'.length)] = body!['config'];
      return {'servers': servers, 'revision': 'revision-2'};
    }
    throw StateError('Unexpected MCP request: $method $path');
  }
}
