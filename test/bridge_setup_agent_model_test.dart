import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/services/bridge_setup_agent_model.dart';

import 'support/bridge_setup_agent_fakes.dart';

void main() {
  const history = [
    BridgeAgentMessage('system', 'Help install Bridge'),
    BridgeAgentMessage('user', 'Repair installation')
  ];

  test(
      'Chat Completions preserves tool call IDs and provider reasoning on follow-ups',
      () async {
    final requests = <Map<String, dynamic>>[];
    final model = HttpBridgeSetupAgentModel(client: MockClient((request) async {
      expect(request.url.path, '/v1/chat/completions');
      expect(request.headers['Authorization'],
          'Bearer ${setupAgentProvider.apiKey}');
      expect(request.followRedirects, isFalse);
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'Inspect the environment',
                  'reasoning_content': 'provider reasoning',
                  'tool_calls': [
                    {
                      'id': 'check-1',
                      'type': 'function',
                      'function': {
                        'name': 'run_command',
                        'arguments': jsonEncode({
                          'command': 'uname -m',
                          'reason': 'Inspect architecture'
                        })
                      }
                    }
                  ]
                }
              }
            ]
          }),
          200);
    }));
    final reply = await model.next(setupAgentProvider, history);
    expect(reply.calls.single.arguments['command'], 'uname -m');
    await model.next(setupAgentProvider, [
      ...history,
      reply,
      const BridgeAgentMessage('tool', 'arm64', callId: 'check-1')
    ]);
    final messages = requests.last['messages'] as List;
    expect(messages[messages.length - 2]['reasoning_content'],
        'provider reasoning');
    expect(messages.last['tool_call_id'], 'check-1');
    expect(jsonEncode(requests), isNot(contains(setupAgentProvider.apiKey)));
  });

  test('Anthropic uses Messages tool schemas and returns matching tool results',
      () async {
    late Map<String, dynamic> requestBody;
    final model = HttpBridgeSetupAgentModel(client: MockClient((request) async {
      expect(request.url.path, '/v1/messages');
      expect(request.headers['x-api-key'], setupAgentProvider.apiKey);
      expect(request.headers, isNot(contains('Authorization')));
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'Check Bridge'},
              {
                'type': 'tool_use',
                'id': 'anthropic-call',
                'name': 'connect_bridge',
                'input': {}
              },
            ]
          }),
          200);
    }));
    final provider =
        setupAgentProvider.copyWith(format: ApiFormat.anthropicMessages);
    final reply = await model.next(provider, history);
    await model.next(provider, [
      ...history,
      reply,
      const BridgeAgentMessage('tool', 'not running', callId: 'anthropic-call')
    ]);
    expect(
        (requestBody['tools'] as List).first['input_schema']['type'], 'object');
    expect((requestBody['messages'] as List).last['content'][0]['tool_use_id'],
        'anthropic-call');
  });

  test(
      'Responses preserves reasoning items and function call output without server-side storage',
      () async {
    late Map<String, dynamic> requestBody;
    final reasoning = {
      'type': 'reasoning',
      'id': 'reasoning-item',
      'summary': [],
      'encrypted_content': 'opaque-reasoning'
    };
    final model = HttpBridgeSetupAgentModel(client: MockClient((request) async {
      expect(request.url.path, '/v1/responses');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'output': [
              reasoning,
              {
                'type': 'function_call',
                'id': 'output-id',
                'call_id': 'responses-call',
                'name': 'connect_bridge',
                'arguments': '{}'
              },
            ]
          }),
          200);
    }));
    final provider = setupAgentProvider.copyWith(format: ApiFormat.codex);
    final reply = await model.next(provider, history);
    await model.next(provider, [
      ...history,
      reply,
      const BridgeAgentMessage('tool', 'not running', callId: 'responses-call')
    ]);
    expect(requestBody['store'], isFalse);
    expect((requestBody['input'] as List)[1], reasoning);
    expect((requestBody['input'] as List).last, {
      'type': 'function_call_output',
      'call_id': 'responses-call',
      'output': 'not running'
    });
    expect((requestBody['tools'] as List).first['name'], 'run_command');
  });

  test('provider errors expose status only and never echo credentials',
      () async {
    final model = HttpBridgeSetupAgentModel(
        client: MockClient((_) async => http.Response(
            'Error containing ${setupAgentProvider.apiKey}', 401)));
    await expectLater(
        model.next(setupAgentProvider, history),
        throwsA(isA<BridgeAgentModelException>()
            .having((error) => error.statusCode, 'status', 401)));
  });

  test('incomplete or disabled models never make a request', () async {
    var requests = 0;
    final model = HttpBridgeSetupAgentModel(client: MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    await expectLater(
        model.next(setupAgentProvider.copyWith(clearModel: true), history),
        throwsA(isA<BridgeAgentModelException>()));
    await expectLater(
        model.next(setupAgentProvider.copyWith(enabled: false), history),
        throwsA(isA<BridgeAgentModelException>()));
    expect(requests, 0);
  });
}
