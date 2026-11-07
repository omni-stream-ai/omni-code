import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DesktopShortcutAction {
  search,
  newWindow,
  newSession,
  settings,
  home,
  projects,
  toggleNavigation,
  goBack,
}

bool get supportsDesktopShortcuts => switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };

@immutable
class DesktopKeyBinding {
  const DesktopKeyBinding(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  static const modifierKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  ];

  bool get isValid =>
      !modifierKeys.contains(key) &&
      key != LogicalKeyboardKey.escape &&
      key != LogicalKeyboardKey.unidentified &&
      (control ||
          alt ||
          meta ||
          (key.keyId >= LogicalKeyboardKey.f1.keyId &&
              key.keyId <= LogicalKeyboardKey.f24.keyId));

  factory DesktopKeyBinding.fromEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return DesktopKeyBinding(
      event.logicalKey,
      control: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  bool matches(KeyEvent event) => this == DesktopKeyBinding.fromEvent(event);

  List<String> get keyLabels => [
        if (control) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
        if (meta)
          defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Meta',
        switch (key) {
          LogicalKeyboardKey.arrowLeft => '←',
          LogicalKeyboardKey.arrowRight => '→',
          LogicalKeyboardKey.arrowUp => '↑',
          LogicalKeyboardKey.arrowDown => '↓',
          LogicalKeyboardKey.space => 'Space',
          _ => key.keyLabel.length == 1
              ? key.keyLabel.toUpperCase()
              : key.keyLabel,
        },
      ];

  String get label => keyLabels.join('+');

  Map<String, dynamic> toJson() => {
        'key_id': key.keyId,
        'control': control,
        'shift': shift,
        'alt': alt,
        'meta': meta,
      };

  static DesktopKeyBinding? tryParse(dynamic value) {
    if (value is! Map || value['key_id'] is! int) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(value['key_id'] as int);
    if (key == null) return null;
    for (final modifier in ['control', 'shift', 'alt', 'meta']) {
      if (value[modifier] != null && value[modifier] is! bool) return null;
    }
    final binding = DesktopKeyBinding(
      key,
      control: value['control'] == true,
      shift: value['shift'] == true,
      alt: value['alt'] == true,
      meta: value['meta'] == true,
    );
    return binding.isValid ? binding : null;
  }

  @override
  bool operator ==(Object other) =>
      other is DesktopKeyBinding &&
      key == other.key &&
      control == other.control &&
      shift == other.shift &&
      alt == other.alt &&
      meta == other.meta;

  @override
  int get hashCode => Object.hash(key, control, shift, alt, meta);
}

DesktopKeyBinding defaultDesktopShortcut(DesktopShortcutAction action) {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  final (key, shift) = switch (action) {
    DesktopShortcutAction.search => (LogicalKeyboardKey.keyP, false),
    DesktopShortcutAction.newWindow => (LogicalKeyboardKey.keyN, false),
    DesktopShortcutAction.newSession => (LogicalKeyboardKey.keyN, true),
    DesktopShortcutAction.settings => (LogicalKeyboardKey.comma, false),
    DesktopShortcutAction.home => (LogicalKeyboardKey.keyH, true),
    DesktopShortcutAction.projects => (LogicalKeyboardKey.keyP, true),
    DesktopShortcutAction.toggleNavigation => (LogicalKeyboardKey.keyB, false),
    DesktopShortcutAction.goBack => (LogicalKeyboardKey.arrowLeft, false),
  };
  if (action == DesktopShortcutAction.goBack) {
    return DesktopKeyBinding(key, alt: !mac, meta: mac);
  }
  return DesktopKeyBinding(key, control: !mac, meta: mac, shift: shift);
}

/// Missing entries use platform defaults; explicit null disables an action.
DesktopKeyBinding? resolveDesktopShortcut(
  Map<DesktopShortcutAction, DesktopKeyBinding?> overrides,
  DesktopShortcutAction action,
) =>
    overrides.containsKey(action)
        ? overrides[action]
        : defaultDesktopShortcut(action);

Map<DesktopShortcutAction, DesktopKeyBinding?> parseDesktopShortcuts(
    dynamic json) {
  if (json is! Map) return const {};
  final result = <DesktopShortcutAction, DesktopKeyBinding?>{};
  for (final action in DesktopShortcutAction.values) {
    if (!json.containsKey(action.name)) continue;
    final value = json[action.name];
    final binding = DesktopKeyBinding.tryParse(value);
    if (value == null || binding != null) result[action] = binding;
  }
  return Map.unmodifiable(result);
}
