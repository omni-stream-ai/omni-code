import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../services/cloud_speech_service.dart';
import '../services/notification_service.dart';
import '../services/audio_recording_service.dart';
import '../services/speech_input_service.dart';
import '../services/tts_service.dart';
import '../services/tencent_cloud_streaming_asr_service.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/copyable_message.dart';
import '../../l10n/generated/app_localizations.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.session,
    this.sessionInitializer,
    this.client,
    this.enableSpeechServices = true,
    this.audioRecordingService,
    this.speechInputService,
    this.ttsService,
  });

  static const routeName = '/session';

  final SessionSummary session;
  final Future<SessionSummary>? sessionInitializer;
  final BridgeClient? client;
  final bool enableSpeechServices;
  final AudioRecordingService? audioRecordingService;
  final SpeechInputService? speechInputService;
  final TtsService? ttsService;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const double _bottomAutoScrollThreshold = 96;
  static const double _messageBubbleMaxWidth = 320;
  static const double _assistantMessageBubbleWidthFactor = 0.82;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final AudioRecordingService _audioRecordingService;
  late final SpeechInputService _speechInputService;
  late final TtsService _ttsService;
  late final TencentCloudStreamingAsrService _tencentCloudStreamingAsrService;
  final Set<String> _autoSpokenAssistantMessageIds = <String>{};
  final Set<String> _notifiedAssistantMessageIds = <String>{};
  final Map<String, _LocalMessageDraft> _localMessageStates = {};
  late SessionSummary _session;
  final List<ChatMessage> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _eventsSubscription;
  Timer? _eventsReconnectTimer;
  late final AnimationController _callModeOrbController;

  String? _recordingPath;
  String _recognizedSpeech = '';
  String? _systemAsrLocaleId;
  bool _systemAsrUnavailable = false;
  bool _loadingMessages = true;
  bool _speechReady = false;
  bool _ttsReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _callModeEnabled = false;
  bool _callModeAwaitingPlaybackCompletion = false;
  bool _systemTranscriptCompleting = false;
  bool _streamingAsrActive = false;
  final Map<String, int> _unreadToolCounts = <String, int>{};
  String? _speechStatus;
  String? _speechError;
  ApprovalRequest? _pendingApproval;
  bool _restoringSession = false;
  bool _appInForeground = true;
  bool _creatingSession = false;
  bool _submittingApproval = false;
  String? _submittingApprovalChoice;
  String? _submittedApprovalRequestId;
  bool _cancellingReply = false;

  BridgeClient get _client => widget.client ?? bridgeClient;

  String _systemSpeechUnavailableLabel() =>
      context.l10n.systemSpeechUnavailable;
  String? get _systemSpeechUnavailableStatus =>
      _speechError == null && _speechStatus == _systemSpeechUnavailableLabel()
          ? _speechStatus
          : null;
  String? get _speechBannerMessage => _speechError;

  String? get _callModeUnavailableMessage {
    if (!widget.enableSpeechServices) {
      return context.l10n.callModeUnavailable;
    }
    if (!_supportsCallModeAsrProvider()) {
      return context.l10n.callModeRequiresStreamingAsr;
    }
    if (_usesSystemSpeechForCallMode() && _systemAsrUnavailable) {
      return _systemSpeechUnavailableLabel();
    }
    return null;
  }

  String _reinitializingTtsLabel() => context.l10n.reinitializingTts;

  bool get _isAwaitingSubmittedApprovalResolution {
    final requestId = _submittedApprovalRequestId;
    if (requestId == null ||
        _session.status != SessionStatus.awaitingApproval) {
      return false;
    }
    final approval = _pendingApproval;
    return approval == null || approval.requestId == requestId;
  }

  void _reconcileSubmittedApprovalState() {
    final requestId = _submittedApprovalRequestId;
    if (requestId == null) {
      return;
    }
    if (_session.status != SessionStatus.awaitingApproval) {
      _submittedApprovalRequestId = null;
      return;
    }
    final approval = _pendingApproval;
    if (approval != null && approval.requestId != requestId) {
      _submittedApprovalRequestId = null;
    }
  }

  bool get _isMessageInputComposing {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _clearTransientTtsStatus() {
    if (_speechStatus == _reinitializingTtsLabel() ||
        _speechStatus == context.l10n.requestingTts) {
      _speechStatus = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _callModeOrbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _audioRecordingService =
        widget.audioRecordingService ?? AudioRecordingService();
    _speechInputService = widget.speechInputService ?? SpeechInputService();
    _ttsService = widget.ttsService ?? TtsService();
    _tencentCloudStreamingAsrService = TencentCloudStreamingAsrService();
    _session = widget.session;
    _pendingApproval = _session.pendingApproval;
    _creatingSession = widget.sessionInitializer != null;
    if (widget.enableSpeechServices) {
      _initializeSpeech();
      _initializeTts();
    }
    if (_creatingSession) {
      _loadingMessages = false;
      unawaited(_createSessionAndHydrate());
    } else {
      _loadMessages();
      _subscribeToEvents();
    }
  }

  @override
  void dispose() {
    _callModeOrbController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _eventsSubscription?.cancel();
    _eventsReconnectTimer?.cancel();
    unawaited(_audioRecordingService.cancel());
    unawaited(_speechInputService.cancel());
    unawaited(_tencentCloudStreamingAsrService.cancel());
    _ttsService.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      if (_creatingSession) {
        return;
      }
      unawaited(_restoreSessionAfterResume());
      return;
    }
    _appInForeground = false;
  }

  void _syncSessionSummaryCache() {
    _client.syncSessionSummary(_session);
  }

  @override
  Widget build(BuildContext context) {
    if (_callModeEnabled) {
      return _buildCallModeScaffold(context);
    }
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isSessionBusy = _session.status == SessionStatus.running;
    final hasActiveTurn = _session.status == SessionStatus.running ||
        _session.status == SessionStatus.awaitingApproval ||
        _pendingApproval != null;
    final canCancelReply = hasActiveTurn && !_cancellingReply;
    final turns = _turns;
    final approvalCardMaxHeight = MediaQuery.of(context).size.height * 0.42;
    final isAwaitingSubmittedApprovalResolution =
        _isAwaitingSubmittedApprovalResolution;
    final speechBannerMessage = _speechBannerMessage;
    final systemSpeechUnavailableMessage = _systemSpeechUnavailableStatus;
    final callModeUnavailableMessage = _callModeUnavailableMessage;
    final showVoiceInputUnavailableTooltip =
        systemSpeechUnavailableMessage != null &&
            !isSessionBusy &&
            !_speechReady &&
            !_isListening;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.compact,
        title: AppBackHeader(
          title: _session.title,
          titleStyle: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        actions: [
          _buildCallModeAction(
            unavailableMessage: callModeUnavailableMessage,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_creatingSession)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.block,
                AppSpacing.block,
                AppSpacing.block,
                0,
              ),
              padding: AppSpacing.tilePadding,
              decoration: BoxDecoration(
                color: AppColors.surfaceFor(brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                border: Border.all(color: AppColors.outlineFor(brightness)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.tileY),
                  Expanded(
                    child: Text(
                      l10n.creatingSession,
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if ((_session.status == SessionStatus.awaitingApproval ||
                  _pendingApproval != null) &&
              (_pendingApproval == null ||
                  isAwaitingSubmittedApprovalResolution))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.block,
                AppSpacing.block,
                AppSpacing.block,
                0,
              ),
              padding: AppSpacing.tilePadding,
              decoration: BoxDecoration(
                color: AppColors.warningSurfaceFor(brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                border:
                    Border.all(color: AppColors.warningBorderFor(brightness)),
              ),
              child: Text(
                l10n.waitingApprovalProcessing,
                style: const TextStyle(height: 1.4),
              ),
            ),
          if (speechBannerMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.block,
                AppSpacing.block,
                AppSpacing.block,
                0,
              ),
              child: CopyableMessage(
                message: speechBannerMessage,
                copyLabel: context.l10n.copy,
                copiedLabel: context.l10n.copied,
                backgroundColor: AppColors.errorBgFor(brightness),
                borderColor: AppColors.errorBorderFor(brightness),
                iconColor: AppColors.errorIconFor(brightness),
                textColor: AppColors.errorTextFor(brightness),
              ),
            ),
          if (_pendingApproval != null &&
              !isAwaitingSubmittedApprovalResolution)
            _buildPendingApprovalCard(approvalCardMaxHeight),
          Expanded(
            child: (_creatingSession || _loadingMessages)
                ? const _SessionMessagesSkeleton(
                    key: Key('session-chat-skeleton'),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: AppSpacing.blockPadding,
                      itemCount: turns.length,
                      itemBuilder: (context, index) {
                        final turn = turns[index];
                        return _buildTurn(context, turn);
                      },
                    ),
                  ),
          ),
          Container(
            padding: AppSpacing.blockPadding,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.outlineFor(brightness)),
              ),
            ),
            child: hasActiveTurn
                ? Column(
                    children: [
                      if (_session.status ==
                          SessionStatus.awaitingApproval) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.tileY),
                            Text(
                              l10n.waitingProcessApproval,
                              style: TextStyle(
                                color: AppColors.mutedSoftFor(brightness),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.stack),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: canCancelReply ? _cancelReply : null,
                          child: _cancellingReply
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.stopReply),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Focus(
                        onKeyEvent: _handleMessageInputKeyEvent,
                        child: TextField(
                          controller: _controller,
                          enabled: !isSessionBusy,
                          maxLines: 4,
                          minLines: 3,
                          decoration: InputDecoration(
                            hintText: l10n.messageInputHint,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.stack),
                      Row(
                        children: [
                          Expanded(
                            child: _withUnavailableTooltip(
                              message: showVoiceInputUnavailableTooltip
                                  ? systemSpeechUnavailableMessage
                                  : null,
                              child: OutlinedButton(
                                onPressed: (isSessionBusy ||
                                        (!_speechReady && !_isListening))
                                    ? null
                                    : _toggleListening,
                                child: Text(
                                  _isListening
                                      ? l10n.stopVoice
                                      : l10n.voiceInput,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.tileY),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  isSessionBusy ? null : _sendTextMessage,
                              child: Text(l10n.send),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Scaffold _buildCallModeScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final l10n = context.l10n;
    final speechBannerMessage = _speechBannerMessage;
    final lastAssistantMessage = _latestAssistantMessage;
    final lastAssistantPreview = _previewText(lastAssistantMessage?.content);
    final liveTranscript = _recognizedSpeech.trim().isNotEmpty
        ? _recognizedSpeech.trim()
        : _controller.text.trim();
    final statusLine = _callModeStatusLine(l10n);
    final subtitle = liveTranscript.isNotEmpty
        ? liveTranscript
        : (lastAssistantPreview.isNotEmpty
            ? lastAssistantPreview
            : _callModeIdleSubtitle(l10n));
    final orbScale = _isListening
        ? 1.08
        : _isSpeaking
            ? 1.04
            : _session.status == SessionStatus.running
                ? 1.02
                : 0.96;

    return Scaffold(
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFF0B1020)
          : const Color(0xFFF5F8FF),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: brightness == Brightness.dark
                ? const [
                    Color(0xFF121A31),
                    Color(0xFF0F1527),
                    Color(0xFF0B1020),
                  ]
                : const [
                    Color(0xFFFDFEFF),
                    Color(0xFFEFF5FF),
                    Color(0xFFEAF1FF),
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.block,
              AppSpacing.compact,
              AppSpacing.block,
              AppSpacing.block,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: l10n.close,
                      onPressed: () => unawaited(_disableCallMode()),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            l10n.voiceChatTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.mutedSoftFor(brightness),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const Spacer(),
                Text(
                  statusLine,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.accentBlueFor(brightness),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.stack),
                _buildCallModeOrb(
                  brightness: brightness,
                  baseScale: orbScale,
                ),
                const SizedBox(height: AppSpacing.section),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.section,
                    vertical: AppSpacing.card,
                  ),
                  decoration: BoxDecoration(
                    color: brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusHero),
                    border: Border.all(
                      color: brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFD9E6FF),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.45,
                          color: AppColors.textSoftFor(brightness),
                        ),
                      ),
                      if (speechBannerMessage != null) ...[
                        const SizedBox(height: AppSpacing.stack),
                        Text(
                          speechBannerMessage,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.errorTextFor(brightness),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildCallModeControlButton(
                      brightness: brightness,
                      icon: Icons.chat_bubble_outline_rounded,
                      tooltip: l10n.callModeOpenChatHistory,
                      onPressed: () {
                        unawaited(_disableCallMode());
                        _showLatestConversationPreview();
                      },
                    ),
                    const SizedBox(width: AppSpacing.section),
                    _buildCallModePrimaryButton(
                      brightness: brightness,
                      onPressed: () {
                        if (_session.status == SessionStatus.running) {
                          unawaited(_cancelReply());
                          return;
                        }
                        unawaited(_toggleListening());
                      },
                    ),
                    const SizedBox(width: AppSpacing.section),
                    _buildCallModeControlButton(
                      brightness: brightness,
                      icon: Icons.close_rounded,
                      tooltip: l10n.close,
                      onPressed: () => unawaited(_disableCallMode()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallModeControlButton({
    required Brightness brightness,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.white.withValues(alpha: 0.82),
              border: Border.all(
                color: brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFD7E5FF),
              ),
            ),
            child: Icon(
              icon,
              color: AppColors.textSoftFor(brightness),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallModeOrb({
    required Brightness brightness,
    required double baseScale,
  }) {
    final intensity = _isListening
        ? 1.0
        : _isSpeaking
            ? 0.82
            : _session.status == SessionStatus.running
                ? 0.68
                : 0.46;
    return AnimatedBuilder(
      animation: _callModeOrbController,
      builder: (context, child) {
        final wave = Curves.easeInOut.transform(_callModeOrbController.value);
        final pulseScale = 0.965 + (0.08 * intensity * wave);
        final haloScale = 1.08 + (0.18 * intensity * wave);
        final haloOpacity = 0.12 + (0.18 * intensity * wave);
        final sparkleOffset = -0.16 + (0.12 * wave);
        return Transform.scale(
          scale: baseScale * pulseScale,
          child: SizedBox(
            width: 258,
            height: 258,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: haloScale,
                  child: Container(
                    width: 188,
                    height: 188,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF78A7FF).withValues(alpha: haloOpacity),
                          const Color(0xFFB392FF)
                              .withValues(alpha: haloOpacity * 0.62),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 34,
                  child: Container(
                    width: 154,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF6C8FFF)
                              .withValues(alpha: 0.16 + (0.10 * intensity)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 236,
                  height: 236,
                  alignment: Alignment.center,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Align(
                        alignment: Alignment(-0.04 + (0.04 * wave), 0.02),
                        child: Container(
                          width: 188,
                          height: 188,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFFFD7EB)
                                    .withValues(alpha: 0.18 + (0.08 * intensity)),
                                const Color(0xFF9A88FF)
                                    .withValues(alpha: 0.10 + (0.06 * intensity)),
                                const Color(0xFF4E78FF)
                                    .withValues(alpha: 0.04 + (0.04 * intensity)),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.34, 0.72, 1.0],
                            ),
                          ),
                        ),
                      ),
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) {
                          return const RadialGradient(
                            center: Alignment(0, -0.04),
                            radius: 0.88,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.58, 1.0],
                          ).createShader(bounds);
                        },
                        child: CustomPaint(
                          painter: _CallModeOrbPainter(
                            progress: _callModeOrbController.value,
                            intensity: intensity,
                            brightness: brightness,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment(sparkleOffset, -0.46),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0.06),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallModePrimaryButton({
    required Brightness brightness,
    required VoidCallback onPressed,
  }) {
    final isBusy = _session.status == SessionStatus.running;
    final isLive = _isListening || _streamingAsrActive;
    final icon = isBusy
        ? Icons.stop_rounded
        : isLive
            ? Icons.graphic_eq_rounded
            : Icons.mic_rounded;
    final background = isBusy
        ? const Color(0xFFFF7B6B)
        : const Color(0xFF1E74FF);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background,
            boxShadow: [
              BoxShadow(
                color: background.withValues(alpha: 0.28),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 30,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  ChatMessage? get _latestAssistantMessage {
    for (var index = _messages.length - 1; index >= 0; index -= 1) {
      final message = _messages[index];
      if (message.role == MessageRole.assistant &&
          message.content.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  String _previewText(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final normalized = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}...';
  }

  String _callModeStatusLine(AppLocalizations l10n) {
    if (_speechError != null && _speechError!.trim().isNotEmpty) {
      return _speechError!;
    }
    if (_session.status == SessionStatus.awaitingApproval) {
      return l10n.waitingApprovalProcessing;
    }
    if (_session.status == SessionStatus.running) {
      return l10n.callModeWorking;
    }
    if (_callModeAwaitingPlaybackCompletion || _isSpeaking) {
      return l10n.callModeSpeaking;
    }
    if (_isListening || _streamingAsrActive) {
      return l10n.callModeListening;
    }
    return l10n.startCallMode;
  }

  String _callModeIdleSubtitle(AppLocalizations l10n) {
    return l10n.callModeIdleSubtitle;
  }

  Future<void> _showLatestConversationPreview() async {
    final previewMessages = _messages
        .where((message) =>
            message.role == MessageRole.user || message.role == MessageRole.assistant)
        .toList(growable: false);
    if (!mounted || previewMessages.isEmpty) {
      return;
    }
    final brightness = Theme.of(context).brightness;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panelFor(brightness),
      isScrollControlled: true,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.62;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.block,
                    AppSpacing.block,
                    AppSpacing.block,
                    AppSpacing.compact,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _session.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.block,
                      0,
                      AppSpacing.block,
                      AppSpacing.block,
                    ),
                    itemCount: previewMessages.length,
                    itemBuilder: (context, index) {
                      final message = previewMessages[index];
                      final isUser = message.role == MessageRole.user;
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.stack),
                          padding: const EdgeInsets.all(AppSpacing.card),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: isUser
                                ? AppColors.accentBlueFor(brightness)
                                : AppColors.panelDeepFor(brightness),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusPanel),
                            border: isUser
                                ? null
                                : Border.all(
                                    color: AppColors.outlineFor(brightness),
                                  ),
                          ),
                          child: Text(
                            _previewText(message.content),
                            style: TextStyle(
                              height: 1.45,
                              color: isUser
                                  ? AppColors.accentBlueOnFor(brightness)
                                  : AppColors.textSoftFor(brightness),
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
      },
    );
  }

  Widget _withUnavailableTooltip({
    required String? message,
    required Widget child,
  }) {
    if (message == null || message.isEmpty) {
      return child;
    }

    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      waitDuration: Duration.zero,
      showDuration: const Duration(seconds: 2),
      exitDuration: const Duration(milliseconds: 100),
      child: child,
    );
  }

  Widget _buildCallModeAction({
    required String? unavailableMessage,
  }) {
    final brightness = Theme.of(context).brightness;
    final onPressed = _callModeEnabled
        ? () => unawaited(_disableCallMode())
        : unavailableMessage == null
            ? () => unawaited(_enableCallMode())
            : null;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.block),
      child: _withUnavailableTooltip(
        message: !_callModeEnabled ? unavailableMessage : null,
        child: IconButton(
          key: const Key('session-call-mode-button'),
          tooltip: unavailableMessage == null
              ? (_callModeEnabled
                  ? context.l10n.stopCallMode
                  : context.l10n.startCallMode)
              : null,
          onPressed: onPressed,
          style: _callModeEnabled
              ? IconButton.styleFrom(
                  backgroundColor: AppColors.primaryFor(brightness),
                  foregroundColor: AppColors.onPrimaryFor(brightness),
                  side: BorderSide(
                    color: AppColors.primaryFor(brightness),
                  ),
                )
              : null,
          icon: Icon(
            _callModeEnabled
                ? Icons.phone_in_talk_rounded
                : Icons.call_outlined,
          ),
        ),
      ),
    );
  }

  String _agentLabel(AgentKind agent) {
    return agent.label;
  }

  Widget _buildPendingApprovalCard(double maxHeight) {
    final approval = _pendingApproval!;
    final summary = approval.reason ?? approval.command ?? approval.kind;
    final isSubmitting = _submittingApproval;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.block,
        AppSpacing.block,
        AppSpacing.block,
        0,
      ),
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.warningSurfaceFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.warningBorderFor(brightness)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.agentAwaitingPermission(_agentLabel(_session.agent)),
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.warningTextFor(brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.compact),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                    if (approval.command != null) ...[
                      const SizedBox(height: AppSpacing.compact),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.tileY),
                        decoration: BoxDecoration(
                          color: AppColors.panelDeepFor(brightness),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusControl,
                          ),
                          border: Border.all(
                            color: AppColors.warningBorderFor(brightness),
                          ),
                        ),
                        child: SelectableText(
                          approval.command!,
                          style: TextStyle(
                            color: AppColors.warningTextFor(brightness),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    if (!approval.resolvable) ...[
                      const SizedBox(height: AppSpacing.compact),
                      Text(
                        context.l10n.desktopOnlyApproval,
                        style: TextStyle(
                          color: AppColors.warningTextFor(brightness),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.stack),
            Wrap(
              spacing: AppSpacing.compact,
              runSpacing: AppSpacing.compact,
              children: [
                FilledButton(
                  onPressed: approval.resolvable && !isSubmitting
                      ? () => _submitApproval('accept')
                      : null,
                  child: _buildApprovalButtonChild(
                    'accept',
                    context.l10n.approve,
                  ),
                ),
                if (approval.allowAcceptForSession)
                  OutlinedButton(
                    onPressed: approval.resolvable && !isSubmitting
                        ? () => _submitApproval('accept_for_session')
                        : null,
                    child: _buildApprovalButtonChild(
                      'accept_for_session',
                      context.l10n.approveForSession,
                    ),
                  ),
                OutlinedButton(
                  onPressed: approval.resolvable && !isSubmitting
                      ? () => _submitApproval('decline')
                      : null,
                  child: _buildApprovalButtonChild(
                    'decline',
                    context.l10n.reject,
                  ),
                ),
                if (approval.allowCancel)
                  OutlinedButton(
                    onPressed: approval.resolvable && !isSubmitting
                        ? () => _submitApproval('cancel')
                        : null,
                    child: _buildApprovalButtonChild(
                      'cancel',
                      context.l10n.cancel,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalButtonChild(String choice, String label) {
    final isSubmittingThisChoice =
        _submittingApproval && _submittingApprovalChoice == choice;
    if (!isSubmittingThisChoice) {
      return Text(label);
    }
    final brightness = Theme.of(context).brightness;
    final spinnerColor =
        choice == 'accept' ? AppColors.onPrimaryFor(brightness) : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: spinnerColor,
          ),
        ),
        const SizedBox(width: AppSpacing.compact),
        Text(context.l10n.processing),
      ],
    );
  }

  Widget _buildTurn(BuildContext context, _ConversationTurn turn) {
    final turnId = turn.id;
    final unreadCount = _unreadToolCounts[turnId] ?? 0;
    final hasHighlight = unreadCount > 0 && turnId == _activeTurnId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final messageBubbleMaxWidth =
            _messageBubbleMaxWidthFor(constraints.maxWidth);
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.screenBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (turn.userMessage != null)
                _buildUserMessage(
                  turn.userMessage!,
                  maxWidth: messageBubbleMaxWidth,
                ),
              ...turn.assistantMessages.map(
                (message) => _buildAssistantMessage(
                  message,
                  maxWidth: messageBubbleMaxWidth,
                ),
              ),
              if (turn.toolMessages.isNotEmpty)
                _buildToolEntry(
                  count: turn.toolMessages.length,
                  highlighted: hasHighlight,
                  onTap: () => _showAllSystemMessages(turn),
                ),
            ],
          ),
        );
      },
    );
  }

  double _messageBubbleMaxWidthFor(double availableWidth) {
    final preferredWidth = availableWidth * _assistantMessageBubbleWidthFactor;
    return math.min(
      availableWidth,
      math.min(
        AppSpacing.contentMaxWidth,
        math.max(_messageBubbleMaxWidth, preferredWidth),
      ),
    );
  }

  Widget _buildUserMessage(
    ChatMessage message, {
    required double maxWidth,
  }) {
    final localState = _localMessageStates[message.id];
    final canRetry = localState?.state == _LocalMessageState.failed;
    final brightness = Theme.of(context).brightness;
    final bubbleTextColor = AppColors.accentBlueOnFor(brightness);
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: canRetry ? () => _retryLocalMessage(message.id) : null,
        child: Container(
          key: ValueKey('user-message-bubble-${message.id}'),
          margin: const EdgeInsets.only(bottom: AppSpacing.stack),
          padding: AppSpacing.cardPadding,
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: BoxDecoration(
            color: AppColors.accentBlueFor(brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                message.content,
                style: TextStyle(
                  height: 1.45,
                  color: bubbleTextColor,
                ),
              ),
              if (localState != null) ...[
                const SizedBox(height: AppSpacing.compact),
                Text(
                  localState.label(context),
                  style: TextStyle(
                    fontSize: 11,
                    color: localState.state == _LocalMessageState.failed
                        ? AppColors.errorTextFor(brightness)
                        : bubbleTextColor.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolEntry({
    required int count,
    required bool highlighted,
    required VoidCallback onTap,
  }) {
    final brightness = Theme.of(context).brightness;
    final baseSurface = AppColors.panelDeepFor(brightness);
    final backgroundColor = highlighted
        ? AppColors.tintSurfaceFor(
            brightness,
            AppColors.signalFor(brightness),
            base: baseSurface,
            darkAlpha: 0.30,
            lightAlpha: 0.18,
          )
        : baseSurface;
    final borderColor = highlighted
        ? AppColors.tintBorderFor(
            brightness,
            AppColors.signalFor(brightness),
            base: baseSurface,
            darkAlpha: 0.56,
            lightAlpha: 0.30,
          )
        : AppColors.outlineStrongFor(brightness);
    final labelColor = highlighted
        ? AppColors.textFor(brightness)
        : AppColors.mutedSoftFor(brightness);
    final countColor = highlighted
        ? AppColors.textSoftFor(brightness)
        : AppColors.mutedFor(brightness);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.compact),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.compact,
                vertical: AppSpacing.iconTight,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                border: Border.all(
                  color: borderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 12,
                    color: labelColor,
                  ),
                  const SizedBox(width: AppSpacing.micro),
                  Text(
                    context.l10n.toolActivity,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.micro),
                  Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      color: countColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(
    ChatMessage message, {
    required double maxWidth,
  }) {
    final displayContent = _displayContentForMessage(message);
    final isLoadingReply = message.content.trim().isEmpty &&
        _session.status == SessionStatus.running;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final ttsUnavailableMessage =
        !_ttsReady && !_isSpeaking ? _systemSpeechUnavailableStatus : null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: ValueKey('assistant-message-bubble-${message.id}'),
        margin: const EdgeInsets.only(bottom: AppSpacing.stack),
        padding: AppSpacing.cardPadding,
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: AppColors.panelDeepFor(brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
          border: Border.all(color: AppColors.outlineFor(brightness)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoadingReply)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.tileY),
                  Text(
                    context.l10n.working,
                    style: TextStyle(
                      height: 1.45,
                      color: AppColors.mutedSoftFor(brightness),
                    ),
                  ),
                ],
              )
            else ...[
              MarkdownBody(
                data: displayContent,
                fitContent: true,
                selectable: true,
                shrinkWrap: true,
                softLineBreak: true,
                styleSheet: _assistantMarkdownStyleSheet(theme),
                syntaxHighlighter: _AssistantCodeSyntaxHighlighter(theme),
                onTapLink: (text, href, title) =>
                    _handleAssistantMarkdownLinkTap(href),
              ),
              const SizedBox(height: AppSpacing.tileY),
              _withUnavailableTooltip(
                message: ttsUnavailableMessage,
                child: OutlinedButton(
                  onPressed: _isSpeaking
                      ? _stopSpeaking
                      : (_ttsReady
                          ? () => _speakMessage(message.content)
                          : null),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.outlineStrongFor(brightness),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.tileX,
                      vertical: AppSpacing.tileY,
                    ),
                  ),
                  child: Text(
                    _isSpeaking
                        ? context.l10n.stopPlayback
                        : context.l10n.playback,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _assistantMarkdownStyleSheet(ThemeData theme) {
    final brightness = theme.brightness;
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      color: AppColors.textFor(brightness),
    );
    final headingColor = AppColors.textFor(brightness);
    final codeSurfaceColor = AppColors.tintSurfaceFor(
      brightness,
      AppColors.signalFor(brightness),
      base: AppColors.panelFor(brightness),
      darkAlpha: 0.16,
      lightAlpha: 0.09,
    );
    final outlineColor = AppColors.tintBorderFor(
      brightness,
      AppColors.signalFor(brightness),
      base: AppColors.outlineFor(brightness),
      darkAlpha: 0.34,
      lightAlpha: 0.18,
    );
    final linkColor = AppColors.signalFor(brightness);
    final inlineCodeBackground = AppColors.tintSurfaceFor(
      brightness,
      AppColors.signalFor(brightness),
      base: AppColors.surfaceFor(brightness),
      darkAlpha: 0.12,
      lightAlpha: 0.07,
    );
    final codeStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: (bodyStyle?.fontSize ?? 14) * 0.93,
      height: 1.55,
      color: AppColors.textFor(brightness),
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const <String>['monospace'],
      letterSpacing: 0.1,
    );

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: bodyStyle,
      a: bodyStyle?.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
      ),
      code: codeStyle?.copyWith(
        backgroundColor: inlineCodeBackground,
      ),
      strong: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
      em: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
      listBullet: bodyStyle,
      blockquote: bodyStyle?.copyWith(
        color: AppColors.textSoftFor(brightness),
      ),
      pPadding: const EdgeInsets.symmetric(vertical: 1),
      blockSpacing: AppSpacing.compact,
      codeblockPadding: const EdgeInsets.fromLTRB(
        AppSpacing.tileX,
        AppSpacing.tileY,
        AppSpacing.tileX,
        AppSpacing.tileX,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeSurfaceColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.boardFor(brightness).withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      blockquotePadding: AppSpacing.tilePadding,
      blockquoteDecoration: BoxDecoration(
        color: AppColors.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: outlineColor),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: outlineColor)),
      ),
      h1: theme.textTheme.titleLarge?.copyWith(color: headingColor),
      h2: theme.textTheme.titleMedium?.copyWith(color: headingColor),
      h3: theme.textTheme.titleSmall?.copyWith(color: headingColor),
      h4: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
      h5: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
      h6: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  void _handleAssistantMarkdownLinkTap(String? href) {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null) {
      return;
    }
    unawaited(launchUrl(uri));
  }

  String _toolMessagePreview(ChatMessage message) {
    final parsed = _parseToolMessage(message.content);
    if (parsed == null) {
      return _compactToolText(message.content);
    }

    final parts = <String>[parsed.kindLabel];
    if (parsed.phaseLabel != null && parsed.phaseLabel!.isNotEmpty) {
      parts.add(parsed.phaseLabel!);
    }

    final primary = parsed.primary?.trim();
    if (primary != null && primary.isNotEmpty) {
      parts.add(_compactToolText(primary));
    } else if (parsed.secondaryItems.isNotEmpty) {
      parts.add(_compactToolText(parsed.secondaryItems.first));
    }

    if (parsed.trailingNote != null && parsed.trailingNote!.isNotEmpty) {
      parts.add(parsed.trailingNote!);
    }

    return parts.join(' · ');
  }

  String _compactToolText(String text) {
    final compacted = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compacted.length <= 96) {
      return compacted;
    }
    return '${compacted.substring(0, 96)}…';
  }

  Future<void> _createSessionAndHydrate() async {
    final initializer = widget.sessionInitializer;
    if (initializer == null) {
      return;
    }

    try {
      final session = await initializer;
      if (!mounted) {
        return;
      }
      if (kIsWeb) {
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.session(session.projectId, session.id),
          arguments: session,
        );
        return;
      }
      setState(() {
        _session = session;
        _pendingApproval = session.pendingApproval;
        _reconcileSubmittedApprovalState();
        _creatingSession = false;
        _loadingMessages = true;
        _speechError = null;
      });
      _subscribeToEvents();
      await _loadMessages();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creatingSession = false;
        _speechError = context.l10n.createSessionFailed('$error');
      });
    }
  }

  Future<void> _loadMessages() async {
    if (_creatingSession) {
      return;
    }
    try {
      final messages = await _client.listMessages(_session.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _loadingMessages = false;
      });
      _jumpToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingMessages = false;
        _speechError = context.l10n.loadMessagesFailed('$error');
      });
    }
  }

  void _subscribeToEvents() {
    if (_creatingSession) {
      return;
    }
    _eventsSubscription?.cancel();
    _eventsReconnectTimer?.cancel();
    _eventsSubscription = _client.subscribeToSessionEvents(_session.id).listen(
          _handleBridgeEvent,
          onError: (_) => _scheduleEventReconnect(),
          onDone: _scheduleEventReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleEventReconnect() {
    if (!mounted) {
      return;
    }
    _eventsSubscription?.cancel();
    _eventsReconnectTimer?.cancel();
    _eventsReconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      unawaited(_restoreSessionAfterResume());
    });
  }

  Future<void> _restoreSessionAfterResume() async {
    if (_creatingSession) {
      return;
    }
    if (_restoringSession) {
      return;
    }
    _restoringSession = true;
    try {
      _subscribeToEvents();

      final results = await Future.wait<Object?>([
        _client.listMessages(_session.id),
        _client.listProjectSessions(_session.projectId, forceRefresh: true),
      ]);
      if (!mounted) {
        return;
      }

      final messages = results[0] as List<ChatMessage>;
      final sessions = results[1] as List<SessionSummary>;
      final refreshedSession = sessions
          .where((session) => session.id == _session.id)
          .cast<SessionSummary?>()
          .firstWhere(
            (_) => true,
            orElse: () => null,
          );

      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _loadingMessages = false;
        _pendingApproval = refreshedSession?.pendingApproval;
        _speechError = null;
        if (refreshedSession != null) {
          _session = refreshedSession;
        }
        _reconcileSubmittedApprovalState();
      });
      _maybeAutoScrollToBottom();
      if (_callModeEnabled) {
        unawaited(_maybeResumeCallModeListening());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechError = context.l10n.restoreSessionFailed('$error');
      });
    } finally {
      _restoringSession = false;
    }
  }

  void _handleBridgeEvent(Map<String, dynamic> event) {
    final data = event['data'] as Map<String, dynamic>;
    final type = data['type'] as String?;
    final payload = data['payload'] as Map<String, dynamic>?;

    if (!mounted || type == null || payload == null) {
      return;
    }

    switch (type) {
      case 'session_snapshot':
        setState(() {
          _session = SessionSummary.fromJson(payload);
          _pendingApproval = _session.pendingApproval;
          _reconcileSubmittedApprovalState();
        });
        _syncSessionSummaryCache();
        _maybeAutoScrollToBottom();
        break;
      case 'session_status':
        final status = parseSessionStatus(payload['status'] as String);
        setState(() {
          _session = _session.copyWith(
            status: status,
            updatedAt: DateTime.now(),
          );
          if (status != SessionStatus.awaitingApproval) {
            _pendingApproval = null;
          }
          _reconcileSubmittedApprovalState();
        });
        _syncSessionSummaryCache();
        final latestAssistantMessage = _messages
            .where((item) => item.role == MessageRole.assistant)
            .cast<ChatMessage?>()
            .lastWhere((_) => true, orElse: () => null);
        var startedPlayback = false;
        if (latestAssistantMessage != null) {
          startedPlayback =
              _maybeAutoSpeakAssistantMessage(latestAssistantMessage.id);
          _maybeNotifyAssistantMessage(latestAssistantMessage.id);
        }
        if (_callModeEnabled &&
            !startedPlayback &&
            status != SessionStatus.running) {
          unawaited(_maybeResumeCallModeListening());
        }
        break;
      case 'message_created':
        final shouldAutoScroll = _isNearBottom();
        final message = ChatMessage.fromJson(payload);
        setState(() {
          _localMessageStates.remove(message.id);
          if (message.role == MessageRole.system) {
            final turnId = _activeTurnId;
            if (turnId != null) {
              _unreadToolCounts.update(turnId, (value) => value + 1,
                  ifAbsent: () => 1);
            }
          }
          final index = _messages.indexWhere((item) => item.id == message.id);
          if (index >= 0) {
            _messages[index] = message;
          } else if (message.role == MessageRole.user) {
            final localIndex = _matchingPendingLocalMessageIndex(message);
            if (localIndex >= 0) {
              final localMessageId = _messages[localIndex].id;
              _localMessageStates.remove(localMessageId);
              _messages[localIndex] = message;
            } else {
              _messages.add(message);
            }
          } else {
            _messages.add(message);
          }
          if (message.role != MessageRole.system) {
            _session = _session.copyWith(
              updatedAt: message.createdAt,
              lastMessagePreview: message.content,
            );
          }
        });
        if (message.role != MessageRole.system) {
          _syncSessionSummaryCache();
        }
        if (message.role == MessageRole.assistant) {
          _maybeAutoSpeakAssistantMessage(message.id);
          _maybeNotifyAssistantMessage(message.id);
        }
        if (shouldAutoScroll) {
          _animateToBottom();
        }
        break;
      case 'message_delta':
        final shouldAutoScroll = _isNearBottom();
        final messageId = payload['message_id'] as String;
        final delta = payload['delta'] as String;
        setState(() {
          final index = _messages.indexWhere((item) => item.id == messageId);
          if (index >= 0) {
            _messages[index] = _messages[index].copyWith(
              content: '${_messages[index].content}$delta',
            );
          } else {
            _messages.add(
              ChatMessage(
                id: messageId,
                sessionId: _session.id,
                role: MessageRole.assistant,
                content: delta,
                createdAt: DateTime.now(),
              ),
            );
          }
        });
        _maybeAutoSpeakAssistantMessage(messageId);
        _maybeNotifyAssistantMessage(messageId);
        if (shouldAutoScroll) {
          _jumpToBottom();
        }
        break;
      case 'agent_error':
        setState(() {
          _speechError = payload['message'] as String;
        });
        break;
      case 'approval_requested':
        final approval = ApprovalRequest.fromJson(
            payload['request'] as Map<String, dynamic>);
        debugPrint(
          '[approval] requested session=${_session.id} request=${approval.requestId} '
          'kind=${approval.kind} resolvable=${approval.resolvable}',
        );
        setState(() {
          _pendingApproval = approval;
          _session = _session.copyWith(
            status: SessionStatus.awaitingApproval,
            updatedAt: DateTime.now(),
            pendingApproval: approval,
          );
          _reconcileSubmittedApprovalState();
        });
        _syncSessionSummaryCache();
        break;
      case 'approval_resolved':
        final requestId = payload['request_id'] as String? ?? '';
        debugPrint(
          '[approval] resolved session=${_session.id} request=$requestId '
          'choice=${payload["choice"]}',
        );
        setState(() {
          _pendingApproval = null;
          _session = _session.copyWith(
            status: SessionStatus.running,
            updatedAt: DateTime.now(),
            clearPendingApproval: true,
          );
          _submittedApprovalRequestId = null;
          _submittingApproval = false;
          _submittingApprovalChoice = null;
          _speechError = null;
        });
        _syncSessionSummaryCache();
        break;
    }
  }

  Future<void> _submitApproval(String choice) async {
    final approval = _pendingApproval;
    if (approval == null || _submittingApproval) {
      return;
    }

    setState(() {
      _submittingApproval = true;
      _submittingApprovalChoice = choice;
      _speechError = null;
    });

    try {
      debugPrint(
        '[approval] submit session=${_session.id} request=${approval.requestId} '
        'choice=$choice',
      );
      await _client.submitApproval(_session.id, approval.requestId, choice);
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingApproval = null;
        _session = _session.copyWith(
          updatedAt: DateTime.now(),
          clearPendingApproval: true,
        );
        _submittingApproval = false;
        _submittingApprovalChoice = null;
        _submittedApprovalRequestId = approval.requestId;
        _speechError = null;
      });
      _syncSessionSummaryCache();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submittingApproval = false;
        _submittingApprovalChoice = null;
        _submittedApprovalRequestId = null;
        _speechError = context.l10n.approvalSubmitFailed('$error');
      });
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      final useSystemSpeech =
          appSettingsController.settings.asrProvider == AsrProvider.system;
      if (useSystemSpeech) {
        _systemAsrUnavailable = false;
        try {
          final ready = await _speechInputService.initialize(
            onStatus: (status) {
              if (!mounted) {
                return;
              }
              if (status == 'done' || status == 'notListening') {
                setState(() {
                  _isListening = false;
                });
              }
            },
            onError: (error, permanent) {
              if (!mounted) {
                return;
              }
              setState(() {
                _isListening = false;
                _speechError = context.l10n.voiceTranscriptionFailed(error);
              });
              if (permanent || kIsWeb) {
                _systemAsrUnavailable = true;
              }
            },
          ).timeout(const Duration(seconds: 6));
          if (ready) {
            _systemAsrLocaleId = await _resolveSystemAsrLocaleId();
            if (!mounted) {
              return;
            }
            setState(() {
              _speechReady = true;
              if (_speechStatus == _systemSpeechUnavailableLabel()) {
                _speechStatus = null;
              }
              _speechError = null;
            });
            return;
          }
          _systemAsrUnavailable = true;
        } catch (_) {
          _systemAsrUnavailable = true;
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _systemAsrLocaleId = null;
          _speechReady = false;
          _speechStatus = _systemSpeechUnavailableLabel();
          _speechError = null;
        });
        return;
      }
      _systemAsrLocaleId = null;
      final ready = await _audioRecordingService.hasPermission().timeout(
            const Duration(seconds: 6),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _speechReady = ready;
        _speechStatus = ready ? null : context.l10n.microphonePermissionMissing;
        _speechError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
        _speechError = context.l10n.voiceInputInitFailed('$error');
      });
    }
  }

  Future<void> _initializeTts() async {
    try {
      await _ttsService.initialize(
        onStart: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = true;
            _clearTransientTtsStatus();
          });
        },
        onComplete: () {
          final resumeCallMode = _callModeAwaitingPlaybackCompletion;
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
            _callModeAwaitingPlaybackCompletion = false;
            _clearTransientTtsStatus();
          });
          if (resumeCallMode) {
            unawaited(_maybeResumeCallModeListening());
          }
        },
        onCancel: () {
          final resumeCallMode = _callModeAwaitingPlaybackCompletion;
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
            _callModeAwaitingPlaybackCompletion = false;
            _clearTransientTtsStatus();
          });
          if (resumeCallMode) {
            unawaited(_maybeResumeCallModeListening());
          }
        },
        onError: (message) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
            _callModeAwaitingPlaybackCompletion = false;
            _speechError = context.l10n.ttsFailed(message);
          });
        },
      ).timeout(const Duration(seconds: 6));

      if (!mounted) {
        return;
      }
      final provider = appSettingsController.settings.ttsProvider;
      setState(() {
        _ttsReady = provider == TtsProvider.system
            ? _ttsService.isSystemTtsAvailable
            : true;
        if (!_ttsReady && provider == TtsProvider.system) {
          _speechStatus = _systemSpeechUnavailableLabel();
          _speechError = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ttsReady = false;
        _speechError = context.l10n.ttsInitFailed('$error');
      });
    }
  }

  Future<void> _toggleListening() async {
    final useSystemSpeech = _useSystemSpeech();
    final useTencentStreaming =
        appSettingsController.settings.asrProvider ==
        AsrProvider.tencentCloudStreaming;
    if (!_speechReady) {
      setState(() {
        _speechStatus = context.l10n.reinitializingVoiceInput;
        _speechError = null;
      });
      await _initializeSpeech();
      if (!_speechReady) {
        return;
      }
    }

    if (_isListening) {
      if (useSystemSpeech) {
        await _stopSystemListening();
      } else if (useTencentStreaming) {
        await _stopTencentCloudStreamingAsr();
      } else {
        await _stopRecordingAndTranscribe();
      }
      return;
    }

    setState(() {
      _speechError = null;
      _speechStatus = context.l10n.voiceInputInProgress;
      _isListening = true;
      _recognizedSpeech = '';
    });

    try {
      if (useSystemSpeech) {
        await _speechInputService.startListening(
          localeId: _systemAsrLocaleId,
          onResult: (words, isFinal) {
            if (!mounted) {
              return;
            }
            setState(() {
              _recognizedSpeech = words;
              _controller.text = words;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
              if (isFinal) {
                _speechStatus = context.l10n.voiceTranscriptionComplete;
                _speechError = null;
              }
            });
            if (isFinal && _callModeEnabled) {
              unawaited(
                _handleCallModeTranscript(words, stopListeningFirst: true),
              );
            }
          },
        );
      } else if (useTencentStreaming) {
        await _startTencentCloudStreamingAsr();
      } else {
        _recordingPath = await _audioRecordingService.start();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _speechError = context.l10n.startVoiceInputFailed('$error');
      });
    }
  }

  Future<void> _stopSystemListening() async {
    try {
      await _speechInputService.stopListening();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _speechError = context.l10n.stopVoiceInputFailed('$error');
      });
      return;
    }
    await _finalizeSystemTranscript(
      _recognizedSpeech,
      autoSend: _callModeEnabled,
    );
  }

  Future<String?> _resolveSystemAsrLocaleId() async {
    final locale = preferredLocaleFromSetting(
      appSettingsController.settings.appLanguage,
    );
    final targetLocaleId = _localeIdFor(locale);
    final availableLocales = await _speechInputService.availableLocales();
    if (availableLocales.isEmpty) {
      return targetLocaleId;
    }

    String? exactMatch;
    String? languageMatch;
    for (final available in availableLocales) {
      final normalized = _normalizeLocaleId(available.localeId);
      if (normalized == _normalizeLocaleId(targetLocaleId)) {
        exactMatch = available.localeId;
        break;
      }
      if (languageMatch == null &&
          normalized.startsWith(locale.languageCode.toLowerCase())) {
        languageMatch = available.localeId;
      }
    }
    return exactMatch ?? languageMatch ?? availableLocales.first.localeId;
  }

  String? _localeIdFor(Locale locale) {
    final countryCode = locale.countryCode;
    if (countryCode == null || countryCode.trim().isEmpty) {
      return locale.languageCode;
    }
    return '${locale.languageCode}_${countryCode.trim().toUpperCase()}';
  }

  String _normalizeLocaleId(String? localeId) {
    return (localeId ?? '').trim().replaceAll('-', '_').toLowerCase();
  }

  bool _useSystemSpeech() {
    return appSettingsController.settings.asrProvider == AsrProvider.system &&
        !_systemAsrUnavailable;
  }

  bool _supportsCallModeAsrProvider() {
    final provider = appSettingsController.settings.asrProvider;
    return provider == AsrProvider.system ||
        provider == AsrProvider.tencentCloudStreaming;
  }

  bool _usesSystemSpeechForCallMode() {
    return appSettingsController.settings.asrProvider == AsrProvider.system;
  }

  Future<void> _stopRecordingAndTranscribe() async {
    String? path;
    try {
      path = await _audioRecordingService.stop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _speechError = context.l10n.stopVoiceInputFailed('$error');
      });
      return;
    }

    final filePath = path ?? _recordingPath;
    _recordingPath = null;

    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
      _speechStatus = context.l10n.uploadingAudio;
    });

    if (filePath == null) {
      setState(() {
        _speechError = context.l10n.recordingFileMissing;
      });
      return;
    }

    try {
      final text = await cloudSpeechService.transcribeAudio(File(filePath));
      await _cleanupRecordingFile(filePath);
      if (!mounted) {
        return;
      }
      setState(() {
        _controller.text = text;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        _speechStatus = context.l10n.voiceTranscriptionComplete;
        _speechError = null;
      });
    } catch (error) {
      await _cleanupRecordingFile(filePath);
      if (!mounted) {
        return;
      }
      setState(() {
        _speechError = context.l10n.voiceTranscriptionFailed('$error');
      });
    }
  }

  Future<void> _cleanupRecordingFile(String filePath) async {
    try {
      await File(filePath).delete();
    } catch (_) {
      // Best-effort cleanup for temporary recordings.
    }
  }

  Future<void> _speakMessage(String content) async {
    await _speakMessageInternal(content, resumeCallModeOnComplete: false);
  }

  Future<void> _speakMessageInternal(
    String content, {
    required bool resumeCallModeOnComplete,
  }) async {
    if (!_ttsReady) {
      setState(() {
        _speechStatus = context.l10n.reinitializingTts;
        _speechError = null;
      });
      await _initializeTts();
      if (!_ttsReady) {
        return;
      }
    }

    setState(() {
      _speechError = null;
      _callModeAwaitingPlaybackCompletion = resumeCallModeOnComplete;
      _clearTransientTtsStatus();
    });
    try {
      await _ttsService.speak(content);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _callModeAwaitingPlaybackCompletion = false;
        if (resumeCallModeOnComplete) {
          _callModeEnabled = false;
        }
        _speechError = context.l10n.ttsPlaybackFailed('$error');
      });
    }
  }

  bool _maybeAutoSpeakAssistantMessage(String messageId) {
    final shouldAutoSpeak =
        _callModeEnabled || appSettingsController.settings.autoSpeakReplies;
    if (!shouldAutoSpeak || _isSpeaking) {
      return false;
    }
    if (!_callModeEnabled && !_ttsReady) {
      return false;
    }
    final message = _messages
        .where((item) =>
            item.id == messageId && item.role == MessageRole.assistant)
        .cast<ChatMessage?>()
        .firstWhere((_) => true, orElse: () => null);
    if (message == null) {
      return false;
    }
    final content = message.content.trim();
    if (content.isEmpty || _autoSpokenAssistantMessageIds.contains(messageId)) {
      return false;
    }
    if (_session.status == SessionStatus.running) {
      return false;
    }
    _autoSpokenAssistantMessageIds.add(messageId);
    unawaited(
      _speakMessageInternal(
        content,
        resumeCallModeOnComplete: _callModeEnabled,
      ),
    );
    return true;
  }

  void _maybeNotifyAssistantMessage(String messageId) {
    if (_appInForeground) {
      return;
    }
    final message = _messages
        .where((item) =>
            item.id == messageId && item.role == MessageRole.assistant)
        .cast<ChatMessage?>()
        .firstWhere((_) => true, orElse: () => null);
    if (message == null) {
      return;
    }
    final content = message.content.trim();
    if (content.isEmpty || _notifiedAssistantMessageIds.contains(messageId)) {
      return;
    }
    if (_session.status == SessionStatus.running) {
      return;
    }
    _notifiedAssistantMessageIds.add(messageId);
    unawaited(
      notificationService.showAssistantReplyNotification(
        _session.copyWith(
          updatedAt: message.createdAt,
          lastMessagePreview: content,
        ),
        content,
      ),
    );
  }

  Future<void> _stopSpeaking() async {
    await _ttsService.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _isSpeaking = false;
    });
  }

  KeyEventResult _handleMessageInputKeyEvent(FocusNode _, KeyEvent event) {
    final isEnterKey = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnterKey || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (_isMessageInputComposing) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    unawaited(_sendTextMessage());
    return KeyEventResult.handled;
  }

  Future<void> _sendTextMessage() async {
    if (_creatingSession) {
      setState(() {
        _speechError = context.l10n.sessionStillCreating;
      });
      return;
    }
    if (_session.status == SessionStatus.running) {
      setState(() {
        _speechError = context.l10n.sessionStillRunning;
      });
      return;
    }

    final content = _controller.text.trim();
    if (content.isEmpty) {
      setState(() {
        _speechError = context.l10n.messageInputRequired;
      });
      return;
    }

    final inputMode = _speechStatus == context.l10n.voiceTranscriptionComplete
        ? 'voice'
        : 'text';
    await _submitLocalMessage(content, inputMode: inputMode);
  }

  Future<void> _retryLocalMessage(String messageId) async {
    final draft = _localMessageStates[messageId];
    final message = _messages
        .where((item) => item.id == messageId)
        .cast<ChatMessage?>()
        .firstWhere((_) => true, orElse: () => null);
    if (draft == null || message == null) {
      return;
    }
    await _submitLocalMessage(
      message.content,
      inputMode: draft.inputMode,
      localMessageId: messageId,
    );
  }

  Future<bool> _submitLocalMessage(
    String content, {
    required String inputMode,
    String? localMessageId,
  }) async {
    final messageId =
        localMessageId ?? 'local-${DateTime.now().microsecondsSinceEpoch}';
    final localMessage = ChatMessage(
      id: messageId,
      sessionId: _session.id,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    setState(() {
      _speechError = null;
      if (localMessageId == null) {
        _controller.clear();
        _messages.add(localMessage);
      } else {
        final index = _messages.indexWhere((item) => item.id == localMessageId);
        if (index >= 0) {
          _messages[index] = localMessage;
        }
      }
      _localMessageStates[messageId] = _LocalMessageDraft(
        state: _LocalMessageState.pending,
        inputMode: inputMode,
      );
    });
    _jumpToBottom();

    try {
      final result = await _client.sendMessage(
        _session.id,
        content,
        inputMode: inputMode,
      );
      if (!mounted) {
        return false;
      }
      setState(() {
        _localMessageStates.remove(messageId);
        final localIndex = _messages.indexWhere((item) => item.id == messageId);
        if (localIndex >= 0) {
          final existingUserIndex = _messages.indexWhere(
            (item) => item.id == result.userMessage.id,
          );
          if (existingUserIndex >= 0 && existingUserIndex != localIndex) {
            _messages.removeAt(localIndex);
          } else {
            _messages[localIndex] = result.userMessage;
          }
        } else {
          final existingUserIndex = _messages.indexWhere(
            (item) => item.id == result.userMessage.id,
          );
          if (existingUserIndex >= 0) {
            _messages[existingUserIndex] = result.userMessage;
          } else {
            _messages.add(result.userMessage);
          }
        }

        final replyIndex =
            _messages.indexWhere((item) => item.id == result.reply.id);
        if (replyIndex >= 0) {
          _messages[replyIndex] = result.reply;
        } else {
          _messages.add(result.reply);
        }
        _session = _session.copyWith(
          status: SessionStatus.running,
          updatedAt: result.userMessage.createdAt,
          lastMessagePreview: result.userMessage.content,
          clearPendingApproval: true,
        );
      });
      _syncSessionSummaryCache();
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _localMessageStates[messageId] = _LocalMessageDraft(
          state: _LocalMessageState.failed,
          inputMode: inputMode,
        );
        _speechError = error.toString().contains('already processing a message')
            ? context.l10n.sessionStillRunning
            : context.l10n.sendFailed('$error');
      });
      return false;
    }
  }

  int _matchingPendingLocalMessageIndex(ChatMessage serverMessage) {
    if (serverMessage.role != MessageRole.user) {
      return -1;
    }

    return _messages.indexWhere((item) {
      final draft = _localMessageStates[item.id];
      return draft != null &&
          item.role == MessageRole.user &&
          item.sessionId == serverMessage.sessionId &&
          item.content == serverMessage.content;
    });
  }

  Future<void> _cancelReply() async {
    if (_creatingSession || _cancellingReply) {
      return;
    }
    setState(() {
      _cancellingReply = true;
      _speechError = null;
    });
    try {
      await _client.cancelReply(_session.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _cancellingReply = false;
        _pendingApproval = null;
        _submittingApproval = false;
        _submittingApprovalChoice = null;
        _speechError = null;
        _speechStatus = context.l10n.replyStopped;
        _session = _session.copyWith(
          status: SessionStatus.idle,
          updatedAt: DateTime.now(),
          clearPendingApproval: true,
        );
      });
      _syncSessionSummaryCache();
      if (_callModeEnabled) {
        unawaited(_maybeResumeCallModeListening());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cancellingReply = false;
        _speechError = null;
      });
      unawaited(_restoreSessionAfterResume());
    }
  }

  Future<void> _enableCallMode() async {
    if (_callModeUnavailableMessage != null) {
      return;
    }
    setState(() {
      _callModeEnabled = true;
      _callModeAwaitingPlaybackCompletion = false;
      _speechError = null;
    });
    await _maybeResumeCallModeListening();
  }

  Future<void> _disableCallMode() async {
    final shouldCancelListening = _isListening && _useSystemSpeech();
    final shouldCancelStreaming = _streamingAsrActive;
    setState(() {
      _callModeEnabled = false;
      _callModeAwaitingPlaybackCompletion = false;
    });
    if (shouldCancelStreaming) {
      await _stopTencentCloudStreamingAsr();
    }
    if (shouldCancelListening) {
      try {
        await _speechInputService.cancel();
      } catch (_) {
        // Best effort; disabling call mode should not surface a second error.
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _recognizedSpeech = '';
      });
    }
  }

  Future<void> _maybeResumeCallModeListening() async {
    if (!_callModeEnabled ||
        _callModeAwaitingPlaybackCompletion ||
        _creatingSession ||
        !_appInForeground ||
        _session.status == SessionStatus.running ||
        _session.status == SessionStatus.awaitingApproval ||
        _pendingApproval != null ||
        _isListening ||
        _isSpeaking ||
        _systemTranscriptCompleting ||
        _streamingAsrActive ||
        _controller.text.trim().isNotEmpty ||
        _callModeUnavailableMessage != null) {
      return;
    }

    if (_usesSystemSpeechForCallMode()) {
      await _toggleListening();
    } else {
      await _startTencentCloudStreamingAsr();
    }
    if (!mounted) {
      return;
    }
    if (_callModeEnabled &&
        !_isListening &&
        _session.status == SessionStatus.idle) {
      setState(() {
        _callModeEnabled = false;
        _callModeAwaitingPlaybackCompletion = false;
      });
    }
  }

  Future<void> _handleCallModeTranscript(
    String transcript, {
    required bool stopListeningFirst,
  }) async {
    if (_systemTranscriptCompleting) {
      return;
    }
    _systemTranscriptCompleting = true;
    try {
      if (stopListeningFirst) {
        try {
          await _speechInputService.stopListening();
        } catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isListening = false;
            _callModeEnabled = false;
            _callModeAwaitingPlaybackCompletion = false;
            _speechError = context.l10n.stopVoiceInputFailed('$error');
          });
          return;
        }
      }
      final submitted = await _finalizeSystemTranscript(
        transcript,
        autoSend: true,
      );
      if (!mounted || submitted) {
        return;
      }
      setState(() {
        _callModeEnabled = false;
        _callModeAwaitingPlaybackCompletion = false;
      });
    } finally {
      _systemTranscriptCompleting = false;
    }
  }

  Future<bool> _finalizeSystemTranscript(
    String transcript, {
    required bool autoSend,
  }) async {
    final trimmedTranscript = transcript.trim();
    _recognizedSpeech = '';
    if (!mounted) {
      return false;
    }
    if (trimmedTranscript.isEmpty) {
      setState(() {
        _isListening = false;
        _speechError = context.l10n.voiceTranscriptionNoResult;
      });
      if (autoSend) {
        unawaited(_maybeResumeCallModeListening());
      }
      return false;
    }

    setState(() {
      _isListening = false;
      _controller.text = trimmedTranscript;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _speechStatus = context.l10n.voiceTranscriptionComplete;
      _speechError = null;
    });

    if (!autoSend) {
      return true;
    }
    return _submitLocalMessage(trimmedTranscript, inputMode: 'voice');
  }

  Future<void> _startTencentCloudStreamingAsr() async {
    if (_streamingAsrActive) {
      return;
    }
    if (!_speechReady) {
      setState(() {
        _speechStatus = context.l10n.reinitializingVoiceInput;
        _speechError = null;
      });
      await _initializeSpeech();
      if (!_speechReady) {
        return;
      }
    }

    setState(() {
      _speechError = null;
      _speechStatus = context.l10n.voiceInputInProgress;
      _isListening = true;
      _streamingAsrActive = true;
      _recognizedSpeech = '';
    });

    try {
      debugPrint('[call-mode] starting Tencent streaming ASR');
      final audioStream = await _audioRecordingService.startStream();
      await _tencentCloudStreamingAsrService.start(
        audioStream: audioStream,
        languageTag: preferredLocaleTagFromSetting(
          appSettingsController.settings.appLanguage,
        ),
        onUtterance: (utterance) {
          debugPrint(
            '[call-mode] utterance final=${utterance.isFinal} text=${utterance.text}',
          );
          if (!mounted) {
            return;
          }
          setState(() {
            _recognizedSpeech = utterance.text;
            _controller.text = utterance.text;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
            if (utterance.isFinal) {
              _speechStatus = context.l10n.voiceTranscriptionComplete;
              _speechError = null;
            }
          });
          if (utterance.isFinal && _callModeEnabled) {
            unawaited(_handleTencentCloudFinalUtterance(utterance.text));
          }
        },
        onError: (error) {
          debugPrint('[call-mode] Tencent ASR error: $error');
          if (!mounted) {
            return;
          }
          setState(() {
            _isListening = false;
            _streamingAsrActive = false;
            _callModeEnabled = false;
            _callModeAwaitingPlaybackCompletion = false;
            _speechError = context.l10n.voiceTranscriptionFailed(error);
          });
        },
      );
    } catch (error) {
      debugPrint('[call-mode] failed to start Tencent ASR: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _streamingAsrActive = false;
        _speechError = context.l10n.startVoiceInputFailed('$error');
      });
    }
  }

  Future<void> _stopTencentCloudStreamingAsr() async {
    await _tencentCloudStreamingAsrService.cancel();
    await _audioRecordingService.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
      _streamingAsrActive = false;
      _recognizedSpeech = '';
      if (!_callModeEnabled) {
        _speechStatus = null;
      }
    });
  }

  Future<void> _handleTencentCloudFinalUtterance(String transcript) async {
    await _stopTencentCloudStreamingAsr();
    final submitted = await _finalizeSystemTranscript(
      transcript,
      autoSend: true,
    );
    if (!mounted || submitted) {
      return;
    }
    setState(() {
      _callModeEnabled = false;
      _callModeAwaitingPlaybackCompletion = false;
    });
  }

  List<_ConversationTurn> get _turns {
    final turns = <_ConversationTurn>[];
    _ConversationTurn? currentTurn;
    for (final message in _messages) {
      if (message.role == MessageRole.user) {
        currentTurn = _ConversationTurn(id: message.id, userMessage: message);
        turns.add(currentTurn);
        continue;
      }

      currentTurn ??= _ConversationTurn(id: 'orphan-${message.id}');
      if (turns.isEmpty || !identical(turns.last, currentTurn)) {
        turns.add(currentTurn);
      }

      if (message.role == MessageRole.system) {
        currentTurn.toolMessages.add(message);
      } else {
        currentTurn.assistantMessages.add(message);
      }
    }
    return turns;
  }

  String? get _activeTurnId {
    for (var index = _messages.length - 1; index >= 0; index -= 1) {
      final message = _messages[index];
      if (message.role == MessageRole.user) {
        return message.id;
      }
    }
    return null;
  }

  Future<void> _showAllSystemMessages(_ConversationTurn turn) async {
    final systemMessages = turn.toolMessages;
    if (systemMessages.isEmpty) {
      return;
    }
    final brightness = Theme.of(context).brightness;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelFor(brightness),
        title: Text(context.l10n.allToolActivity),
        content: SizedBox(
          width: 360,
          height: 420,
          child: ListView.separated(
            itemCount: systemMessages.length,
            itemBuilder: (context, index) => InkWell(
              onTap: () => _showToolMessageDetail(systemMessages[index]),
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.micro,
                  horizontal: AppSpacing.textStack,
                ),
                child: Text(
                  _toolMessagePreview(systemMessages[index]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ),
            separatorBuilder: (_, __) => Divider(
              height: 16,
              color: AppColors.outlineFor(brightness),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _unreadToolCounts.remove(turn.id);
              });
              Navigator.of(context).pop();
            },
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _showToolMessageDetail(ChatMessage message) async {
    final parsed = _parseToolMessage(message.content);
    final brightness = Theme.of(context).brightness;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panelFor(brightness),
        title: Text(context.l10n.toolActivityDetail),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: parsed == null
                ? SelectableText(
                    message.content,
                    style: const TextStyle(height: 1.5),
                  )
                : _buildStructuredToolDetail(parsed, message.content),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredToolDetail(
    _ParsedToolMessage parsed,
    String rawContent,
  ) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(context.l10n.detailType, parsed.kindLabel),
        if (parsed.phaseLabel != null)
          _detailRow(context.l10n.detailPhase, parsed.phaseLabel!),
        if (parsed.primary != null && parsed.primary!.isNotEmpty)
          parsed.primaryIsList
              ? _detailList(
                  parsed.primaryLabel ?? context.l10n.detailContent,
                  <String>[parsed.primary!, ...parsed.secondaryItems],
                )
              : _detailBlock(
                  parsed.primaryLabel ?? context.l10n.detailContent,
                  parsed.primary!,
                ),
        if (!parsed.primaryIsList && parsed.secondaryItems.isNotEmpty)
          _detailList(
            parsed.secondaryLabel ?? context.l10n.detailItems,
            parsed.secondaryItems,
          ),
        if (parsed.trailingNote != null && parsed.trailingNote!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.fieldGap),
          _detailRow(context.l10n.detailExtra, parsed.trailingNote!),
        ],
        const SizedBox(height: AppSpacing.block),
        Text(
          context.l10n.detailRawContent,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.mutedSoftFor(brightness),
          ),
        ),
        const SizedBox(height: AppSpacing.compact),
        SelectableText(
          rawContent,
          style: const TextStyle(height: 1.5),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.fieldGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.mutedSoftFor(brightness),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _detailBlock(String label, String value) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.mutedSoftFor(brightness),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.stackTight),
        SelectableText(value, style: const TextStyle(height: 1.5)),
      ],
    );
  }

  Widget _detailList(String label, List<String> items) {
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.mutedSoftFor(brightness),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.stackTight),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.stackTight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.stackTight),
                  child: Icon(
                    Icons.circle,
                    size: AppSpacing.stackTight,
                    color: AppColors.mutedSoftFor(brightness),
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                Expanded(
                  child: SelectableText(
                    item,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  _ParsedToolMessage? _parseToolMessage(String content) {
    final text = content.trim();
    if (!text.startsWith('[')) {
      return null;
    }
    final end = text.indexOf(']');
    if (end <= 1) {
      return null;
    }

    final tag = text.substring(1, end);
    final remainder = text.substring(end + 1).trim();

    if (tag.startsWith('command:')) {
      final phase = tag.split(':').skip(1).join(':');
      final exitMatch =
          RegExp(r'^(.*)\s+\(exit\s+(-?\d+)\)$').firstMatch(remainder);
      return _ParsedToolMessage(
        kindLabel: context.l10n.toolKindCommand,
        phaseLabel: _phaseLabel(phase),
        primaryLabel: context.l10n.toolPrimaryCommand,
        primary: exitMatch?.group(1)?.trim() ?? remainder,
        secondaryLabel: context.l10n.toolSecondaryResult,
        secondaryItems: exitMatch == null
            ? const []
            : [context.l10n.toolExitCode(exitMatch.group(2)!)],
      );
    }

    if (tag.startsWith('file:')) {
      final phase = tag.split(':').skip(1).join(':');
      final moreMatch = RegExp(r'\+(\d+)\s+more$').firstMatch(remainder);
      final cleanedRemainder = moreMatch == null
          ? remainder
          : remainder.substring(0, moreMatch.start).trim();
      final files = cleanedRemainder
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return _ParsedToolMessage(
        kindLabel: context.l10n.toolKindFile,
        phaseLabel: _phaseLabel(phase),
        primaryLabel: context.l10n.toolPrimaryFile,
        primary: files.isEmpty ? remainder : files.first,
        secondaryLabel: context.l10n.toolSecondaryOtherFiles,
        secondaryItems: files.length <= 1
            ? const []
            : files.skip(1).toList(growable: false),
        trailingNote: moreMatch == null
            ? null
            : context.l10n.toolMoreFiles(moreMatch.group(1)!),
      );
    }

    if (tag.startsWith('todo')) {
      final phase = tag.contains(':') ? tag.split(':').skip(1).join(':') : null;
      final countMatch =
          RegExp(r'^(.*)\((\d+)\s+items\)$').firstMatch(remainder);
      final body = countMatch?.group(1)?.trim() ?? remainder;
      final items = body
          .split('|')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return _ParsedToolMessage(
        kindLabel: context.l10n.toolKindTodo,
        phaseLabel: phase == null ? null : _phaseLabel(phase),
        primaryLabel: context.l10n.toolPrimaryTodoItems,
        primary: items.isEmpty ? remainder : items.first,
        secondaryLabel: context.l10n.toolSecondaryOtherItems,
        secondaryItems: items.length <= 1
            ? const []
            : items.skip(1).toList(growable: false),
        primaryIsList: true,
      );
    }

    if (tag == 'plan') {
      final countMatch =
          RegExp(r'^(.*)\((\d+)\s+steps\)$').firstMatch(remainder);
      final body = countMatch?.group(1)?.trim() ?? remainder;
      final steps = body
          .split('|')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return _ParsedToolMessage(
        kindLabel: context.l10n.toolKindPlan,
        primaryLabel: context.l10n.toolPrimarySteps,
        primary: steps.isEmpty ? remainder : steps.first,
        secondaryLabel: context.l10n.toolSecondaryOtherSteps,
        secondaryItems: steps.length <= 1
            ? const []
            : steps.skip(1).toList(growable: false),
        primaryIsList: true,
      );
    }

    if (tag.startsWith('debug:')) {
      return _ParsedToolMessage(
        kindLabel: context.l10n.toolKindDebug,
        primaryLabel: context.l10n.toolPrimaryIdentifier,
        primary: tag,
        secondaryLabel: context.l10n.toolSecondaryDetail,
        secondaryItems: remainder.isEmpty ? const [] : [remainder],
      );
    }

    final firstColon = tag.indexOf(':');
    if (firstColon > 0) {
      final kind = tag.substring(0, firstColon);
      final phase = tag.substring(firstColon + 1);
      return _ParsedToolMessage(
        kindLabel: _kindLabel(kind),
        phaseLabel: _phaseLabel(phase),
        primaryLabel: context.l10n.detailContent,
        primary: remainder,
      );
    }

    return _ParsedToolMessage(
      kindLabel: _kindLabel(tag),
      primaryLabel: context.l10n.detailContent,
      primary: remainder,
    );
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'command':
        return context.l10n.toolKindCommand;
      case 'file':
        return context.l10n.toolKindFile;
      case 'todo':
        return context.l10n.toolKindTodo;
      case 'plan':
        return context.l10n.toolKindPlan;
      case 'web':
      case 'search':
        return context.l10n.toolKindSearch;
      case 'fetch':
        return context.l10n.toolKindFetch;
      case 'reasoning':
        return context.l10n.toolKindReasoning;
      case 'thread':
        return context.l10n.toolKindThread;
      case 'turn':
        return context.l10n.toolKindTurn;
      case 'approval':
        return context.l10n.toolKindApproval;
      case 'mcp':
        return 'MCP';
      default:
        return kind;
    }
  }

  String _phaseLabel(String phase) {
    switch (phase) {
      case 'running':
        return context.l10n.phaseRunning;
      case 'completed':
      case 'complete':
      case 'done':
        return context.l10n.phaseCompleted;
      case 'started':
        return context.l10n.phaseStarted;
      default:
        return phase;
    }
  }

  String _displayContentForMessage(ChatMessage message) {
    return message.content;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    return false;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) <=
        _bottomAutoScrollThreshold;
  }

  void _maybeAutoScrollToBottom() {
    if (_isNearBottom()) {
      _jumpToBottom();
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _animateToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}

class _SessionMessagesSkeleton extends StatelessWidget {
  const _SessionMessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListView(
        padding: AppSpacing.blockPadding,
        children: const [
          _MessageBubbleSkeleton(
            alignment: Alignment.centerLeft,
            width: 236,
            lineWidths: [188, 144],
          ),
          SizedBox(height: AppSpacing.stack),
          _MessageBubbleSkeleton(
            alignment: Alignment.centerRight,
            width: 204,
            lineWidths: [132, 164],
            emphasized: true,
          ),
          SizedBox(height: AppSpacing.stack),
          _MessageBubbleSkeleton(
            alignment: Alignment.centerLeft,
            width: 262,
            lineWidths: [214, 190, 124],
          ),
          SizedBox(height: AppSpacing.stack),
          _MessageBubbleSkeleton(
            alignment: Alignment.centerRight,
            width: 176,
            lineWidths: [124, 96],
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _MessageBubbleSkeleton extends StatelessWidget {
  const _MessageBubbleSkeleton({
    required this.alignment,
    required this.width,
    required this.lineWidths,
    this.emphasized = false,
  });

  final Alignment alignment;
  final double width;
  final List<double> lineWidths;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bubbleColor = emphasized
        ? AppColors.tintSurfaceFor(
            brightness,
            AppColors.accentBlueFor(brightness),
            darkAlpha: 0.18,
            lightAlpha: 0.10,
          )
        : AppColors.surfaceFor(brightness);
    final borderColor = emphasized
        ? AppColors.tintBorderFor(
            brightness,
            AppColors.accentBlueFor(brightness),
          )
        : AppColors.outlineFor(brightness);

    return Align(
      alignment: alignment,
      child: Container(
        width: width,
        padding: AppSpacing.tilePadding,
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusTile),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < lineWidths.length; index++) ...[
              AppSkeletonBlock(width: lineWidths[index], height: 10),
              if (index < lineWidths.length - 1)
                const SizedBox(height: AppSpacing.textStack),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssistantCodeSyntaxHighlighter extends SyntaxHighlighter {
  _AssistantCodeSyntaxHighlighter(this.theme);

  final ThemeData theme;

  static final RegExp _tokenPattern = RegExp(
    r'''(?<comment>//.*$|#.*$)|(?<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?<keyword>\b(?:abstract|async|await|break|case|catch|class|const|continue|def|default|else|enum|export|extends|false|final|finally|for|from|function|if|import|in|interface|let|new|null|override|print|return|static|super|switch|this|throw|true|try|var|void|while|with|yield)\b)|(?<number>\b\d+(?:\.\d+)?\b)''',
    multiLine: true,
  );

  @override
  TextSpan format(String source) {
    final brightness = theme.brightness;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textFor(brightness),
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 14) * 0.93,
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const <String>['monospace'],
      height: 1.55,
      letterSpacing: 0.1,
    );
    final commentStyle = baseStyle?.copyWith(
      color: AppColors.mutedSoftFor(brightness),
      fontStyle: FontStyle.italic,
    );
    final stringStyle = baseStyle?.copyWith(
      color: brightness == Brightness.dark
          ? const Color(0xFFFFC47A)
          : const Color(0xFF9A5200),
    );
    final keywordStyle = baseStyle?.copyWith(
      color: brightness == Brightness.dark
          ? const Color(0xFF8ED0FF)
          : const Color(0xFF005CC5),
      fontWeight: FontWeight.w700,
    );
    final numberStyle = baseStyle?.copyWith(
      color: brightness == Brightness.dark
          ? const Color(0xFFB7F287)
          : const Color(0xFF2F7D32),
    );

    final spans = <TextSpan>[];
    var currentIndex = 0;
    for (final match in _tokenPattern.allMatches(source)) {
      if (match.start > currentIndex) {
        spans.add(
          TextSpan(
            text: source.substring(currentIndex, match.start),
            style: baseStyle,
          ),
        );
      }

      final token = match.group(0)!;
      TextStyle? style = baseStyle;
      if (match.namedGroup('comment') != null) {
        style = commentStyle;
      } else if (match.namedGroup('string') != null) {
        style = stringStyle;
      } else if (match.namedGroup('keyword') != null) {
        style = keywordStyle;
      } else if (match.namedGroup('number') != null) {
        style = numberStyle;
      }

      spans.add(TextSpan(text: token, style: style));
      currentIndex = match.end;
    }

    if (currentIndex < source.length) {
      spans.add(
        TextSpan(text: source.substring(currentIndex), style: baseStyle),
      );
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

enum _LocalMessageState { pending, failed }

class _LocalMessageDraft {
  const _LocalMessageDraft({
    required this.state,
    required this.inputMode,
  });

  final _LocalMessageState state;
  final String inputMode;

  String label(BuildContext context) {
    return switch (state) {
      _LocalMessageState.pending => context.l10n.draftPending,
      _LocalMessageState.failed => context.l10n.draftFailed,
    };
  }
}

class _ConversationTurn {
  _ConversationTurn({required this.id, this.userMessage});

  final String id;
  final ChatMessage? userMessage;
  final List<ChatMessage> assistantMessages = <ChatMessage>[];
  final List<ChatMessage> toolMessages = <ChatMessage>[];
}

class _CallModeOrbPainter extends CustomPainter {
  const _CallModeOrbPainter({
    required this.progress,
    required this.intensity,
    required this.brightness,
  });

  final double progress;
  final double intensity;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    _paintBlob(
      canvas,
      size,
      center: center.translate(
        _wave(0.0, 20, 38),
        _wave(0.18, -18, 22),
      ),
      radiusX: size.width * (0.30 + (0.03 * _wave01(0.12))),
      radiusY: size.height * (0.24 + (0.04 * _wave01(0.44))),
      rotation: _wave(0.0, -0.36, 0.52),
      colorA: const Color(0xFFFFC0DE).withValues(alpha: 0.68),
      colorB: const Color(0xFFC5A1FF).withValues(alpha: 0.22),
    );
    _paintBlob(
      canvas,
      size,
      center: center.translate(
        _wave(0.36, -34, 24),
        _wave(0.58, 10, 28),
      ),
      radiusX: size.width * (0.23 + (0.04 * _wave01(0.28))),
      radiusY: size.height * (0.22 + (0.03 * _wave01(0.76))),
      rotation: _wave(0.42, 0.58, -0.74),
      colorA: Colors.white.withValues(alpha: 0.18 + (0.06 * intensity)),
      colorB: const Color(0xFF7EA7FF).withValues(alpha: 0.10),
    );
    _paintBlob(
      canvas,
      size,
      center: center.translate(
        _wave(0.74, 12, 20),
        _wave(0.86, 30, -20),
      ),
      radiusX: size.width * (0.21 + (0.03 * _wave01(0.66))),
      radiusY: size.height * (0.24 + (0.04 * _wave01(0.18))),
      rotation: _wave(0.72, -0.24, 0.30),
      colorA: const Color(0xFFFFB2D2)
          .withValues(alpha: brightness == Brightness.dark ? 0.48 : 0.42),
      colorB: const Color(0xFF8C7CFF).withValues(alpha: 0.10),
    );
  }

  void _paintBlob(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double radiusX,
    required double radiusY,
    required double rotation,
    required Color colorA,
    required Color colorB,
  }) {
    final path = Path();
    final points = <Offset>[];
    final count = 7;
    for (var index = 0; index < count; index += 1) {
      final t = index / count;
      final angle = (math.pi * 2 * t) + rotation;
      final noise = 0.84 + (0.24 * _wave01(t + progress));
      final x = center.dx + math.cos(angle) * radiusX * noise;
      final y = center.dy + math.sin(angle) * radiusY * (1.0 + (0.18 * noise));
      points.add(Offset(x, y));
    }

    path.moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < count; index += 1) {
      final current = points[index];
      final next = points[(index + 1) % count];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.close();

    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          ((center.dx / size.width) * 2) - 1,
          ((center.dy / size.height) * 2) - 1,
        ),
        radius: 0.92,
        colors: [colorA, colorB, Colors.transparent],
        stops: const [0.0, 0.72, 1.0],
      ).createShader(Offset.zero & size)
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawPath(path, paint);
  }

  double _wave(double shift, double from, double to) {
    final value = math.sin((progress + shift) * math.pi * 2);
    final normalized = (value + 1) / 2;
    return from + ((to - from) * normalized);
  }

  double _wave01(double shift) {
    return (math.sin((progress + shift) * math.pi * 2) + 1) / 2;
  }

  @override
  bool shouldRepaint(covariant _CallModeOrbPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.brightness != brightness;
  }
}

class _ParsedToolMessage {
  const _ParsedToolMessage({
    required this.kindLabel,
    this.phaseLabel,
    this.primaryLabel,
    this.primary,
    this.secondaryLabel,
    this.secondaryItems = const <String>[],
    this.primaryIsList = false,
    this.trailingNote,
  });

  final String kindLabel;
  final String? phaseLabel;
  final String? primaryLabel;
  final String? primary;
  final String? secondaryLabel;
  final List<String> secondaryItems;
  final bool primaryIsList;
  final String? trailingNote;
}
