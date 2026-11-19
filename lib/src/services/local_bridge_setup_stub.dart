import 'local_bridge_setup.dart';

LocalBridgeSetupService createLocalBridgeSetupService() =>
    _UnsupportedLocalBridgeSetup();

class _UnsupportedLocalBridgeSetup implements LocalBridgeSetupService {
  @override
  bool get isSupported => false;

  @override
  Future<LocalBridgeSetupResult> installAndStart({
    required String clientId,
    required void Function(LocalBridgeSetupProgress) onProgress,
  }) async {
    throw const LocalBridgeSetupException(
      LocalBridgeSetupFailure.unsupportedPlatform,
    );
  }
}
