import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/widgets/workspace_agent_composer.dart';
import 'package:omni_code/src/widgets/workspace_agent_panel.dart';

import 'workspace_agent_test.dart' as fixtures;

void main() {
  testWidgets(
      'main chat submits its own model and agent and binds retries to that configuration',
      (tester) async {
    Map<String, dynamic>? saved = {
      'provider_id': 'service',
      'model': 'model-a'
    };
    var agent = 'codex';
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/workspace-agent')) {
        expectSync(
            request.headers['X-Omni-Code-Workspace-Scope'], 'conversation');
        expectSync(request.headers['X-Omni-Code-Conversation-Id'], isNotEmpty);
        expectSync(request.headers['X-Omni-Code-Client-Id'], isNotEmpty);
      }
      if (request.url.path == '/settings') {
        return fixtures.ok({'model_providers': []});
      }
      if (request.url.path.endsWith('/model')) {
        if (request.method == 'PUT') {
          saved =
              jsonDecode(request.body)['selection'] as Map<String, dynamic>?;
        }
        return fixtures.ok({'selection': saved});
      }
      if (request.url.path.endsWith('/dispatch/settings')) {
        return fixtures.ok({'agent': agent});
      }
      if (request.url.path.endsWith('/chat')) {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (requests.length == 1) return http.Response('Try again', 503);
        return fixtures.ok([
          {'id': 'reply', 'role': 'assistant', 'content': 'Request accepted'}
        ]);
      }
      return fixtures.ok(fixtures.snapshot());
    }));
    final composer = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(
                    client: client,
                    composerController: composer,
                    inline: true)))));
    await tester.pumpAndSettle();
    expect(composer.modelError, isNull);
    expect(composer.selection, {'provider_id': 'service', 'model': 'model-a'});
    expect(composer.taskAgent, 'codex');
    // Server defaults changing after this client's selection must not choose its request settings.
    saved = {'provider_id': 'service', 'model': 'other-client-model'};
    agent = 'pi';
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Implement export');
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(requests.single['configuration'], {
      'selection': {'provider_id': 'service', 'model': 'model-a'},
      'agent': 'codex',
      'approval_mode': 'smart',
    });
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(requests[1]['request_id'], requests[0]['request_id']);
    expect(requests[1]['configuration'], requests[0]['configuration']);
    await composer.saveModel({'provider_id': 'service', 'model': 'model-b'});
    composer.setTaskAgent('pi');
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Implement export');
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(requests[2]['configuration'], {
      'selection': {'provider_id': 'service', 'model': 'model-b'},
      'agent': 'pi',
      'approval_mode': 'smart',
    });
    expect(requests[2]['request_id'], isNot(requests[0]['request_id']));
    await tester.pumpWidget(const SizedBox());
    composer.dispose();
    client.dispose();
  });

  testWidgets('choosing a task agent updates the next chat request immediately',
      (tester) async {
    var agent = 'pi';
    Map<String, dynamic>? sent;
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path == '/settings') {
        return fixtures.ok({'model_providers': []});
      }
      if (request.url.path.endsWith('/model')) {
        return fixtures.ok({'selection': null});
      }
      if (request.url.path.endsWith('/dispatch/settings')) {
        if (request.method == 'PUT') {
          agent = jsonDecode(request.body)['agent'] as String;
        }
        return fixtures.ok({'agent': agent});
      }
      if (request.url.path.endsWith('/chat')) {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return fixtures.ok([
          {'id': 'reply', 'role': 'assistant', 'content': 'Scheduled'}
        ]);
      }
      return fixtures.ok(fixtures.snapshot());
    }));
    final composer = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(
                    client: client,
                    composerController: composer,
                    inline: true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-assistant-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agent-dispatch-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(composer.taskAgent, 'codex');
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Work on the project');
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(sent!['configuration'],
        {'selection': null, 'agent': 'codex', 'approval_mode': 'smart'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    composer.dispose();
    client.dispose();
  });

  testWidgets(
      'chat waits for saved execution settings instead of using defaults',
      (tester) async {
    var unavailable = true;
    final requests = <Map<String, dynamic>>[];
    final client = BridgeClient(httpClient: MockClient((request) async {
      if (request.url.path == '/settings') {
        return fixtures.ok({'model_providers': []});
      }
      if (request.url.path.endsWith('/model')) {
        return fixtures.ok({
          'selection': {'provider_id': 'service', 'model': 'saved-model'}
        });
      }
      if (request.url.path.endsWith('/dispatch/settings')) {
        return unavailable
            ? http.Response('Try again', 503)
            : fixtures.ok({'agent': 'codex'});
      }
      if (request.url.path.endsWith('/chat')) {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return fixtures.ok([
          {'id': 'reply', 'role': 'assistant', 'content': 'Scheduled'}
        ]);
      }
      return fixtures.ok(fixtures.snapshot());
    }));
    final composer = WorkspaceAgentComposerController(client);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: WorkspaceAgentChat(
                    client: client,
                    composerController: composer,
                    inline: true)))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('home-assistant-input')), 'Implement export');
    await tester.pump();
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(composer.text.text, 'Implement export');
    unavailable = false;
    await tester.tap(find.byKey(const Key('home-assistant-send')));
    await tester.pumpAndSettle();
    expect(requests.single['configuration'], {
      'selection': {'provider_id': 'service', 'model': 'saved-model'},
      'agent': 'codex',
      'approval_mode': 'smart',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    composer.dispose();
    client.dispose();
  });
}
