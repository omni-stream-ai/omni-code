import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_back_header.dart';

class SessionCallModeView extends StatelessWidget {
  const SessionCallModeView({
    super.key,
    required this.voiceChatTitle,
    required this.statusText,
    required this.bodyText,
    this.realtimeHintLabel,
    this.realtimeHintDetail,
    required this.subtitlesVisible,
    required this.subtitleToggleTooltip,
    required this.closeTooltip,
    required this.orbAnimation,
    required this.onBackPressed,
    required this.onSubtitleTogglePressed,
    required this.onPrimaryPressed,
    required this.onClosePressed,
    this.bannerText,
    this.statusIsError = false,
    this.isStarting = false,
    this.isListening = false,
    this.isSpeaking = false,
    this.isBusy = false,
    this.isLive = false,
  });

  final String voiceChatTitle;
  final String statusText;
  final String bodyText;
  final String? realtimeHintLabel;
  final String? realtimeHintDetail;
  final String? bannerText;
  final bool subtitlesVisible;
  final String subtitleToggleTooltip;
  final String closeTooltip;
  final Animation<double> orbAnimation;
  final VoidCallback onBackPressed;
  final VoidCallback onSubtitleTogglePressed;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onClosePressed;
  final bool statusIsError;
  final bool isStarting;
  final bool isListening;
  final bool isSpeaking;
  final bool isBusy;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final palette = _CallModePalette.resolve(brightness);

