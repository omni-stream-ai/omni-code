import 'notification_delivery.dart';

class MemoryNotificationDelivery implements NotificationDelivery {
  final Map<String, DateTime> _delivered = {};
  Future<void>? _tail;

  @override
  Future<void> deliver(
      String key, Duration retention, Future<void> Function() show) {
    // Start the queue where delivery is used, rather than in a constructor
    // zone whose microtask scheduler may no longer be running.
    final result = (_tail ?? Future<void>.value()).then((_) async {
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
