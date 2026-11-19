import 'local_bridge_setup_stub.dart'
    if (dart.library.io) 'local_bridge_setup_io.dart' as platform;

enum LocalBridgeSetupStage {
  checking,
  downloading,
  installing,
  configuringStartup,
  starting,
  authorizing,
}

class LocalBridgeSetupProgress {
  const LocalBridgeSetupProgress(this.stage, {this.fraction});

  final LocalBridgeSetupStage stage;
  final double? fraction;
}

class LocalBridgeSetupResult {
  const LocalBridgeSetupResult({required this.url, required this.token});

  final String url;
  final String token;
}

enum LocalBridgeSetupFailure {
  unsupportedPlatform,
  existingBridge,
  incompatibleVersion,
  downloadFailed,
  verificationFailed,
  installFailed,
  startupFailed,
  authorizationFailed,
  busy,
}

class LocalBridgeSetupException implements Exception {
  const LocalBridgeSetupException(this.failure, {this.diagnostic});

  final LocalBridgeSetupFailure failure;
  final String? diagnostic;

  @override
  String toString() => 'Local Bridge setup: ${failure.name}';
}

abstract class LocalBridgeSetupService {
  bool get isSupported;

  Future<LocalBridgeSetupResult> installAndStart({
    required String clientId,
    required void Function(LocalBridgeSetupProgress) onProgress,
  });
}

LocalBridgeSetupService createLocalBridgeSetupService() =>
    platform.createLocalBridgeSetupService();
