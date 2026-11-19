import '../models.dart';
import 'local_bridge_setup.dart';
import 'bridge_setup_agent_host_stub.dart'
    if (dart.library.io) 'bridge_setup_agent_host_io.dart' as platform;

class BridgeAgentCommandResult {
  const BridgeAgentCommandResult(
      {required this.exitCode, required this.output});
  final int exitCode;
  final String output;
}

abstract class BridgeSetupAgentHost {
  bool get isSupported;
  Future<List<ModelProviderConfig>> discoverProviders();
  Future<Map<String, dynamic>> diagnostics();
  Future<BridgeAgentCommandResult> runCommand(String command);
  Future<LocalBridgeSetupResult> connect(String clientId);
  void close();
}

BridgeSetupAgentHost createBridgeSetupAgentHost() =>
    platform.createBridgeSetupAgentHost();