    return Scaffold(
      key: const Key('call-mode-screen'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactHeight = constraints.maxHeight < 700;
            final horizontalPadding = constraints.maxWidth >= 760
                ? AppSpacing.insetWide
                : AppSpacing.screenX;
            final animationSize = math.min(
              constraints.maxWidth - (horizontalPadding * 2),
              compactHeight ? 260.0 : 320.0,
            );

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.contentMaxWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.block,
                    horizontalPadding,
                    AppSpacing.screenBottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppBackHeader(
                        title: voiceChatTitle,
                        onTap: onBackPressed,
                        maxTitleLines: 1,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            vertical: compactHeight
                                ? AppSpacing.block
                                : AppSpacing.shell,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0,
                                constraints.maxHeight -
                                    (compactHeight ? 194.0 : 248.0),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _VoiceAnimation(
                                  animation: orbAnimation,
                                  palette: palette,
                                  isStarting: isStarting,
                                  isListening: isListening,
                                  isSpeaking: isSpeaking,
                                  isBusy: isBusy,
                                  size: animationSize,
                                ),
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.section
                                      : AppSpacing.shell,
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: subtitlesVisible
                                      ? _SubtitlePanel(
                                          bodyText: bodyText,
                                          realtimeHintLabel: realtimeHintLabel,
                                          realtimeHintDetail:
                                              realtimeHintDetail,
                                          bannerText: bannerText,
                                          palette: palette,
                                          isStarting: isStarting,
                                        )
                                      : const SizedBox(
                                          key: ValueKey(
                                            'call-mode-subtitles-hidden',
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _CallControls(
                        palette: palette,
                        subtitlesVisible: subtitlesVisible,
                        subtitleToggleTooltip: subtitleToggleTooltip,
                        closeTooltip: closeTooltip,
                        isStarting: isStarting,
                        isBusy: isBusy,
                        isLive: isLive,
                        onSubtitleTogglePressed: onSubtitleTogglePressed,
                        onPrimaryPressed: onPrimaryPressed,
                        onClosePressed: onClosePressed,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VoiceAnimation extends StatelessWidget {
  const _VoiceAnimation({
    required this.animation,
    required this.palette,
    required this.isStarting,
    required this.isListening,
    required this.isSpeaking,
    required this.isBusy,
    required this.size,
  });

  final Animation<double> animation;
  final _CallModePalette palette;
  final bool isStarting;
  final bool isListening;
  final bool isSpeaking;
  final bool isBusy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final activity = isListening
        ? 1.0
        : isSpeaking
            ? 0.86
            : isBusy || isStarting
                ? 0.58
                : 0.38;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: isStarting
            ? CustomPaint(
                key: const Key('call-mode-orb-static'),
                painter: _VoiceWavePainter(
                  progress: 0,
                  activity: activity,
                  palette: palette,
                ),
              )
            : AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  return CustomPaint(
                    key: const Key('call-mode-orb-gif'),
                    painter: _VoiceWavePainter(
                      progress: animation.value,
                      activity: activity,
                      palette: palette,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SubtitlePanel extends StatelessWidget {
  const _SubtitlePanel({
    required this.bodyText,
    required this.realtimeHintLabel,
    required this.realtimeHintDetail,
    required this.bannerText,
    required this.palette,
    required this.isStarting,
  }) : super(key: const ValueKey('call-mode-subtitles-visible'));

  final String bodyText;
  final String? realtimeHintLabel;
  final String? realtimeHintDetail;
  final String? bannerText;
  final _CallModePalette palette;
  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRealtimeHint = realtimeHintLabel != null &&
        realtimeHintLabel!.trim().isNotEmpty &&
        realtimeHintDetail != null &&
        realtimeHintDetail!.trim().isNotEmpty;
    final hasBanner = bannerText != null && bannerText!.trim().isNotEmpty;

    return Container(
      key: const Key('call-mode-body-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.block),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bodyText,
            key: const Key('call-mode-body-text'),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: palette.text,
              fontWeight: FontWeight.w800,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
          if (hasRealtimeHint) ...[
            const SizedBox(height: AppSpacing.card),
            _RealtimeHint(
              label: realtimeHintLabel!,
              detail: realtimeHintDetail!,
              palette: palette,
              isStarting: isStarting,
            ),
          ],
          if (hasBanner) ...[
            const SizedBox(height: AppSpacing.stack),
            Text(
              bannerText!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RealtimeHint extends StatelessWidget {
  const _RealtimeHint({
    required this.label,
    required this.detail,
    required this.palette,
    required this.isStarting,
  });

  final String label;
  final String detail;
  final _CallModePalette palette;
  final bool isStarting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('call-mode-realtime-hint'),
      width: double.infinity,
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: isStarting ? palette.warningBackground : palette.panelDeep,
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        border: Border.all(
          color: isStarting ? palette.warningBorder : palette.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isStarting)
            SizedBox.square(
              key: const Key('call-mode-realtime-starting-spinner'),
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.warning,
              ),
            )
          else
            Icon(
              Icons.graphic_eq_rounded,
              color: palette.signal,
              size: 18,
            ),
          const SizedBox(width: AppSpacing.compact),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  key: const Key('call-mode-realtime-hint-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  detail,
                  key: const Key('call-mode-realtime-hint-detail'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.palette,
    required this.subtitlesVisible,
    required this.subtitleToggleTooltip,
    required this.closeTooltip,
    required this.isStarting,
    required this.isBusy,
    required this.isLive,
    required this.onSubtitleTogglePressed,
    required this.onPrimaryPressed,
    required this.onClosePressed,
  });

  final _CallModePalette palette;
  final bool subtitlesVisible;
  final String subtitleToggleTooltip;
  final String closeTooltip;
  final bool isStarting;
  final bool isBusy;
  final bool isLive;
  final VoidCallback onSubtitleTogglePressed;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onClosePressed;

  @override
  Widget build(BuildContext context) {
    final micIcon = isBusy
        ? Icons.stop_rounded
        : isStarting
            ? Icons.hourglass_top_rounded
            : isLive
                ? Icons.mic_rounded
                : Icons.mic_off_rounded;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IconControl(
          buttonKey: const Key('call-mode-subtitle-toggle-button'),
          icon: subtitlesVisible
              ? Icons.subtitles_rounded
              : Icons.subtitles_off_rounded,
          tooltip: subtitleToggleTooltip,
          palette: palette,
          isSelected: subtitlesVisible,
          onPressed: onSubtitleTogglePressed,
        ),
        const SizedBox(width: AppSpacing.stack),
        _IconControl(
          buttonKey: const Key('call-mode-primary-button'),
          icon: micIcon,
          tooltip: isBusy ? 'Stop' : 'Microphone',
          palette: palette,
          isPrimary: true,
          isSelected: isLive,
          isWarning: isStarting,
          isDanger: isBusy,
          onPressed: onPrimaryPressed,
        ),
        const SizedBox(width: AppSpacing.stack),
        _IconControl(
          buttonKey: const Key('call-mode-close-button'),
          icon: Icons.call_end_rounded,
          tooltip: closeTooltip,
          palette: palette,
          isDanger: true,
          onPressed: onClosePressed,
        ),
      ],
    );
  }
}

class _IconControl extends StatelessWidget {
  const _IconControl({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onPressed,
    this.isPrimary = false,
    this.isSelected = false,
    this.isWarning = false,
    this.isDanger = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final _CallModePalette palette;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isSelected;
  final bool isWarning;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final size = isPrimary ? 62.0 : 52.0;
    final background = isDanger
        ? palette.errorBackground
        : isWarning
            ? palette.warningBackground
            : isSelected || isPrimary
                ? palette.primary
                : palette.panelDeep;
    final foreground = isDanger
        ? palette.error
        : isWarning
            ? palette.warning
            : isSelected || isPrimary
                ? palette.onPrimary
                : palette.textSoft;
    final border = isDanger
        ? palette.errorBorder
        : isWarning
            ? palette.warningBorder
            : isSelected || isPrimary
                ? palette.primary
                : palette.outlineStrong;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: buttonKey,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
              border: Border.all(color: border),
            ),
            child: Icon(
              icon,
              color: foreground,
              size: isPrimary ? 28 : 23,
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.progress,
    required this.activity,
    required this.palette,
  });

  final double progress;
  final double activity;
  final _CallModePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final shortest = size.shortestSide;
    final time = progress * math.pi * 2;
    final radius = shortest * (0.28 + (0.018 * math.sin(time)));

    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = palette.outlineStrong.withValues(alpha: 0.72);
    canvas.drawCircle(center, shortest * 0.39, outerPaint);

    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = palette.primary.withValues(alpha: 0.10 + (activity * 0.16));
    for (var index = 0; index < 3; index += 1) {
      final phase = (progress + (index * 0.28)) % 1.0;
      final ringRadius = shortest * (0.28 + (phase * 0.20));
      pulsePaint.color = Color.lerp(
        palette.primary,
        palette.signal,
        0.12,
      )!
          .withValues(
        alpha: (1.0 - phase) * 0.16 * activity,
      );
      canvas.drawCircle(center, ringRadius, pulsePaint);
    }

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.panel.withValues(alpha: 0.98),
          Color.lerp(palette.panelDeep, palette.primary, 0.10)!
              .withValues(alpha: 0.96),
          palette.panelDeep.withValues(alpha: 0.98),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, corePaint);

    final coreStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Color.lerp(palette.outlineStrong, palette.primary, 0.26)!
          .withValues(alpha: 0.82);
    canvas.drawCircle(center, radius, coreStrokePaint);

    final barCount = 11;
    final maxBarHeight = shortest * (0.24 + (activity * 0.10));
    final barWidth = math.max(4.0, shortest * 0.018);
    final gap = math.max(5.0, shortest * 0.018);
    final totalWidth = (barCount * barWidth) + ((barCount - 1) * gap);
    final baseLeft = center.dx - (totalWidth / 2);
    final barPaint = Paint()
      ..color = Color.lerp(
        palette.primary,
        palette.signal,
        0.08,
      )!
          .withValues(alpha: 0.96);

    for (var index = 0; index < barCount; index += 1) {
      final distanceFromCenter = (index - ((barCount - 1) / 2)).abs();
      final envelope = 1.0 - (distanceFromCenter / barCount);
      final wave = 0.5 + (0.5 * math.sin(time * 1.6 + (index * 0.84)));
      final height =
          maxBarHeight * (0.22 + (envelope * 0.36) + (wave * activity * 0.42));
      final left = baseLeft + (index * (barWidth + gap));
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          center.dy - (height / 2),
          barWidth,
          height,
        ),
        Radius.circular(barWidth),
      );
      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activity != activity ||
        oldDelegate.palette != palette;
  }
}

class _CallModePalette {
  const _CallModePalette({
    required this.background,
    required this.panel,
    required this.panelAlt,
    required this.panelDeep,
    required this.outline,
    required this.outlineStrong,
    required this.text,
    required this.textSoft,
    required this.muted,
    required this.signal,
    required this.primary,
    required this.onPrimary,
    required this.warning,
    required this.warningBackground,
    required this.warningBorder,
    required this.error,
    required this.errorBackground,
    required this.errorBorder,
  });

  final Color background;
  final Color panel;
  final Color panelAlt;
  final Color panelDeep;
  final Color outline;
  final Color outlineStrong;
  final Color text;
  final Color textSoft;
  final Color muted;
  final Color signal;
  final Color primary;
  final Color onPrimary;
  final Color warning;
  final Color warningBackground;
  final Color warningBorder;
  final Color error;
  final Color errorBackground;
  final Color errorBorder;

  static _CallModePalette resolve(Brightness brightness) {
    return _CallModePalette(
      background: AppColors.screenFor(brightness),
      panel: AppColors.panelFor(brightness),
      panelAlt: AppColors.panelAltFor(brightness),
      panelDeep: AppColors.panelDeepFor(brightness),
      outline: AppColors.outlineFor(brightness),
      outlineStrong: AppColors.outlineStrongFor(brightness),
      text: AppColors.textFor(brightness),
      textSoft: AppColors.textSoftFor(brightness),
      muted: AppColors.mutedSoftFor(brightness),
      signal: AppColors.accentBlueFor(brightness),
      primary: AppColors.primaryFor(brightness),
      onPrimary: AppColors.onPrimaryFor(brightness),
      warning: AppColors.warningTextFor(brightness),
      warningBackground: AppColors.warningSurfaceFor(brightness),
      warningBorder: AppColors.warningBorderFor(brightness),
      error: AppColors.errorFor(brightness),
      errorBackground: AppColors.errorBgFor(brightness),
      errorBorder: AppColors.errorBorderFor(brightness),
    );
  }
}
