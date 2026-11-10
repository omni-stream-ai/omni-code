import 'relay_settings.dart';

class RelayResourceGateway {
  static Future<RelayResourceGateway> open(
          RelaySettings session, String prefix) async =>
      throw UnsupportedError(
          'This browser resource requires the native Omni Code app');
  Uri urlFor(String path) =>
      throw UnsupportedError('Native resource gateway unavailable');
  Future<void> close() async {}
}
