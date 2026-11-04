// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';
import 'dart:js_interop';

import 'notification_delivery.dart';

@JS('navigator.locks')
external _Locks? get _locks;

extension type _Locks(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(JSString name, JSFunction callback);
}

class WebNotificationDelivery implements NotificationDelivery {
  @override
  Future<void> deliver(
      String key, Duration retention, Future<void> Function() show) async {
    final locks = _locks;
    Future<void> deliverLocked() async {
      const storageKey = 'omni-code-notification-delivery';
      final now = DateTime.now().millisecondsSinceEpoch;
      var entries = <String, dynamic>{};
      try {
        final decoded =
            jsonDecode(html.window.localStorage[storageKey] ?? '{}');
        if (decoded is Map<String, dynamic>) entries = decoded;
      } on FormatException {
        // An invalid cache must not permanently silence notifications.
      }
      entries.removeWhere((_, expiry) => expiry is! int || expiry <= now);
      if (entries.containsKey(key)) return;
      await show();
      entries[key] = now + retention.inMilliseconds;
      html.window.localStorage[storageKey] = jsonEncode(entries);
    }

    if (locks == null) {
      await deliverLocked();
      return;
    }
    await locks
        .request(
          'omni-code-notification-delivery'.toJS,
          ((JSAny? _) => deliverLocked().then<JSAny?>((_) => null).toJS).toJS,
        )
        .toDart;
  }
}

NotificationDelivery createDelivery() => WebNotificationDelivery();
