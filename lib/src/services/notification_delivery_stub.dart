import 'notification_delivery.dart';

class MemoryNotificationDelivery implements NotificationDelivery {
  final Map<String, DateTime> _delivered = {};
  Future<void> _tail = Future.value();

  @override
  Future<void> deliver(
      String key, Duration retention, Future<void> Function() show) {
    final result = _tail.then((_) async {
      final now = DateTime.now();
      _delivered.removeWhere((_, expiry) => !expiry.isAfter(now));
      if (_delivered.containsKey(key)) return;
      await show();
      _delivered[key] = now.add(retention);
    });
    _tail = result.catchError((Object _) {});
    return result;
  }
}

NotificationDelivery createDelivery() => MemoryNotificationDelivery();
