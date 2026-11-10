import 'dart:io';
import 'realtime_socket.dart';

Future<BridgeRealtimeSocket> connectRealtimeSocket(Uri uri,
        {Map<String, dynamic>? headers}) async =>
    _Socket(await WebSocket.connect(uri.toString(), headers: headers));

class _Socket implements BridgeRealtimeSocket {
  _Socket(this.socket);
  final WebSocket socket;
  @override
  Stream<dynamic> get messages => socket;
  @override
  void add(dynamic data) => socket.add(data);
  @override
  Future<void> close() => socket.close();
}
