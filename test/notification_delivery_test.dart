import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/services/notification_delivery_io.dart';
import 'package:omni_code/src/services/notification_delivery_stub.dart';

void main() {
  test('memory delivery works after its constructor scheduler stops', () async {
    final deferred = <void Function()>[];
    final delivery = runZoned(
      MemoryNotificationDelivery.new,
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, callback) =>
            deferred.add(callback),
      ),
    );
    var deliveries = 0;
    try {
      await delivery.deliver('approval', const Duration(days: 1), () async {
        deliveries += 1;
      }).timeout(const Duration(seconds: 1));
      expect(deliveries, 1);
    } finally {
      for (final callback in deferred) {
        callback();
      }
    }
  });

  final sharedDirectory =
      Platform.environment['TEST_NOTIFICATION_DELIVERY_DIRECTORY'];
  test('independent process notification worker', () async {
    final shared = Directory(sharedDirectory!);
    final delivery = FileNotificationDelivery(directory: () async => shared);
    await delivery.deliver('shared-approval', const Duration(days: 1),
        () async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await File('${shared.path}/deliveries')
          .writeAsString('delivered\n', mode: FileMode.append, flush: true);
    });
  }, skip: sharedDirectory == null);

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('notification-delivery-');
  });
  tearDown(() => directory.delete(recursive: true));

  FileNotificationDelivery client() =>
      FileNotificationDelivery(directory: () async => directory);

  test('concurrent clients deliver one notification and persist the result',
      () async {
    var deliveries = 0;
    Future<void> show() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      deliveries++;
    }

    await Future.wait([
      client().deliver('approval-1', const Duration(days: 1), show),
      client().deliver('approval-1', const Duration(days: 1), show),
    ]);
    await client().deliver('approval-1', const Duration(days: 1), show);
    expect(deliveries, 1);
    await client().deliver('approval-2', const Duration(days: 1), show);
    expect(deliveries, 2);
  });

  test('failed delivery can be retried by another client', () async {
    await expectLater(
        client().deliver('reply', const Duration(seconds: 10),
            () async => throw StateError('platform unavailable')),
        throwsStateError);
    var delivered = false;
    await client().deliver('reply', const Duration(seconds: 10), () async {
      delivered = true;
    });
    expect(delivered, isTrue);
  });

  test('an expired delivery does not suppress a later notification', () async {
    var deliveries = 0;
    Future<void> show() async {
      deliveries++;
    }

    await client().deliver('reply', Duration.zero, show);
    await client().deliver('reply', const Duration(seconds: 10), show);
    expect(deliveries, 2);
  });
}
