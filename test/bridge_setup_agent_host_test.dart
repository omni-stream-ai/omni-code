import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/bridge_setup_agent_host_io.dart';

import 'support/bridge_setup_agent_fakes.dart';

void main() {
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('bridge-agent-host-test-'));
  tearDown(() async => root.delete(recursive: true));

  test('discovers existing model configuration without a running Bridge',
      () async {
    final settings = File('${root.path}/.omni-code/settings.json');
    await settings.parent.create();
    await settings.writeAsString(jsonEncode({
      'model_providers': [setupAgentProvider.toJson()]
    }));
    final host = NativeBridgeSetupAgentHost(
        environment: {'HOME': root.path, 'USERPROFILE': root.path});
    final providers = await host.discoverProviders();
    expect(providers.single.model, setupAgentProvider.model);
    expect(providers.single.apiKey, setupAgentProvider.apiKey);
    host.close();
  });

  test('malformed model files do not prevent configuring a new model',
      () async {
    final settings = File('${root.path}/.omni-code/settings.json');
    await settings.parent.create();
    await settings.writeAsString('invalid json');
    final host = NativeBridgeSetupAgentHost(
        environment: {'HOME': root.path, 'USERPROFILE': root.path});
    expect(await host.discoverProviders(), isEmpty);
    host.close();
  });

  test('captures output and exit status from a real local command', () async {
    final host = NativeBridgeSetupAgentHost(environment: {
      'HOME': root.path,
      'PATH': Platform.environment['PATH']!
    });
    final result = await host.runCommand("printf 'diagnostic output'; exit 7");
    expect(result.exitCode, 7);
    expect(result.output, 'diagnostic output');
    host.close();
  }, skip: Platform.isWindows);

  test('stops a timed-out command and can run the next one', () async {
    final host = NativeBridgeSetupAgentHost(
        environment: {'HOME': root.path, 'PATH': Platform.environment['PATH']!},
        commandTimeout: const Duration(milliseconds: 50));
    final result = await host.runCommand('exec sleep 5');
    expect(result.exitCode, -1);
    expect(result.output, contains('timed out'));
    expect((await host.runCommand("printf 'retry' ")).output, 'retry');
    host.close();
  }, skip: Platform.isWindows);
}
