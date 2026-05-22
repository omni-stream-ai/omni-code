import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class SessionCallModeView extends StatelessWidget {
  const SessionCallModeView({
    super.key,
    required this.voiceChatTitle,
    required this.statusText,
    required this.bodyText,
    this.bodyTextMuted = false,
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
  final bool bodyTextMuted;
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
      body: Stack(
        children: [
          Positioned.fill(child: _CallModeBackdrop(palette: palette)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compactHeight = constraints.maxHeight < 720;
                final compactWidth = constraints.maxWidth < 390;
                final horizontalPadding = constraints.maxWidth >= 760
                    ? AppSpacing.insetWide
                    : AppSpacing.screenX;
                final maxContentWidth =
                    constraints.maxWidth >= 760 ? 620.0 : 520.0;
                final animationSize = math.min(
                  constraints.maxWidth - (horizontalPadding * 2),
                  compactHeight ? 252.0 : 342.0,
                );

                return SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxContentWidth,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
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
                                _CallModeHeader(
                                  title: voiceChatTitle,
                                  palette: palette,
                                  isLive: isLive,
                                  onBackPressed: onBackPressed,
                                ),
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.section
                                      : AppSpacing.shell,
                                ),
                                _CallModeStatus(
                                  palette: palette,
                                  statusText: statusText,
                                  statusIsError: statusIsError,
                                  compact: compactWidth,
                                ),
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.block
                                      : AppSpacing.section,
                                ),
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
                                          bodyTextMuted: bodyTextMuted,
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
                                const Spacer(),
                                SizedBox(
                                  height: compactHeight
                                      ? AppSpacing.block
                                      : AppSpacing.shell,
                                ),
                                _CallControls(
                                  palette: palette,
                                  subtitlesVisible: subtitlesVisible,
                                  subtitleToggleTooltip: subtitleToggleTooltip,
                                  closeTooltip: closeTooltip,
                                  isStarting: isStarting,
                                  isBusy: isBusy,
                                  isLive: isLive,
                                  onSubtitleTogglePressed:
                                      onSubtitleTogglePressed,
                                  onPrimaryPressed: onPrimaryPressed,
                                  onClosePressed: onClosePressed,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CallModeBackdrop extends StatelessWidget {
  const _CallModeBackdrop({required this.palette});

  final _CallModePalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CallModeBackdropPainter(palette: palette),
    );
  }
}

class _CallModeHeader extends StatelessWidget {
  const _CallModeHeader({
    required this.title,
    required this.palette,
    required this.isLive,
    required this.onBackPressed,
  });

  final String title;
  final _CallModePalette palette;
  final bool isLive;
  final VoidCallback onBackPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.headerSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
        border: Border.all(color: palette.outline),
        boxShadow: palette.panelShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.compact,
          vertical: AppSpacing.compact,
        ),
        child: Row(
          children: [
            Tooltip(
              message: MaterialLocalizations.of(context).backButtonTooltip,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onBackPressed,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.panelDeep,
                      border: Border.all(color: palette.outlineStrong),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: palette.text,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.stack),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            _LivePill(palette: palette, isLive: isLive),
          ],
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.palette, required this.isLive});

  final _CallModePalette palette;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isLive ? 1 : 0.72,
      duration: const Duration(milliseconds: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.tileX,
          vertical: AppSpacing.controlTight,
        ),
        decoration: BoxDecoration(
          color: isLive ? palette.liveSurface : palette.panelDeep,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: isLive ? palette.liveBorder : palette.outlineStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isLive ? palette.liveText : palette.muted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.compact),
            Text(
              isLive ? 'LIVE' : 'IDLE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isLive ? palette.liveText : palette.muted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallModeStatus extends StatelessWidget {
  const _CallModeStatus({
    required this.palette,
    required this.statusText,
    required this.statusIsError,
    required this.compact,
  });

  final _CallModePalette palette;
  final String statusText;
  final bool statusIsError;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = statusIsError ? palette.error : palette.text;

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.headlineMedium)
                ?.copyWith(
              color: titleColor,
              fontWeight: FontWeight.w900,
              height: 1.08,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: AppSpacing.compact),
          Text(
            statusIsError
                ? 'Check microphone and speech service, then try again.'
                : 'Interrupt anytime. Context stays attached to this session.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.muted,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
        ],
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
    required this.bodyTextMuted,
    required this.realtimeHintLabel,
    required this.realtimeHintDetail,
    required this.bannerText,
    required this.palette,
    required this.isStarting,
  }) : super(key: const ValueKey('call-mode-subtitles-visible'));

  final String bodyText;
  final bool bodyTextMuted;
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
      padding: const EdgeInsets.all(AppSpacing.section),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.panelTop, palette.panelBottom],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusScreen),
        border: Border.all(
          color: bodyTextMuted ? palette.outlineStrong : palette.outline,
        ),
        boxShadow: palette.panelShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRealtimeHint) ...[
            _RealtimeBadge(palette: palette),
            const SizedBox(height: AppSpacing.block),
          ],
          Text(
            bodyText,
            key: const Key('call-mode-body-text'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: bodyTextMuted
                  ? palette.text.withValues(alpha: 0.42)
                  : palette.text,
              fontWeight: bodyTextMuted ? FontWeight.w600 : FontWeight.w900,
              height: 1.34,
              letterSpacing: 0,
            ),
          ),
          if (hasRealtimeHint) ...[
            const SizedBox(height: AppSpacing.section),
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

class _RealtimeBadge extends StatelessWidget {
  const _RealtimeBadge({required this.palette});

  final _CallModePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.tileX,
        vertical: AppSpacing.controlTight,
      ),
      decoration: BoxDecoration(
        color: palette.liveSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: palette.liveBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: palette.liveText,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.compact),
          Text(
            'REALTIME',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.liveText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
          ),
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
      padding: const EdgeInsets.all(AppSpacing.block),
      decoration: BoxDecoration(
        color: isStarting ? palette.warningBackground : palette.panelDeep,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
        border: Border.all(
          color: isStarting ? palette.warningBorder : palette.outline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            SizedBox(
              width: 154,
              height: 52,
              child: CustomPaint(
                painter: _MiniWavePainter(palette: palette),
              ),
            ),
          const SizedBox(width: AppSpacing.block),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.controlTop, palette.controlBottom],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusScreen),
        border: Border.all(color: palette.outline),
        boxShadow: palette.panelShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.section,
          vertical: AppSpacing.block,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _IconControl(
              buttonKey: const Key('call-mode-subtitle-toggle-button'),
              icon: subtitlesVisible
                  ? Icons.subtitles_rounded
                  : Icons.subtitles_off_rounded,
              label: 'Subtitles',
              tooltip: subtitleToggleTooltip,
              palette: palette,
              isSelected: subtitlesVisible,
              onPressed: onSubtitleTogglePressed,
            ),
            _IconControl(
              buttonKey: const Key('call-mode-primary-button'),
              icon: micIcon,
              label: isBusy ? 'Stop' : 'Hold',
              tooltip: isBusy ? 'Stop' : 'Microphone',
              palette: palette,
              isPrimary: true,
              isSelected: isLive,
              isWarning: isStarting,
              isDanger: isBusy,
              onPressed: onPrimaryPressed,
            ),
            _IconControl(
              buttonKey: const Key('call-mode-close-button'),
              icon: Icons.call_end_rounded,
              label: 'End',
              tooltip: closeTooltip,
              palette: palette,
              isDanger: true,
              onPressed: onClosePressed,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconControl extends StatelessWidget {
  const _IconControl({
    required this.buttonKey,
    required this.icon,
    required this.label,
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
  final String label;
  final String tooltip;
  final _CallModePalette palette;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isSelected;
  final bool isWarning;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = isPrimary ? 74.0 : 58.0;
    final radius = isPrimary ? AppSpacing.radiusScreen : AppSpacing.radiusHero;
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
      child: SizedBox(
        width: isPrimary ? 108 : 82,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: buttonKey,
                onTap: onPressed,
                borderRadius: BorderRadius.circular(radius),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: border),
                  ),
                  child: Icon(
                    icon,
                    color: foreground,
                    size: isPrimary ? 32 : 24,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.compact),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
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
    final coreRadius = shortest * (0.30 + (0.018 * math.sin(time)));

    final shellPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.primary.withValues(alpha: palette.isDark ? 0.18 : 0.24),
          palette.signal.withValues(alpha: palette.isDark ? 0.09 : 0.16),
          palette.accent.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.56, 1.0],
      ).createShader(
        Rect.fromCircle(center: center, radius: shortest * 0.48),
      );
    canvas.drawCircle(center, shortest * 0.48, shellPaint);

    final platePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = palette.orbPlate;
    canvas.drawCircle(center, shortest * 0.39, platePaint);

    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = palette.outlineStrong.withValues(alpha: 0.58);
    canvas.drawCircle(center, shortest * 0.39, outerPaint);

    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
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
          palette.orbHighlight,
          palette.orbMid,
          palette.orbEdge,
        ],
        stops: const [0.0, 0.22, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius));
    canvas.drawCircle(center, coreRadius, corePaint);

    final coreStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Color.lerp(palette.primary, palette.outlineStrong, 0.18)!
          .withValues(alpha: 0.70);
    canvas.drawCircle(center, coreRadius, coreStrokePaint);

    final barCount = 7;
    final maxBarHeight = shortest * (0.24 + (activity * 0.10));
    final barWidth = math.max(5.0, shortest * 0.025);
    final gap = math.max(8.0, shortest * 0.028);
    final totalWidth = (barCount * barWidth) + ((barCount - 1) * gap);
    final baseLeft = center.dx - (totalWidth / 2);
    final barPaint = Paint()..color = palette.primary.withValues(alpha: 0.96);

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
      barPaint.color = Color.lerp(
        index.isEven ? palette.primary : palette.signal,
        palette.accent,
        palette.isDark ? 0.04 : 0.18,
      )!
          .withValues(alpha: 0.96);
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

