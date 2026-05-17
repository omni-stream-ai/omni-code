import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

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
  final bool isListening;
  final bool isSpeaking;
  final bool isBusy;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final palette = _CallModePalette.resolve(Brightness.dark);

    return Scaffold(
      key: const Key('call-mode-screen'),
      backgroundColor: palette.backgroundBase,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.backgroundTop,
              palette.backgroundMid,
              palette.backgroundBase,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -104,
              left: -58,
              child: _GlowBlob(
                width: 248,
                height: 248,
                colors: palette.topGlow,
              ),
            ),
            Positioned(
              top: 92,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Container(
                  height: 320,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.08),
                      radius: 0.92,
                      colors: [
                        palette.signal.withValues(alpha: 0.10),
                        palette.haloBlue.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 138,
              right: -88,
              child: _GlowBlob(
                width: 252,
                height: 272,
                colors: palette.sideGlow,
              ),
            ),
            Positioned(
              bottom: -52,
              left: 20,
              child: _GlowBlob(
                width: 316,
                height: 204,
                colors: palette.bottomGlow,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.16),
                      ],
                      stops: const [0.0, 0.62, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactHeight = constraints.maxHeight < 760;
                  final compactWidth = constraints.maxWidth < 380;
                  final veryCompactHeight = constraints.maxHeight < 620;
                  final horizontalPadding = constraints.maxWidth >= 760
                      ? AppSpacing.shell
                      : AppSpacing.block;
                  final orbSize = compactHeight ? 286.0 : 372.0;
                  final bodyMaxWidth =
                      compactWidth ? constraints.maxWidth : 384.0;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          AppSpacing.compact,
                          horizontalPadding,
                          veryCompactHeight
                              ? AppSpacing.stack
                              : AppSpacing.block,
                        ),
                        child: Column(
                          children: [
                            _TopBar(
                              title: voiceChatTitle,
                              palette: palette,
                              isLive: isLive,
                              onBackPressed: onBackPressed,
                            ),
                            SizedBox(
                              height: compactHeight ? AppSpacing.block : 36.0,
                            ),
                            _StatusChip(
                              text: statusText,
                              isError: statusIsError,
                              palette: palette,
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, innerConstraints) {
                                  final isVeryShort =
                                      innerConstraints.maxHeight < 380;
                                  final isShort =
                                      innerConstraints.maxHeight < 460;
                                  final resolvedOrbSize = math.min(
                                    orbSize,
                                    isVeryShort
                                        ? 214.0
                                        : isShort
                                            ? 258.0
                                            : orbSize,
                                  );
                                  final topGap = isVeryShort
                                      ? AppSpacing.compact
                                      : compactHeight
                                          ? AppSpacing.stackTight
                                          : AppSpacing.card;
                                  final bottomGap = isVeryShort
                                      ? AppSpacing.stackTight
                                      : compactHeight
                                          ? AppSpacing.block
                                          : AppSpacing.section;
                                  final subtitleGap = subtitlesVisible
                                      ? bottomGap
                                      : math.max(
                                          AppSpacing.section,
                                          bottomGap * 0.46,
                                        );

                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.stackTight,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: math.max(
                                          0,
                                          innerConstraints.maxHeight -
                                              (AppSpacing.stackTight * 2),
                                        ),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(height: topGap),
                                            _CallModeOrb(
                                              animation: orbAnimation,
                                              palette: palette,
                                              isListening: isListening,
                                              isSpeaking: isSpeaking,
                                              isBusy: isBusy,
                                              size: resolvedOrbSize,
                                            ),
                                            SizedBox(height: subtitleGap),
                                            AnimatedSwitcher(
                                              duration: const Duration(
                                                milliseconds: 220,
                                              ),
                                              switchInCurve:
                                                  Curves.easeOutCubic,
                                              switchOutCurve:
                                                  Curves.easeInCubic,
                                              transitionBuilder:
                                                  (child, animation) {
                                                return FadeTransition(
                                                  opacity: animation,
                                                  child: SizeTransition(
                                                    sizeFactor: animation,
                                                    axis: Axis.vertical,
                                                    axisAlignment: -1,
                                                    child: child,
                                                  ),
                                                );
                                              },
                                              child: subtitlesVisible
                                                  ? ConstrainedBox(
                                                      key: const ValueKey(
                                                        'call-mode-subtitles-visible',
                                                      ),
                                                      constraints:
                                                          BoxConstraints(
                                                        maxWidth: bodyMaxWidth,
                                                      ),
                                                      child: _TranscriptCard(
                                                        bodyText: bodyText,
                                                        realtimeHintLabel:
                                                            realtimeHintLabel,
                                                        realtimeHintDetail:
                                                            realtimeHintDetail,
                                                        bannerText: bannerText,
                                                        palette: palette,
                                                      ),
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
                                  );
                                },
                              ),
                            ),
                            SizedBox(
                              height: veryCompactHeight
                                  ? AppSpacing.stack
                                  : compactHeight
                                      ? AppSpacing.block
                                      : 22.0,
                            ),
                            _ControlDock(
                              palette: palette,
                              subtitlesVisible: subtitlesVisible,
                              subtitleToggleTooltip: subtitleToggleTooltip,
                              closeTooltip: closeTooltip,
                              onSubtitleTogglePressed: onSubtitleTogglePressed,
                              onPrimaryPressed: onPrimaryPressed,
                              onClosePressed: onClosePressed,
                              isBusy: isBusy,
                              isLive: isLive,
                              compact: veryCompactHeight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
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

    return Row(
      children: [
        _GlassCircleButton(
          buttonKey: const Key('call-mode-back-button'),
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          palette: palette,
          diameter: 46,
          onPressed: onBackPressed,
        ),
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: Text(
              title,
              key: const Key('call-mode-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: palette.primaryText,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.card,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            color: palette.buttonBackground,
            border: Border.all(color: palette.buttonBorder),
            boxShadow: [
              BoxShadow(
                color: palette.buttonShadow,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLive ? palette.liveGreen : palette.mutedText,
                  boxShadow: [
                    BoxShadow(
                      color: (isLive ? palette.liveGreen : palette.mutedText)
                          .withValues(alpha: 0.42),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Text(
                'LIVE',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isLive ? palette.liveGreen : palette.mutedText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusWaveIcon extends StatelessWidget {
  const _StatusWaveIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [8.0, 16.0, 22.0, 14.0].map((height) {
          return Container(
            width: 3,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              color: color,
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.text,
    required this.isError,
    required this.palette,
  });

  final String text;
  final bool isError;
  final _CallModePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isError ? palette.error : palette.signal;
    final background = isError
        ? palette.error.withValues(alpha: 0.14)
        : accent.withValues(alpha: 0.12);

    return Container(
      key: const Key('call-mode-status-chip'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.card + 2,
        vertical: AppSpacing.compact,
      ),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: accent.withValues(alpha: isError ? 0.32 : 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusWaveIcon(color: accent),
          const SizedBox(width: AppSpacing.compact),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.bodyText,
    required this.realtimeHintLabel,
    required this.realtimeHintDetail,
    required this.bannerText,
    required this.palette,
  });

  final String bodyText;
  final String? realtimeHintLabel;
  final String? realtimeHintDetail;
  final String? bannerText;
  final _CallModePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('call-mode-body-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
        border: Border.all(color: palette.cardBorder),
        boxShadow: [
          BoxShadow(
            color: palette.cardShadow,
            blurRadius: 38,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.block),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: palette.primaryAction,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.compact),
                Text(
                  'OMNI',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.primaryAction,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                const Spacer(),
                Text(
                  'Live',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.secondaryText,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                _StatusWaveIcon(
                  color: palette.primaryAction,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stack),
            Text(
              bodyText,
              key: const Key('call-mode-body-text'),
              textAlign: TextAlign.left,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.primaryText,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                height: 1.58,
                fontFamily: 'monospace',
              ),
            ),
            if (realtimeHintLabel != null &&
                realtimeHintLabel!.trim().isNotEmpty &&
                realtimeHintDetail != null &&
                realtimeHintDetail!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.card),
              Divider(
                height: 1,
                thickness: 1,
                color: palette.cardInsetBorder,
              ),
              const SizedBox(height: AppSpacing.card),
              _RealtimeHintCard(
                label: realtimeHintLabel!,
                detail: realtimeHintDetail!,
                palette: palette,
              ),
            ],
            if (bannerText != null && bannerText!.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.stack),
              Text(
                bannerText!,
                textAlign: TextAlign.left,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.secondaryText,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RealtimeHintCard extends StatelessWidget {
  const _RealtimeHintCard({
    required this.label,
    required this.detail,
    required this.palette,
  });

  final String label;
  final String detail;
  final _CallModePalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('call-mode-realtime-hint'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.card,
        vertical: AppSpacing.card - 1,
      ),
      decoration: BoxDecoration(
        color: palette.cardInsetBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: palette.cardInsetBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.signal,
              boxShadow: [
                BoxShadow(
                  color: palette.signal.withValues(alpha: 0.28),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.compact),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  key: const Key('call-mode-realtime-hint-label'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: palette.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: AppSpacing.micro),
                Text(
                  detail,
                  key: const Key('call-mode-realtime-hint-detail'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.secondaryText,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
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

class _ControlDock extends StatelessWidget {
  const _ControlDock({
    required this.palette,
    required this.subtitlesVisible,
    required this.subtitleToggleTooltip,
    required this.closeTooltip,
    required this.onSubtitleTogglePressed,
    required this.onPrimaryPressed,
    required this.onClosePressed,
    required this.isBusy,
    required this.isLive,
    required this.compact,
  });

  final _CallModePalette palette;
  final bool subtitlesVisible;
  final String subtitleToggleTooltip;
  final String closeTooltip;
  final VoidCallback onSubtitleTogglePressed;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onClosePressed;
  final bool isBusy;
  final bool isLive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primaryColor = isBusy ? palette.stopAction : palette.primaryAction;
    final primaryIcon = isBusy
        ? Icons.stop_rounded
        : isLive
            ? Icons.graphic_eq_rounded
            : Icons.mic_rounded;
    final primaryShadow = primaryColor.withValues(alpha: 0.34);
    final sideDiameter = compact ? 36.0 : 48.0;
    final outerDiameter = compact ? 104.0 : 122.0;
    final innerDiameter = compact ? 86.0 : 98.0;
    final dockHeight = compact ? 118.0 : 154.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dockWidth = math.min(
          compact ? 336.0 : 388.0,
          constraints.maxWidth,
        );

        return SizedBox(
          height: dockHeight + AppSpacing.stackTight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: dockWidth,
                  height: dockHeight,
                  decoration: BoxDecoration(
                    color: palette.dockBackground,
                    borderRadius: BorderRadius.circular(44),
                    border: Border.all(color: palette.dockBorder),
                    boxShadow: [
                      BoxShadow(
                        color: palette.cardShadow,
                        blurRadius: 36,
                        offset: const Offset(0, 22),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? AppSpacing.stack : AppSpacing.block,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _DockActionButton(
                          buttonKey:
                              const Key('call-mode-subtitle-toggle-button'),
                          icon: subtitlesVisible
                              ? Icons.subtitles_rounded
                              : Icons.subtitles_off_rounded,
                          label: 'Subtitles',
                          tooltip: subtitleToggleTooltip,
                          palette: palette,
                          diameter: sideDiameter + 32,
                          isActive: subtitlesVisible,
                          onPressed: onSubtitleTogglePressed,
                        ),
                        SizedBox(width: outerDiameter),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _DockActionButton(
                              buttonKey: const Key('call-mode-close-button'),
                              icon: Icons.close_rounded,
                              label: 'End Chat',
                              tooltip: closeTooltip,
                              palette: palette,
                              diameter: sideDiameter + 32,
                              onPressed: onClosePressed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('call-mode-primary-button'),
                  onTap: onPrimaryPressed,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  child: Container(
                    width: outerDiameter,
                    height: outerDiameter,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withValues(alpha: 0.10),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: innerDiameter,
                        height: innerDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF79CCFF),
                              primaryColor,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryShadow,
                              blurRadius: 38,
                              spreadRadius: 2,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Icon(
                          primaryIcon,
                          size: compact ? 32 : 36,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.palette,
    required this.diameter,
    this.isActive = false,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final String tooltip;
  final _CallModePalette palette;
  final double diameter;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _GlassCircleButton(
                buttonKey: buttonKey,
                icon: icon,
                tooltip: tooltip,
                palette: palette,
                compact: true,
                diameter: diameter,
                isActive: isActive,
                onPressed: onPressed,
              ),
              if (isActive)
                Positioned(
                  top: 5,
                  right: 8,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.liveGreen,
                      boxShadow: [
                        BoxShadow(
                          color: palette.liveGreen.withValues(alpha: 0.50),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: palette.primaryText,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _CallModeOrb extends StatefulWidget {
  const _CallModeOrb({
    required this.animation,
    required this.palette,
    required this.isListening,
    required this.isSpeaking,
    required this.isBusy,
    required this.size,
  });

  final Animation<double> animation;
  final _CallModePalette palette;
  final bool isListening;
  final bool isSpeaking;
  final bool isBusy;
  final double size;

  @override
  State<_CallModeOrb> createState() => _CallModeOrbState();
}

class _CallModeOrbState extends State<_CallModeOrb> {
  static const String _gifAsset =
      'assets/call_mode/glowing_orb_water_loop_inner_small.gif';
  static Future<ui.FragmentProgram>? _shaderLoader;

  ui.FragmentProgram? _shaderProgram;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final loader = _shaderLoader ??=
          ui.FragmentProgram.fromAsset('shaders/call_mode_orb.frag');
      final program = await loader;
      if (!mounted) {
        return;
      }
      setState(() {
        _shaderProgram = program;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _shaderProgram = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final intensity = widget.isListening
        ? 1.0
        : widget.isSpeaking
            ? 0.88
            : widget.isBusy
                ? 0.72
                : 0.50;
    final baseScale = widget.isListening
        ? 1.08
        : widget.isSpeaking
            ? 1.04
            : widget.isBusy
                ? 1.01
                : 0.97;

    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        final wave = Curves.easeInOutSine.transform(widget.animation.value);
        final pulseScale = 0.985 + (0.052 * intensity * wave);
        final haloScale = 1.01 + (0.05 * intensity * wave);
        final bloomScale = 0.98 + (0.04 * intensity * wave);
        final bloomOpacity = 0.10 + (0.07 * intensity * wave);
        return Transform.scale(
          scale: baseScale * pulseScale,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: bloomScale,
                  child: Container(
                    width: widget.size * 0.94,
                    height: widget.size * 0.94,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0.0, -0.04),
                        radius: 0.92,
                        colors: [
                          Colors.white.withValues(
                            alpha: bloomOpacity * 0.03,
                          ),
                          widget.palette.haloBlue.withValues(
                            alpha: bloomOpacity * 0.22,
                          ),
                          widget.palette.haloPink.withValues(
                            alpha: bloomOpacity * 0.18,
                          ),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.44, 0.80, 1.0],
                      ),
                    ),
                  ),
                ),
                Image.asset(
                  _gifAsset,
                  key: const Key('call-mode-orb-gif'),
                  width: widget.size * 0.82,
                  height: widget.size * 0.82,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    final smokePainter = _shaderProgram == null
                        ? _CallModeOrbSmokeFallbackPainter(
                            progress: widget.animation.value,
                            intensity: intensity,
                            brightness: widget.palette.brightness,
                          )
                        : _CallModeOrbShaderPainter(
                            program: _shaderProgram!,
                            progress: widget.animation.value,
                            intensity: intensity,
                            brightness: widget.palette.brightness,
                          );

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size.square(widget.size),
                          painter: _CallModeOrbAuraPainter(
                            progress: widget.animation.value,
                            intensity: intensity,
                            palette: widget.palette,
                            haloScale: haloScale,
                          ),
                        ),
                        CustomPaint(
                          size: Size.square(widget.size),
                          painter: smokePainter,
                          foregroundPainter: _CallModeOrbGlassOverlayPainter(
                            progress: widget.animation.value,
                            intensity: intensity,
                            brightness: widget.palette.brightness,
                            palette: widget.palette,
                            haloScale: haloScale,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.palette,
    this.compact = false,
    this.diameter,
    this.isActive = false,
    required this.onPressed,
  });

  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final _CallModePalette palette;
  final bool compact;
  final double? diameter;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final resolvedDiameter = diameter ?? (compact ? 48.0 : 56.0);
    final backgroundColor = isActive
        ? palette.signal.withValues(
            alpha: palette.brightness == Brightness.dark ? 0.18 : 0.12,
          )
        : palette.buttonBackground;
    final borderColor = isActive
        ? palette.signal.withValues(
            alpha: palette.brightness == Brightness.dark ? 0.32 : 0.24,
          )
        : palette.buttonBorder;
    final iconColor = isActive ? palette.signal : palette.primaryText;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: buttonKey,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: Container(
            width: resolvedDiameter,
            height: resolvedDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: palette.buttonShadow,
                  blurRadius: compact ? 14 : 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: resolvedDiameter * 0.40,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.width,
    required this.height,
    required this.colors,
  });

  final double width;
  final double height;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width),
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

class _CallModePalette {
  const _CallModePalette({
    required this.brightness,
    required this.backgroundTop,
    required this.backgroundMid,
    required this.backgroundBase,
    required this.primaryText,
    required this.mutedText,
    required this.secondaryText,
    required this.labelBackground,
    required this.labelBorder,
    required this.signal,
    required this.liveGreen,
    required this.error,
    required this.cardBackground,
    required this.cardBorder,
    required this.cardInsetBackground,
    required this.cardInsetBorder,
    required this.cardShadow,
    required this.dockBackground,
    required this.dockBorder,
    required this.buttonBackground,
    required this.buttonBorder,
    required this.buttonShadow,
    required this.primaryAction,
    required this.stopAction,
    required this.haloBlue,
    required this.haloPink,
    required this.orbTop,
    required this.orbBottom,
    required this.topGlow,
    required this.sideGlow,
    required this.bottomGlow,
  });

  final Brightness brightness;
  final Color backgroundTop;
  final Color backgroundMid;
  final Color backgroundBase;
  final Color primaryText;
  final Color mutedText;
  final Color secondaryText;
  final Color labelBackground;
  final Color labelBorder;
  final Color signal;
  final Color liveGreen;
  final Color error;
  final Color cardBackground;
  final Color cardBorder;
  final Color cardInsetBackground;
  final Color cardInsetBorder;
  final Color cardShadow;
  final Color dockBackground;
  final Color dockBorder;
  final Color buttonBackground;
  final Color buttonBorder;
  final Color buttonShadow;
  final Color primaryAction;
  final Color stopAction;
  final Color haloBlue;
  final Color haloPink;
  final Color orbTop;
  final Color orbBottom;
  final List<Color> topGlow;
  final List<Color> sideGlow;
  final List<Color> bottomGlow;

  static _CallModePalette resolve(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return _CallModePalette(
        brightness: brightness,
        backgroundTop: const Color(0xFF08111B),
        backgroundMid: const Color(0xFF0C1623),
        backgroundBase: const Color(0xFF0A131D),
        primaryText: const Color(0xFFF3F7FC),
        mutedText: const Color(0xFF7D90A4),
        secondaryText: const Color(0xFF9FB0C4),
        labelBackground: Colors.white.withValues(alpha: 0.04),
        labelBorder: Colors.white.withValues(alpha: 0.06),
        signal: const Color(0xFF69C2FF),
        liveGreen: const Color(0xFF9CFF2D),
        error: AppColors.errorFor(brightness),
        cardBackground: const Color(0x9E111B28),
        cardBorder: const Color(0x4D7E91AA),
        cardInsetBackground: Colors.transparent,
        cardInsetBorder: const Color(0x1F9BC8FF),
        cardShadow: const Color(0xFF02060B).withValues(alpha: 0.52),
        dockBackground: const Color(0xC2111A27),
        dockBorder: const Color(0x4A7E91AA),
        buttonBackground: const Color(0xFF111B2A).withValues(alpha: 0.82),
        buttonBorder: const Color(0x667E91AA),
        buttonShadow: Colors.black.withValues(alpha: 0.34),
        primaryAction: const Color(0xFF47A9FF),
        stopAction: const Color(0xFFFF7A6E),
        haloBlue: const Color(0xFF54A6FF),
        haloPink: const Color(0xFF8B7DFF),
        orbTop: const Color(0xFFF6F3FF),
        orbBottom: const Color(0xFF2D56E8),
        topGlow: [
          const Color(0xFF3C7DFF).withValues(alpha: 0.22),
          const Color(0xFF9A7CFF).withValues(alpha: 0.12),
          Colors.transparent,
        ],
        sideGlow: [
          const Color(0xFF62C5FF).withValues(alpha: 0.14),
          Colors.transparent,
        ],
        bottomGlow: [
          const Color(0xFF162435).withValues(alpha: 0.10),
          Colors.transparent,
        ],
      );
    }

    return _CallModePalette(
      brightness: brightness,
      backgroundTop: AppColors.boardFor(brightness),
      backgroundMid: AppColors.panelFor(brightness),
      backgroundBase: const Color(0xFFF7FBFF),
      primaryText: AppColors.textFor(brightness),
      mutedText: AppColors.mutedFor(brightness),
      secondaryText: AppColors.mutedSoftFor(brightness),
      labelBackground: Colors.white.withValues(alpha: 0.72),
      labelBorder: const Color(0xFFE0E9F8),
      signal: AppColors.accentBlueFor(brightness),
      liveGreen: const Color(0xFF70D927),
      error: AppColors.errorFor(brightness),
      cardBackground: Colors.white.withValues(alpha: 0.76),
      cardBorder: const Color(0xFFDCE7FF),
      cardInsetBackground: const Color(0xFFF3F7FC),
      cardInsetBorder: const Color(0xFFD8E6FF),
      cardShadow: const Color(0xFF91A9D5).withValues(alpha: 0.20),
      dockBackground: Colors.white.withValues(alpha: 0.82),
      dockBorder: const Color(0xFFDCE7FF),
      buttonBackground: Colors.white.withValues(alpha: 0.92),
      buttonBorder: const Color(0xFFDCE7F5),
      buttonShadow: const Color(0xFF93A9D0).withValues(alpha: 0.18),
      primaryAction: AppColors.accentBlueFor(brightness),
      stopAction: const Color(0xFFFF7A6E),
      haloBlue: const Color(0xFF79B1FF),
      haloPink: AppColors.accentPurpleFor(brightness),
      orbTop: const Color(0xFFFFF7FD),
      orbBottom: const Color(0xFF5874F8),
      topGlow: [
        const Color(0xFFB8D4FF).withValues(alpha: 0.42),
        const Color(0xFFE7CFFF).withValues(alpha: 0.24),
        Colors.transparent,
      ],
      sideGlow: [
        const Color(0xFFAAD8FF).withValues(alpha: 0.34),
        Colors.transparent,
      ],
      bottomGlow: [
        const Color(0xFFD5CCFF).withValues(alpha: 0.26),
        Colors.transparent,
      ],
    );
  }
}

class _CallModeOrbAuraPainter extends CustomPainter {
  const _CallModeOrbAuraPainter({
    required this.progress,
    required this.intensity,
    required this.palette,
    required this.haloScale,
  });

  final double progress;
  final double intensity;
  final _CallModePalette palette;
  final double haloScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = size.width / 320.0;
    final time = progress * math.pi * 2;
    final pulse = 1.0 + (0.008 * intensity * math.sin(time * 1.08));
    final orbRadius = size.width * 0.326 * pulse;
    final auraRadius = orbRadius * (1.03 + ((haloScale - 1.0) * 0.10));

    final atmospherePaint = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * scale)
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.04),
        radius: 1.0,
        colors: [
          palette.haloBlue.withValues(alpha: 0.025 + (0.01 * intensity)),
          palette.haloPink.withValues(alpha: 0.018 + (0.01 * intensity)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.82, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: auraRadius * 1.04));
    canvas.drawCircle(center, auraRadius * 1.00, atmospherePaint);

    final crestCenter =
        center.translate(-(orbRadius * 0.06), -(orbRadius * 0.08));
    final crestRect = Rect.fromCircle(center: crestCenter, radius: auraRadius);
    final crestPaint = Paint()
      ..blendMode = BlendMode.plus
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, 1.3 * scale)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * scale)
      ..shader = SweepGradient(
        startAngle: -math.pi,
        endAngle: math.pi,
        transform: GradientRotation(-0.76 + (math.sin(time * 0.18) * 0.04)),
        colors: [
          Colors.transparent,
          palette.haloBlue.withValues(alpha: 0.015),
          Colors.white.withValues(alpha: 0.08),
          palette.haloBlue.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.12, 0.22, 0.32, 1.0],
      ).createShader(crestRect);
    canvas.drawArc(crestRect, -2.36, 0.76, false, crestPaint);

    final lowerRect = Rect.fromCircle(
      center: center.translate(0, orbRadius * 0.07),
      radius: auraRadius * 0.96,
    );
    final lowerPaint = Paint()
      ..blendMode = BlendMode.plus
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, 1.1 * scale)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale)
      ..shader = SweepGradient(
        startAngle: -math.pi,
        endAngle: math.pi,
        transform: const GradientRotation(0.72),
        colors: [
          Colors.transparent,
          palette.haloPink.withValues(alpha: 0.025),
          palette.haloBlue.withValues(alpha: 0.03),
          Colors.transparent,
        ],
        stops: const [0.0, 0.30, 0.48, 1.0],
      ).createShader(lowerRect);
    canvas.drawArc(lowerRect, 0.68, 1.08, false, lowerPaint);
  }

  @override
  bool shouldRepaint(covariant _CallModeOrbAuraPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.haloScale != haloScale ||
        oldDelegate.palette != palette;
  }
}

class _CallModeOrbGlassOverlayPainter extends CustomPainter {
  const _CallModeOrbGlassOverlayPainter({
    required this.progress,
    required this.intensity,
    required this.brightness,
    required this.palette,
    required this.haloScale,
  });

  final double progress;
  final double intensity;
  final Brightness brightness;
  final _CallModePalette palette;
  final double haloScale;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 320.0;
    final center = size.center(Offset.zero);
    final time = progress * math.pi * 2;
    final pulse = 1.0 + (0.010 * intensity * math.sin(time * 1.18));
    final orbRadius = size.width * 0.326 * pulse;
    final auraScale = 1.10 + ((haloScale - 1.0) * 0.68);
    final auraRadius = orbRadius * auraScale;
    final coreCenter = center.translate(-(orbRadius * 0.04), orbRadius * 0.03);
    final coolWhite = brightness == Brightness.dark
        ? const Color(0xFFF7FCFF)
        : const Color(0xFFFFFFFF);
    final coolCyan = brightness == Brightness.dark
        ? const Color(0xFFD8F8FF)
        : const Color(0xFFCFEFFF);

    final atmosphereBounds = Rect.fromCircle(
      center: center,
      radius: auraRadius * 1.34,
    );
    final atmospherePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: const Alignment(0, -0.04),
        radius: 1.0,
        colors: [
          palette.haloBlue.withValues(alpha: 0.04 + (0.015 * intensity)),
          palette.haloPink.withValues(alpha: 0.018 + (0.010 * intensity)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.72, 1.0],
      ).createShader(atmosphereBounds);
    canvas.drawCircle(center, auraRadius * 0.99, atmospherePaint);

    final shellBounds =
        Rect.fromCircle(center: center, radius: orbRadius * 1.02);
    final shellPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, 1.5 * scale)
      ..shader = SweepGradient(
        startAngle: -math.pi,
        endAngle: math.pi,
        transform: const GradientRotation(-0.52),
        colors: [
          Colors.white.withValues(alpha: 0.03),
          coolWhite.withValues(alpha: 0.86),
          palette.haloBlue.withValues(alpha: 0.88),
          palette.haloPink.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.03),
        ],
        stops: const [0.0, 0.15, 0.42, 0.72, 1.0],
      ).createShader(shellBounds);
    canvas.drawCircle(center, orbRadius * 0.992, shellPaint);

    final shellEchoPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, 1.0 * scale)
      ..color = palette.haloBlue.withValues(alpha: 0.035 + (0.02 * intensity))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale);
    canvas.drawCircle(center, orbRadius * 1.03, shellEchoPaint);

    final crestBounds = Rect.fromCircle(
      center: center.translate(-(orbRadius * 0.08), -(orbRadius * 0.10)),
      radius: orbRadius * 0.88,
    );
    final crestPaint = Paint()
      ..blendMode = BlendMode.plus
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, 1.1 * scale)
      ..shader = SweepGradient(
        startAngle: -math.pi,
        endAngle: math.pi,
        transform: const GradientRotation(-0.92),
        colors: [
          Colors.transparent,
          coolWhite.withValues(alpha: 0.14),
          coolCyan.withValues(alpha: 0.30),
          coolWhite.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.12, 0.24, 0.34, 1.0],
      ).createShader(crestBounds)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.8 * scale);
    canvas.drawArc(crestBounds, -2.42, 0.84, false, crestPaint);

    final coreBounds = Rect.fromCircle(
      center: coreCenter.translate(-(orbRadius * 0.01), 0),
      radius: orbRadius * 0.11,
    );
    final corePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: const Alignment(-0.12, -0.08),
        radius: 0.96,
        colors: [
          coolWhite.withValues(alpha: 0.24),
          coolCyan.withValues(alpha: 0.18),
          palette.haloBlue.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.10, 0.32, 1.0],
      ).createShader(coreBounds);
    canvas.save();
    canvas.translate(coreCenter.dx - (orbRadius * 0.01), coreCenter.dy);
    canvas.rotate(-0.26);
    canvas.scale(1.06, 0.74);
    canvas.drawCircle(Offset.zero, orbRadius * 0.065, corePaint);
    canvas.restore();

    final coreHaloPaint = Paint()
      ..blendMode = BlendMode.plus
      ..color = coolCyan.withValues(alpha: 0.020 + (0.012 * intensity))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * scale);
    canvas.save();
    canvas.translate(coreCenter.dx - (orbRadius * 0.02), coreCenter.dy);
    canvas.rotate(-0.26);
    canvas.scale(1.08, 0.78);
    canvas.drawCircle(Offset.zero, orbRadius * 0.05, coreHaloPaint);
    canvas.restore();

    final hotCorePaint = Paint()
      ..blendMode = BlendMode.plus
      ..color = Colors.white.withValues(alpha: 0.08 + (0.03 * intensity))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale);
    canvas.save();
    canvas.translate(
      coreCenter.dx - (orbRadius * 0.04),
      coreCenter.dy - (orbRadius * 0.015),
    );
    canvas.rotate(-0.20);
    canvas.scale(0.82, 0.60);
    canvas.drawCircle(Offset.zero, orbRadius * 0.03, hotCorePaint);
    canvas.restore();

    final specDotCenter =
        center.translate(-(orbRadius * 0.31), -(orbRadius * 0.23));
    final specDotBounds = Rect.fromCircle(
      center: specDotCenter,
      radius: orbRadius * 0.055,
    );
    final specDotPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          coolWhite.withValues(alpha: 0.74),
          coolCyan.withValues(alpha: 0.16),
          Colors.transparent,
        ],
        stops: const [0.0, 0.44, 1.0],
      ).createShader(specDotBounds);
    canvas.drawCircle(specDotCenter, orbRadius * 0.055, specDotPaint);

    final lowerShellPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, 1.5 * scale)
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          palette.haloBlue.withValues(alpha: 0.16),
          palette.haloPink.withValues(alpha: 0.12),
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(shellBounds);
    canvas.drawArc(
      shellBounds,
      0.34,
      2.48,
      false,
      lowerShellPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CallModeOrbGlassOverlayPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.brightness != brightness ||
        oldDelegate.haloScale != haloScale;
  }
}

class _CallModeOrbShaderPainter extends CustomPainter {
  const _CallModeOrbShaderPainter({
    required this.program,
    required this.progress,
    required this.intensity,
    required this.brightness,
  });

  final ui.FragmentProgram program;
  final double progress;
  final double intensity;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse =
        1.0 + (0.006 * intensity * math.sin(progress * math.pi * 2 * 1.06));
    final shaderSide = size.width * 0.82 * pulse;
    final left = (size.width - shaderSide) / 2;
    final top = (size.height - shaderSide) / 2;
    final shader = program.fragmentShader()
      ..setFloat(0, shaderSide)
      ..setFloat(1, shaderSide)
      ..setFloat(2, progress)
      ..setFloat(3, intensity)
      ..setFloat(4, brightness == Brightness.dark ? 1.0 : 0.0);

    canvas.save();
    canvas.translate(left, top);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, shaderSide, shaderSide),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CallModeOrbShaderPainter oldDelegate) {
    return oldDelegate.program != program ||
        oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.brightness != brightness;
  }
}

class _CallModeOrbSmokeFallbackPainter extends CustomPainter {
  const _CallModeOrbSmokeFallbackPainter({
    required this.progress,
    required this.intensity,
    required this.brightness,
  });

  final double progress;
  final double intensity;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = size.width / 320.0;
    final time = progress * math.pi * 2.0;
    final orbRadius = size.width * 0.326;
    final coolWhite = brightness == Brightness.dark
        ? const Color(0xFFF7FCFF)
        : const Color(0xFFFFFFFF);
    final deepBlue = brightness == Brightness.dark
        ? const Color(0xFF111B40)
        : const Color(0xFF2E3B77);
    final mistBlue = brightness == Brightness.dark
        ? const Color(0xFF75B6FF)
        : const Color(0xFF85C5FF);
    final mistLilac = brightness == Brightness.dark
        ? const Color(0xFFBCA9FF)
        : const Color(0xFFC6B4FF);

    final baseBounds =
        Rect.fromCircle(center: center, radius: orbRadius * 0.98);
    final basePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.12, -0.08),
        radius: 1.0,
        colors: [
          mistBlue.withValues(alpha: 0.42),
          const Color(0xFF416EEA).withValues(alpha: 0.42),
          deepBlue,
        ],
        stops: const [0.0, 0.46, 1.0],
      ).createShader(baseBounds);
    canvas.drawCircle(center, orbRadius * 0.98, basePaint);

    final clipPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: orbRadius * 0.95,
        ),
      );
    canvas.save();
    canvas.clipPath(clipPath);

    void drawSmokeBlob({
      required Offset blobCenter,
      required double radius,
      required double squash,
      required double angle,
      required Color color,
      required double alpha,
    }) {
      canvas.save();
      canvas.translate(blobCenter.dx, blobCenter.dy);
      canvas.rotate(angle);
      canvas.scale(1.0, squash);
      final bounds = Rect.fromCircle(
        center: Offset.zero,
        radius: radius * 1.4,
      );
      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale)
        ..shader = RadialGradient(
          center: const Alignment(-0.12, -0.08),
          radius: 1.0,
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.42),
            Colors.transparent,
          ],
          stops: const [0.0, 0.44, 1.0],
        ).createShader(bounds);
      canvas.drawCircle(Offset.zero, radius, paint);
      canvas.restore();
    }

    drawSmokeBlob(
      blobCenter: center.translate(
        -(orbRadius * 0.12) + (math.sin(time * 0.42) * orbRadius * 0.03),
        -(orbRadius * 0.10) + (math.cos(time * 0.36) * orbRadius * 0.025),
      ),
      radius: orbRadius * 0.30,
      squash: 0.82,
      angle: -0.54,
      color: coolWhite,
      alpha: 0.17,
    );
    drawSmokeBlob(
      blobCenter: center.translate(
        (orbRadius * 0.14) + (math.cos(time * 0.38) * orbRadius * 0.025),
        -(orbRadius * 0.03) + (math.sin(time * 0.34) * orbRadius * 0.020),
      ),
      radius: orbRadius * 0.28,
      squash: 0.74,
      angle: 0.62,
      color: mistBlue,
      alpha: 0.15,
    );
    drawSmokeBlob(
      blobCenter: center.translate(
        -(orbRadius * 0.10) + (math.sin(time * 0.28) * orbRadius * 0.02),
        (orbRadius * 0.11) + (math.cos(time * 0.40) * orbRadius * 0.03),
      ),
      radius: orbRadius * 0.25,
      squash: 0.86,
      angle: 0.26,
      color: mistLilac,
      alpha: 0.12,
    );

    final veilBounds = Rect.fromCircle(
      center: center.translate(0, orbRadius * 0.02),
      radius: orbRadius * 0.68,
    );
    final veilPaint = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = RadialGradient(
        center: const Alignment(-0.08, -0.06),
        radius: 1.0,
        colors: [
          coolWhite.withValues(alpha: 0.06),
          mistBlue.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(veilBounds);
    canvas.drawOval(
      Rect.fromCenter(
        center: veilBounds.center,
        width: veilBounds.width,
        height: veilBounds.height * 0.76,
      ),
      veilPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CallModeOrbSmokeFallbackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.brightness != brightness;
  }
}
