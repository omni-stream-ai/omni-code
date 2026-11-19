import '../models.dart';
import 'bridge_setup_agent_host.dart';
import 'local_bridge_setup.dart';

BridgeSetupAgentHost createBridgeSetupAgentHost() => _UnsupportedHost();

class _UnsupportedHost implements BridgeSetupAgentHost {
  @override
  bool get isSupported => false;
  @override
  Future<List<ModelProviderConfig>> discoverProviders() async => [];
  @override
  Future<Map<String, dynamic>> diagnostics() async => {};
  @override
  Future<BridgeAgentCommandResult> runCommand(String command) async =>
      throw UnsupportedError('Local commands are unavailable');
  @override
  Future<LocalBridgeSetupResult> connect(String clientId) async =>
      throw UnsupportedError('Local Bridge is unavailable');
  @override
  void close() {}
}