class _MiniWavePainter extends CustomPainter {
  const _MiniWavePainter({required this.palette});

  final _CallModePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..color = palette.signal;
    final path = Path();
    final midY = size.height / 2;
    final step = size.width / 6;

    path.moveTo(0, midY);
    for (var index = 0; index < 6; index += 1) {
      final x1 = (index * step) + (step / 2);
      final x2 = (index + 1) * step;
      final controlY = index.isEven ? 6.0 : size.height - 6.0;
      path.quadraticBezierTo(x1, controlY, x2, midY);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniWavePainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}

class _CallModeBackdropPainter extends CustomPainter {
  const _CallModeBackdropPainter({required this.palette});

  final _CallModePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = palette.background);

    final topGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.primary.withValues(alpha: palette.isDark ? 0.22 : 0.32),
          palette.signal.withValues(alpha: palette.isDark ? 0.13 : 0.20),
          palette.background.withValues(alpha: 0),
        ],
        stops: const [0, 0.48, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.72, size.height * 0.12),
          radius: size.shortestSide * 0.78,
        ),
      );
    canvas.drawRect(rect, topGlow);

    final bottomGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.accent.withValues(alpha: palette.isDark ? 0.18 : 0.14),
          palette.signal.withValues(alpha: palette.isDark ? 0.10 : 0.12),
          palette.background.withValues(alpha: 0),
        ],
        stops: const [0, 0.52, 1],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.12, size.height * 0.74),
          radius: size.shortestSide * 0.72,
        ),
      );
    canvas.drawRect(rect, bottomGlow);

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.outline.withValues(alpha: palette.isDark ? 0.42 : 0.38);

    for (var line = 0; line < 3; line += 1) {
      final path = Path();
      final baseY = size.height * (0.17 + (line * 0.035));
      path.moveTo(-size.width * 0.08, baseY);
      path.cubicTo(
        size.width * 0.16,
        baseY - 46,
        size.width * 0.30,
        baseY - 18,
        size.width * 0.45,
        baseY + 38,
      );
      path.cubicTo(
        size.width * 0.62,
        baseY + 104,
        size.width * 0.78,
        baseY + 70,
        size.width * 1.08,
        baseY - 18,
      );
      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CallModeBackdropPainter oldDelegate) {
    return oldDelegate.palette != palette;
  }
}

