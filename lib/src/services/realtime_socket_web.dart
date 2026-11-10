import 'package:web_socket_channel/html.dart';
import '../settings/app_settings.dart';
import '../relay/relay_api.dart';
import '../relay/relay_settings.dart';
import 'realtime_socket.dart';

Future<BridgeRealtimeSocket> connectRealtimeSocket(Uri uri,
    {Map<String, dynamic>? headers}) async {
  final relay = appSettingsController.settings.relay;
  final List<String> protocols = [];
  if (relay.enabled) {
    final api = RelayApi();
    try {
      protocols
          .add('omni-relay-ticket.${await api.websocketTicket(relay, uri)}');
    } finally {
      api.close();
    }
  } else if (headers?.isNotEmpty == true) {
    throw const RelayException('browser_websocket_requires_relay');
  }
  final channel = HtmlWebSocketChannel.connect(uri, protocols: protocols);
  await channel.ready.timeout(const Duration(seconds: 15));
  return _Socket(channel);
}

class _Socket implements BridgeRealtimeSocket {
  _Socket(this.channel);
  final HtmlWebSocketChannel channel;
  @override
  Stream<dynamic> get messages => channel.stream;
  @override
  void add(dynamic data) => channel.sink.add(data);
  @override
  Future<void> close() async {
    await channel.sink.close();
  }
}
