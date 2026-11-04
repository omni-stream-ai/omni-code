import 'notification_delivery_stub.dart'
    if (dart.library.io) 'notification_delivery_io.dart'
    if (dart.library.html) 'notification_delivery_web.dart' as platform;

abstract class NotificationDelivery {
  Future<void> deliver(
    String key,
    Duration retention,
    Future<void> Function() show,
  );
}

NotificationDelivery createNotificationDelivery() => platform.createDelivery();
