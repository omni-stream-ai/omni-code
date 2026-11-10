abstract class BridgeRealtimeSocket {
  Stream<dynamic> get messages;
  void add(dynamic data);
  Future<void> close();
}
