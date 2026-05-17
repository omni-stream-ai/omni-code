import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../theme/app_theme.dart';
import 'session_call_mode_view.dart';

@Preview(
  name: 'Voice Chat Light',
  group: 'Session',
  size: Size(430, 920),
)
Widget sessionCallModeLightPreview() {
  return _buildPreview(Brightness.light);
}

@Preview(
  name: 'Voice Chat Dark',
  group: 'Session',
  size: Size(430, 920),
)
Widget sessionCallModeDarkPreview() {
  return _buildPreview(Brightness.dark);
}

Widget _buildPreview(Brightness brightness) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: _PreviewCallModeScreen(brightness: brightness),
  );
}

class _PreviewCallModeScreen extends StatefulWidget {
  const _PreviewCallModeScreen({required this.brightness});

  final Brightness brightness;

  @override
  State<_PreviewCallModeScreen> createState() => _PreviewCallModeScreenState();
}

class _PreviewCallModeScreenState extends State<_PreviewCallModeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionCallModeView(
      voiceChatTitle: 'Voice chat',
      statusText: 'Go ahead, I\'m listening',
      bodyText:
          'Hello. I\'m here to help you learn, explore new topics, and tackle tricky questions.',
      realtimeHintLabel: 'Listening now',
      realtimeHintDetail:
          'Start speaking whenever you\'re ready. Live transcription will show up here.',
      bannerText: 'Live transcript will appear here while you speak.',
      subtitlesVisible: true,
      subtitleToggleTooltip: 'Hide subtitles',
      closeTooltip: 'Close',
      orbAnimation: _controller,
      statusIsError: false,
      isListening: true,
      isSpeaking: false,
      isBusy: false,
      isLive: true,
      onBackPressed: () {},
      onSubtitleTogglePressed: () {},
      onPrimaryPressed: () {},
      onClosePressed: () {},
    );
  }
}
