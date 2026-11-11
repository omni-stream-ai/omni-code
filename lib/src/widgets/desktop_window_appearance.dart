import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'desktop_window_header.dart';

/// Integrates Linux window controls with the application header.
class DesktopWindowAppearance extends StatefulWidget {
  const DesktopWindowAppearance({required this.child, super.key});

  final Widget child;

  @override
  State<DesktopWindowAppearance> createState() =>
      _DesktopWindowAppearanceState();
}

class _DesktopWindowAppearanceState extends State<DesktopWindowAppearance> {
  static const _channel = MethodChannel('omni_code/window');
  Brightness? _brightness;
  bool _supported = false;
  bool _maximized = false;

  bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    if (_isLinux) {
      _channel.setMethodCallHandler(_handleWindowEvent);
      unawaited(_initializeWindow());
    }
  }

  Future<void> _initializeWindow() async {
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('getState');
      if (!mounted || state == null) return;
      setState(() {
        _supported = state['customHeader'] == true;
        _maximized = state['maximized'] == true;
      });
    } on MissingPluginException {
      // Older runners retain their native titlebar.
    } on PlatformException catch (error) {
      debugPrint('Failed to initialize window header: $error');
    }
  }

  Future<void> _handleWindowEvent(MethodCall call) async {
    if (mounted && call.method == 'stateChanged') {
      setState(() => _maximized = (call.arguments as Map)['maximized'] == true);
    }
  }

  Future<void> _windowAction(String action) async {
    try {
      await _channel.invokeMethod<void>(action);
    } on PlatformException catch (error) {
      debugPrint('Window action $action failed: $error');
    }
  }

  @override
  void dispose() {
    if (_isLinux) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isLinux) return;
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    unawaited(_syncAppearance(brightness));
  }

  Future<void> _syncAppearance(Brightness brightness) async {
    String cssColor(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    try {
      await _channel.invokeMethod<void>('setAppearance', {
        'dark': brightness == Brightness.dark,
        'background': cssColor(AppColors.boardFor(brightness)),
        'foreground': cssColor(AppColors.mutedSoftFor(brightness)),
        'border': cssColor(AppColors.outlineFor(brightness)),
      });
    } on MissingPluginException {
      // Widget previews and older runners may not expose window controls.
    } on PlatformException catch (error) {
      debugPrint('Failed to update window appearance: $error');
    }
  }

  @override
  Widget build(BuildContext context) => !_supported
      ? widget.child
      : Column(children: [
          DesktopWindowHeader(
            maximized: _maximized,
            onDrag: () => unawaited(_windowAction('startDragging')),
            onMinimize: () => unawaited(_windowAction('minimize')),
            onToggleMaximize: () => unawaited(_windowAction('toggleMaximize')),
            onClose: () => unawaited(_windowAction('close')),
          ),
          Expanded(child: DesktopWindowHeaderScope(child: widget.child)),
        ]);
}
