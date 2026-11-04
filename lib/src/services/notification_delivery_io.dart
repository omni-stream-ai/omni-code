import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'notification_delivery.dart';

class FileNotificationDelivery implements NotificationDelivery {
  FileNotificationDelivery({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  // File locks coordinate processes; this queue also coordinates callers in
  // one process, including separate NotificationService instances.
  static Future<void> _tail = Future.value();

  @override
  Future<void> deliver(
      String key, Duration retention, Future<void> Function() show) {
    final result = _tail.then((_) => _deliver(key, retention, show));
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _deliver(
      String key, Duration retention, Future<void> Function() show) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final lock = await File('${directory.path}/notification-delivery.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      final file = File('${directory.path}/notification-delivery.json');
      var entries = <String, dynamic>{};
      if (await file.exists()) {
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map<String, dynamic>) entries = decoded;
        } on FormatException {
          // A damaged cache must not permanently silence notifications.
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      entries.removeWhere((_, expiry) => expiry is! int || expiry <= now);
      if (entries.containsKey(key)) return;
      await show();
      entries[key] = now + retention.inMilliseconds;
      await file.writeAsString(jsonEncode(entries), flush: true);
    } finally {
      await lock.close();
    }
  }
}

NotificationDelivery createDelivery() => FileNotificationDelivery();