class _CallModePalette {
  const _CallModePalette({
    required this.isDark,
    required this.background,
    required this.headerSurface,
    required this.panel,
    required this.panelTop,
    required this.panelBottom,
    required this.panelAlt,
    required this.panelDeep,
    required this.controlTop,
    required this.controlBottom,
    required this.outline,
    required this.outlineStrong,
    required this.text,
    required this.textSoft,
    required this.muted,
    required this.signal,
    required this.accent,
    required this.primary,
    required this.onPrimary,
    required this.liveSurface,
    required this.liveBorder,
    required this.liveText,
    required this.orbPlate,
    required this.orbHighlight,
    required this.orbMid,
    required this.orbEdge,
    required this.warning,
    required this.warningBackground,
    required this.warningBorder,
    required this.error,
    required this.errorBackground,
    required this.errorBorder,
    required this.panelShadow,
  });

  final bool isDark;
  final Color background;
  final Color headerSurface;
  final Color panel;
  final Color panelTop;
  final Color panelBottom;
  final Color panelAlt;
  final Color panelDeep;
  final Color controlTop;
  final Color controlBottom;
  final Color outline;
  final Color outlineStrong;
  final Color text;
  final Color textSoft;
  final Color muted;
  final Color signal;
  final Color accent;
  final Color primary;
  final Color onPrimary;
  final Color liveSurface;
  final Color liveBorder;
  final Color liveText;
  final Color orbPlate;
  final Color orbHighlight;
  final Color orbMid;
  final Color orbEdge;
  final Color warning;
  final Color warningBackground;
  final Color warningBorder;
  final Color error;
  final Color errorBackground;
  final Color errorBorder;
  final List<BoxShadow> panelShadow;

