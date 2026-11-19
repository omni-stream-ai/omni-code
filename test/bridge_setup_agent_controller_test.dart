import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/bridge_setup_agent_controller.dart';
import 'package:omni_code/src/services/bridge_setup_agent_model.dart';
import 'package:omni_code/src/services/local_bridge_setup.dart';

import 'support/bridge_setup_agent_fakes.dart';

void main() {
  late FakeBridgeSetupHost host;
  late FakeBridgeSetupModel model;
  late FakeBridgeSetupInstaller installer;
  BridgeSetupAgentController controller() {
    final value = BridgeSetupAgentController(
        model: model,
        host: host,
        setup: installer,
        clientId: 'desktop-client',
        failure: LocalBridgeSetupFailure.unsupportedPlatform,
        secrets: [setupAgentResult.token],
        language: 'zh');
    addTearDown(value.dispose);
    return value;
  }

  setUp(() {
    host = FakeBridgeSetupHost();
    model = FakeBridgeSetupModel();
    installer = FakeBridgeSetupInstaller();
  });

  test('does not start without a usable configured model', () async {
    final agent = controller();
    await agent.start(setupAgentProvider.copyWith(clearModel: true), 'repair');
    expect(model.requests, isEmpty);
    expect(host.diagnoses, 0);
    expect(agent.started, isFalse);
  });

  test('redacts credentials from diagnostics before the model request',
      () async {
    host.diagnosticData = {
      'log':
          'API_KEY="private-model-credential" token="private-bridge-token" OTHER_SECRET="hidden-secret"'
    };
    final agent = controller();
    await agent.start(setupAgentProvider, 'repair');
    final text = model.requests.single.map((message) => message.text).join();
    expect(text, isNot(contains(setupAgentProvider.apiKey)));
    expect(text, isNot(contains(setupAgentResult.token)));
    expect(text, isNot(contains('hidden-secret')));
    expect(text, contains('[redacted]'));
    expect(jsonDecode(model.requests.single[1].text)['diagnostics']['log'],
        contains('[redacted]'));
    expect(agent.messages.any((message) => message.hidden), isFalse);
  });

  test('waits for command approval then sends tool output back to the model',
      () async {
    model = FakeBridgeSetupModel(
        handler: (_, call) async => call == 1
            ? const BridgeAgentMessage('assistant', '检查环境', calls: [
                BridgeAgentToolCall(
                    id: 'command-1',
                    name: 'run_command',
                    arguments: {'command': 'uname -m', 'reason': '检查处理器'})
              ])
            : const BridgeAgentMessage('assistant', '检查完成'));
    final agent = controller();
    final running = agent.start(setupAgentProvider, 'repair');
    await Future<void>.delayed(Duration.zero);
    expect(agent.pendingCommand?.command, 'uname -m');
    expect(host.commands, isEmpty);
    agent.approveCommand(true);
    await running;
    expect(host.commands, ['uname -m']);
    final output = model.requests.last.last;
    expect(output.callId, 'command-1');
    expect(jsonDecode(output.text)['output'], 'repair output');
    expect(agent.busy, isFalse);
  });

  test('declined commands never execute', () async {
    model = FakeBridgeSetupModel(
        handler: (_, call) async => call == 1
            ? const BridgeAgentMessage('assistant', '', calls: [
                BridgeAgentToolCall(
                    id: 'declined',
                    name: 'run_command',
                    arguments: {'command': 'change-system', 'reason': 'repair'})
              ])
            : const BridgeAgentMessage('assistant', 'No command run'));
    final agent = controller();
    final running = agent.start(setupAgentProvider, 'repair');
    await Future<void>.delayed(Duration.zero);
    agent.approveCommand(false);
    await running;
    expect(host.commands, isEmpty);
    expect(model.requests.last.last.text, contains('declined'));
  });

  test('connecting validates the actual Bridge and keeps its token out of chat',
      () async {
    model = FakeBridgeSetupModel(
        handler: (_, __) async => const BridgeAgentMessage('assistant', '',
                calls: [
                  BridgeAgentToolCall(
                      id: 'connect', name: 'connect_bridge', arguments: {})
                ]));
    final agent = controller();
    await agent.start(setupAgentProvider, 'repair');
    expect(host.connections, 1);
    expect(agent.result, setupAgentResult);
    expect(agent.messages.map((message) => message.text).join(),
        isNot(contains(setupAgentResult.token)));
    expect(model.requests, hasLength(1));
  });

  test('a model claim alone cannot mark installation successful', () async {
    model = FakeBridgeSetupModel(
        handler: (_, __) async =>
            const BridgeAgentMessage('assistant', 'Installation complete'));
    final agent = controller();
    await agent.start(setupAgentProvider, 'repair');
    expect(agent.result, isNull);
    expect(host.connections, 0);
  });

  test('can retry the deterministic installer after fixing the environment',
      () async {
    model = FakeBridgeSetupModel(
        handler: (_, __) async => const BridgeAgentMessage('assistant', '',
                calls: [
                  BridgeAgentToolCall(
                      id: 'retry', name: 'retry_install', arguments: {})
                ]));
    final agent = controller();
    await agent.start(setupAgentProvider, 'repair');
    expect(installer.calls, 1);
    expect(agent.result, setupAgentResult);
  });

  test('a failing action loop stops at the turn limit', () async {
    host.failConnection = true;
    model = FakeBridgeSetupModel(
        handler: (_, call) async => BridgeAgentMessage('assistant', '', calls: [
              BridgeAgentToolCall(
                  id: 'connect-$call', name: 'connect_bridge', arguments: {})
            ]));
    final agent = controller();
    await agent.start(setupAgentProvider, 'repair');
    expect(model.requests, hasLength(12));
    expect(agent.problem, BridgeSetupAgentProblem.turnLimit);
    expect(agent.result, isNull);
  });

  test(
      'authentication errors are recoverable and do not expose provider output',
      () async {
    model = FakeBridgeSetupModel(handler: (_, call) async {
      if (call == 1) throw const BridgeAgentModelException(statusCode: 401);
      return const BridgeAgentMessage('assistant', 'Recovered');
    });
    final agent = controller();
    await agent.start(setupAgentProvider, 'repair');
    expect(agent.problem, BridgeSetupAgentProblem.modelAuthentication);
    await agent.send('Try again');
    expect(agent.problem, isNull);
    expect(agent.messages.last.text, 'Recovered');
  });

  test('closing while approval is pending never executes the command',
      () async {
    model = FakeBridgeSetupModel(
        handler: (_, __) async =>
            const BridgeAgentMessage('assistant', '', calls: [
              BridgeAgentToolCall(
                  id: 'pending',
                  name: 'run_command',
                  arguments: {'command': 'do-not-run', 'reason': 'repair'})
            ]));
    final agent = BridgeSetupAgentController(
        model: model,
        host: host,
        setup: installer,
        clientId: 'desktop',
        failure: LocalBridgeSetupFailure.installFailed);
    final running = agent.start(setupAgentProvider, 'repair');
    await Future<void>.delayed(Duration.zero);
    agent.dispose();
    await running;
    expect(host.commands, isEmpty);
    expect(host.closed, isTrue);
    expect(model.closed, isTrue);
  });
}
