import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/services/bridge_setup_agent_host.dart';
import 'package:omni_code/src/services/bridge_setup_agent_model.dart';
import 'package:omni_code/src/services/local_bridge_setup.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';

const setupAgentProvider = ModelProviderConfig(
    id: 'assistant-model',
    name: 'Local assistant',
    baseUrl: 'https://model.example/v1',
    apiKey: 'private-model-credential',
    model: 'test-model');
const setupAgentResult = LocalBridgeSetupResult(
    url: 'http://127.0.0.1:8787', token: 'private-bridge-token');

class FakeBridgeSetupModel implements BridgeSetupAgentModel {
  FakeBridgeSetupModel({this.handler});
  final Future<BridgeAgentMessage> Function(List<BridgeAgentMessage>, int)?
      handler;
  final requests = <List<BridgeAgentMessage>>[];
  bool closed = false;
  @override
  Future<BridgeAgentMessage> next(
      ModelProviderConfig provider, List<BridgeAgentMessage> messages) {
    requests.add(List.of(messages));
    return handler?.call(messages, requests.length) ??
        Future.value(
            const BridgeAgentMessage('assistant', 'Agent diagnosis ready'));
  }

  @override
  void close() => closed = true;
}

class FakeBridgeSetupHost implements BridgeSetupAgentHost {
  List<ModelProviderConfig> providers = [];
  Map<String, dynamic> diagnosticData = {'platform': 'test'};
  final commands = <String>[];
  int connections = 0, diagnoses = 0;
  bool closed = false, failConnection = false;
  @override
  bool get isSupported => true;
  @override
  Future<List<ModelProviderConfig>> discoverProviders() async => providers;
  @override
  Future<Map<String, dynamic>> diagnostics() async {
    diagnoses++;
    return diagnosticData;
  }

  @override
  Future<BridgeAgentCommandResult> runCommand(String command) async {
    commands.add(command);
    return const BridgeAgentCommandResult(exitCode: 0, output: 'repair output');
  }

  @override
  Future<LocalBridgeSetupResult> connect(String clientId) async {
    connections++;
    if (failConnection) {
      throw const LocalBridgeSetupException(
          LocalBridgeSetupFailure.startupFailed);
    }
    return setupAgentResult;
  }

  @override
  void close() => closed = true;
}

class FakeBridgeSetupInstaller implements LocalBridgeSetupService {
  int calls = 0;
  @override
  bool get isSupported => true;
  @override
  Future<LocalBridgeSetupResult> installAndStart(
      {required String clientId,
      required void Function(LocalBridgeSetupProgress) onProgress}) async {
    calls++;
    return setupAgentResult;
  }
}

class BridgeAgentMemoryStore implements AppSettingsStore {
  bool fail = false;
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Storage unavailable');
    this.value = value;
  }
}