  static _CallModePalette resolve(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return _CallModePalette(
      isDark: isDark,
      background: AppColors.screenFor(brightness),
      headerSurface: AppColors.callModeHeaderSurfaceFor(brightness),
      panel: AppColors.panelFor(brightness),
      panelTop: AppColors.callModePanelTopFor(brightness),
      panelBottom: AppColors.callModePanelBottomFor(brightness),
      panelAlt: AppColors.panelAltFor(brightness),
      panelDeep: AppColors.panelDeepFor(brightness),
      controlTop: AppColors.callModeControlTopFor(brightness),
      controlBottom: AppColors.callModeControlBottomFor(brightness),
      outline: AppColors.outlineFor(brightness),
      outlineStrong: AppColors.outlineStrongFor(brightness),
      text: AppColors.textFor(brightness),
      textSoft: AppColors.textSoftFor(brightness),
      muted: AppColors.mutedSoftFor(brightness),
      signal: AppColors.accentBlueFor(brightness),
      accent: AppColors.accentPurpleFor(brightness),
      primary: AppColors.primaryFor(brightness),
      onPrimary: AppColors.onPrimaryFor(brightness),
      liveSurface: AppColors.callModeLiveSurfaceFor(brightness),
      liveBorder: AppColors.callModeLiveBorderFor(brightness),
      liveText: AppColors.callModeLiveTextFor(brightness),
      orbPlate: isDark
          ? AppColors.darkPanelDeep.withValues(alpha: 0.45)
          : Colors.white.withValues(alpha: 0.52),
      orbHighlight: isDark ? const Color(0xFFF2FFE6) : Colors.white,
      orbMid: isDark ? const Color(0xFFB9FF43) : const Color(0xFFDFFF8B),
      orbEdge: isDark ? const Color(0xFF111B22) : const Color(0xFFEEF5F9),
      warning: AppColors.warningTextFor(brightness),
      warningBackground: AppColors.warningSurfaceFor(brightness),
      warningBorder: AppColors.warningBorderFor(brightness),
      error: AppColors.errorFor(brightness),
      errorBackground: AppColors.errorBgFor(brightness),
      errorBorder: AppColors.errorBorderFor(brightness),
      panelShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.34)
              : const Color(0xFF5B6876).withValues(alpha: 0.16),
          blurRadius: 36,
          offset: const Offset(0, 22),
        ),
      ],
    );
  }
}
