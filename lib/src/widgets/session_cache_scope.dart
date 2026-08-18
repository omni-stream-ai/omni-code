import 'package:flutter/widgets.dart';

class SessionCacheScope extends InheritedNotifier<ValueNotifier<int>> {
  const SessionCacheScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<SessionCacheScope>();
  }
}
