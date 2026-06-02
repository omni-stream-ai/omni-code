import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../message_image_paths.dart';
import '../models.dart';
import '../services/cloud_speech_service.dart';
import '../services/notification_service.dart';
import '../services/audio_recording_service.dart';
import '../services/bridge_realtime_asr_service.dart';
import '../services/speech_input_service.dart';
import '../services/tts_service.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_skeleton.dart';
import '../widgets/session_call_mode_view.dart';
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
    this.bridgeRealtimeAsrService,
  });

  static const routeName = '/session';

  final SessionSummary session;
  final Future<SessionSummary>? sessionInitializer;
  final BridgeClient? client;
  final bool enableSpeechServices;
  final AudioRecordingService? audioRecordingService;
  final SpeechInputService? speechInputService;
  final TtsService? ttsService;
  final BridgeRealtimeAsrService? bridgeRealtimeAsrService;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const double _bottomAutoScrollThreshold = 96;
  static const double _topHistoryExpandThreshold = 72;
  static const double _messageBubbleMaxWidth = 320;
  static const double _assistantMessageBubbleWidthFactor = 0.82;
  static const double _bridgeRealtimeEndpointRule2Ratio = 0.7;
  static const double _callModeSpeechHintDelayRatio = 0.55;
  static const Duration _callModeTtsEchoGracePeriod = Duration(seconds: 6);
  static const Duration _callModeCommandAcceptedSpeechTimeout =
      Duration(seconds: 4);
  static const int _initialVisibleTurnCount = 10;
  static const int _historyTurnBatchSize = 10;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final AudioRecordingService _audioRecordingService;
  late final SpeechInputService _speechInputService;
  late final TtsService _ttsService;
  late final BridgeRealtimeAsrService _bridgeRealtimeAsrService;
  final Set<String> _autoSpokenAssistantMessageIds = <String>{};
  final Set<String> _notifiedAssistantMessageIds = <String>{};
  final Map<String, _LocalMessageDraft> _localMessageStates = {};
  final Map<String, Future<BridgeFileResponse>> _imageFileFutures = {};
  late SessionSummary _session;
  final List<ChatMessage> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _eventsSubscription;
  Timer? _eventsReconnectTimer;
  late final AnimationController _callModeOrbController;
  Timer? _speechStatusAutoDismissTimer;
  Timer? _callModeSpeechHintTimer;
  Timer? _refreshSessionSummaryDebounce;
  bool _refreshSessionSummaryInFlight = false;

  String? _recordingPath;
  String _recognizedSpeech = '';
  bool _recognizedSpeechPendingSpeakerVerification = false;
  bool _recognizedSpeechRejectedSpeaker = false;
  bool _recognizedSpeechRejectedWakeWord = false;
  bool _recognizedSpeechRejectedOther = false;
  String? _systemAsrLocaleId;
  bool _systemAsrUnavailable = false;
  bool _loadingMessages = true;
  bool _speechReady = false;
  bool _ttsReady = false;
  bool _isListening = false;
  bool _voiceInputStarting = false;
  bool _isSpeaking = false;
  String? _speakingMessageId;
  bool _callModeEnabled = false;
  bool _callModeSubtitlesVisible = true;
  bool _callModeAwaitingPlaybackCompletion = false;
  String? _callModeSpokenReplyText;
  String? _callModeCurrentTtsText;
  String? _callModeRecentTtsText;
  DateTime? _callModeRecentTtsExpiresAt;
  bool _systemTranscriptCompleting = false;
  bool _streamingAsrActive = false;
  bool _callModeInterrupting = false;
  bool _callModeInterruptedCurrentReply = false;
  Future<void>? _callModeInterruptFuture;
  bool _callModeSubmittingVoiceUtterance = false;
  bool _callModeSendingVoiceUtterance = false;
  Completer<void>? _callModeCommandAcceptedSpeechCompleter;
  _CallModeSpeechHintState? _callModeSpeechHintState;
  final Map<String, int> _unreadToolCounts = <String, int>{};
  String? _speechStatus;
  String? _speechError;
  ApprovalRequest? _pendingApproval;
  bool _restoringSession = false;
  bool _expandingHistory = false;
  bool _appInForeground = true;
  bool _creatingSession = false;
  bool _submittingApproval = false;
  String? _submittingApprovalChoice;
  String? _submittedApprovalRequestId;
  bool _cancellingReply = false;
  int _visibleTurnCount = 0;
  String? _dismissedErrorBannerMessage;
  String? _overrideProviderId;
  List<ModelProviderConfig> _providers = const [];

  BridgeClient get _client => widget.client ?? bridgeClient;

  String _systemSpeechUnavailableLabel() =>
      context.l10n.systemSpeechUnavailable;
  String? get _systemSpeechUnavailableStatus =>
      _speechError == null && _speechStatus == _systemSpeechUnavailableLabel()
          ? _speechStatus
          : null;
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

  bool get _shouldShowErrorBanner {
    final message = _speechError?.trim();
    if (message == null || message.isEmpty) {
      _dismissedErrorBannerMessage = null;
      return false;
    }
    return message != _dismissedErrorBannerMessage;
  }

  bool _isAutoDismissableSpeechStatus(String? status) {
    return status == context.l10n.voiceTranscriptionComplete ||
        status == context.l10n.replyStopped;
  }

  bool _isMeaningfulVoiceTranscript(String transcript) {
    return _meaningfulVoiceTranscriptCharacterCount(transcript) >= 2;
  }

  bool _isSubstantialVoiceTranscript(String transcript) {
    return _meaningfulVoiceTranscriptCharacterCount(transcript) >= 3;
  }

  int _meaningfulVoiceTranscriptCharacterCount(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    var meaningfulCharacterCount = 0;
    for (final rune in trimmed.runes) {
      if (_isVoiceTranscriptMeaningfulRune(rune)) {
        meaningfulCharacterCount += 1;
      }
    }
    return meaningfulCharacterCount;
  }

  bool _isVoiceTranscriptMeaningfulRune(int rune) {
    return (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF);
  }

  void _syncSpeechStatusAutoDismiss() {
    _speechStatusAutoDismissTimer?.cancel();
    _speechStatusAutoDismissTimer = null;

    final status = _speechStatus;
    if (!mounted || !_isAutoDismissableSpeechStatus(status)) {
      return;
    }

    _speechStatusAutoDismissTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _speechStatus != status) {
        return;
      }
      setState(() {
        _setSpeechStatus(null);
      });
    });
  }

  void _setSpeechStatus(String? status) {
    _speechStatus = status;
    _syncSpeechStatusAutoDismiss();
  }

  void _clearRecognizedSpeechState() {
    _recognizedSpeech = '';
    _recognizedSpeechPendingSpeakerVerification = false;
    _recognizedSpeechRejectedSpeaker = false;
    _recognizedSpeechRejectedWakeWord = false;
    _recognizedSpeechRejectedOther = false;
  }

  void _resetBridgeRealtimeUtteranceGateState() {
    // Wake word gating is disabled.
  }

  void _dismissErrorBanner() {
    final message = _speechError?.trim();
    if (message == null || message.isEmpty) {
      return;
    }
    setState(() {
      _dismissedErrorBannerMessage = message;
    });
  }

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
      _setSpeechStatus(null);
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
    _bridgeRealtimeAsrService = widget.bridgeRealtimeAsrService ??
        BridgeRealtimeAsrService(client: _client);
    _session = widget.session;
    _overrideProviderId = _session.providerId;
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
    _loadProviders();
  }

  @override
  void dispose() {
    _callModeOrbController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _eventsSubscription?.cancel();
    _eventsReconnectTimer?.cancel();
    _speechStatusAutoDismissTimer?.cancel();
    _callModeSpeechHintTimer?.cancel();
    _refreshSessionSummaryDebounce?.cancel();
    _completeCallModeCommandAcceptedSpeech();
    unawaited(_audioRecordingService.cancel());
    unawaited(_speechInputService.cancel());
    unawaited(_bridgeRealtimeAsrService.cancel());
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

  Future<void> _loadProviders() async {
    try {
      final providers = await _client.getModelProviders();
      if (!mounted) return;
      final compatible = _session.agent.compatibleFormats;
      setState(() {
        _providers =
            providers.where((p) => compatible.contains(p.format)).toList();
      });
    } catch (_) {
      // Silently ignore — provider selector just won't show
    }
  }

  void _scheduleRefreshSessionSummary() {
    if (_creatingSession) {
      return;
    }
    _refreshSessionSummaryDebounce?.cancel();
    _refreshSessionSummaryDebounce = Timer(
      const Duration(milliseconds: 500),
      _refreshSessionSummaryFromBridge,
    );
  }

  Future<void> _refreshSessionSummaryFromBridge() async {
    if (_creatingSession || _refreshSessionSummaryInFlight) {
      return;
    }
    _refreshSessionSummaryInFlight = true;
    try {
      final refreshedSession = await _client.getProjectSession(
        _session.projectId,
        _session.id,
        forceRefresh: true,
      );
      if (!mounted || refreshedSession.id != _session.id) {
        return;
      }
      setState(() {
        _session = refreshedSession;
        _pendingApproval = refreshedSession.pendingApproval;
        _reconcileSubmittedApprovalState();
      });
      _syncSessionSummaryCache();
    } catch (_) {
      // Best effort: message delivery should not surface title refresh errors.
    } finally {
      _refreshSessionSummaryInFlight = false;
    }
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
    final showHistoryLoader = _hasHiddenTurns || _expandingHistory;
    final approvalCardMaxHeight = MediaQuery.of(context).size.height * 0.36;
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
          _buildProviderSelector(),
          _buildCallModeAction(
            unavailableMessage: callModeUnavailableMessage,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_session.status == SessionStatus.failed)
            _buildErrorBanner(
              _resolveSessionErrorText(context.l10n),
              dismissable: false,
            )
          else if (_shouldShowErrorBanner)
            _buildErrorBanner(_speechError!.trim()),
          if (_pendingApproval != null)
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
                      itemCount: turns.length + (showHistoryLoader ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (showHistoryLoader) {
                          if (index == 0) {
                            return _buildHistoryLoader();
                          }
                          index -= 1;
                        }
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
                                        _voiceInputStarting ||
                                        (!_speechReady && !_isListening))
                                    ? null
                                    : _toggleListening,
                                child: _voiceInputStarting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
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

  Widget _buildCallModeScaffold(BuildContext context) {
    final l10n = context.l10n;
    final showVoiceInputStarting = _showVoiceInputStartingAsPrimary;
    final failedError = _session.status == SessionStatus.failed
        ? _resolveSessionErrorText(l10n)
        : null;
    final speechError = failedError ?? _speechError?.trim();
    final liveTranscript = _recognizedSpeech.trim().isNotEmpty
        ? _recognizedSpeech.trim()
        : _controller.text.trim();
    final spokenReplyPreview = _previewText(_callModeSpokenReplyText);
    final spokenReplyText = _callModeSpokenReplyText?.trim();
    final showingSpokenReplyMarkdown =
        spokenReplyText != null && spokenReplyText.isNotEmpty;
    final statusLine = _callModeStatusLine(l10n);
    final realtimeHint = _callModeRealtimeHint(l10n);
    final rawSubtitle = showVoiceInputStarting
        ? l10n.callModePreparingListening
        : showingSpokenReplyMarkdown
            ? spokenReplyText
            : liveTranscript.isNotEmpty
                ? liveTranscript
                : _session.status == SessionStatus.running
                    ? l10n.callModeWorking
                    : (spokenReplyPreview.isNotEmpty
                        ? spokenReplyPreview
                        : _callModeIdleSubtitle(l10n));
    final subtitle = liveTranscript.isNotEmpty
        ? _callModeRejectedTranscriptLabel(l10n, rawSubtitle)
        : rawSubtitle;
    return SessionCallModeView(
      voiceChatTitle: l10n.voiceChatTitle,
      statusText: statusLine,
      bodyText: subtitle,
      bodyTextMarkdown: showingSpokenReplyMarkdown,
      bodyTextMuted: _recognizedSpeechPendingSpeakerVerification ||
          _recognizedSpeechRejectedSpeaker ||
          _recognizedSpeechRejectedWakeWord ||
          _recognizedSpeechRejectedOther,
      realtimeHintLabel: realtimeHint?.label,
      realtimeHintDetail: realtimeHint?.detail,
      bannerText:
          speechError == null || speechError.isEmpty ? null : speechError,
      statusIsError: (speechError != null && speechError.isNotEmpty) ||
          _session.status == SessionStatus.failed,
      subtitlesVisible: _callModeSubtitlesVisible,
      subtitleToggleTooltip: _callModeSubtitlesVisible
          ? l10n.hideCallModeSubtitles
          : l10n.showCallModeSubtitles,
      closeTooltip: l10n.close,
      orbAnimation: _callModeOrbController,
      isStarting: showVoiceInputStarting,
      isListening: _isListening,
      isSpeaking: _isSpeaking || _callModeAwaitingPlaybackCompletion,
      isBusy: _session.status == SessionStatus.running,
      isLive: _isListening || _streamingAsrActive,
      onBackPressed: () => unawaited(_disableCallMode()),
      onSubtitleTogglePressed: _toggleCallModeSubtitles,
      onPrimaryPressed: () {
        if (_session.status == SessionStatus.running) {
          unawaited(_cancelReply());
          return;
        }
        final lastAssistantReply = _lastAssistantReplyText()?.trim();
        if (_callModeAllowInterruptions &&
            !_isSpeaking &&
            !_callModeAwaitingPlaybackCompletion &&
            lastAssistantReply != null &&
            lastAssistantReply.isNotEmpty &&
            lastAssistantReply != _callModeSpokenReplyText?.trim()) {
          unawaited(
            _speakMessageInternal(
              lastAssistantReply,
              resumeCallModeOnComplete: true,
            ),
          );
          return;
        }
        unawaited(_toggleListening());
      },
      onClosePressed: () => unawaited(_disableCallMode()),
    );
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
    if (_session.status == SessionStatus.failed) {
      final errorText = _resolveSessionErrorText(l10n);
      if (errorText != l10n.sessionFailedGeneric) {
        return errorText;
      }
    }
    if (_speechError != null && _speechError!.trim().isNotEmpty) {
      return _speechError!;
    }
    if (_showVoiceInputStartingAsPrimary) {
      return l10n.callModePreparingListening;
    }
    if (_session.status == SessionStatus.awaitingApproval) {
      return l10n.waitingApprovalProcessing;
    }
    if (_callModeSubmittingVoiceUtterance) {
      return l10n.callModeWorking;
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

  _CallModeRealtimeHint? _callModeRealtimeHint(AppLocalizations l10n) {
    if (_speechError != null && _speechError!.trim().isNotEmpty) {
      return null;
    }
    if (_showVoiceInputStartingAsPrimary) {
      return _CallModeRealtimeHint(
        label: l10n.callModePreparingListeningLabel,
        detail: l10n.callModePreparingListeningDetail,
      );
    }
    if (_session.status == SessionStatus.awaitingApproval ||
        _session.status == SessionStatus.running ||
        _callModeSubmittingVoiceUtterance ||
        _callModeAwaitingPlaybackCompletion ||
        _isSpeaking) {
      return null;
    }
    if (!_callModeEnabled) {
      return null;
    }
    final speechHintState = _callModeSpeechHintState;
    if (speechHintState == _CallModeSpeechHintState.speaking) {
      return _CallModeRealtimeHint(
        label: l10n.callModeSpeechDetectedLabel,
        detail: l10n.callModeSpeechDetectedDetail,
      );
    }
    if (speechHintState == _CallModeSpeechHintState.waitingForPause) {
      return _CallModeRealtimeHint(
        label: l10n.callModeWaitingForPauseLabel,
        detail: l10n.callModeWaitingForPauseDetail,
      );
    }
    if (_isListening || _streamingAsrActive) {
      return _CallModeRealtimeHint(
        label: l10n.callModeListeningReadyLabel,
        detail: l10n.callModeListeningReadyDetail,
      );
    }
    return null;
  }

  String _callModeIdleSubtitle(AppLocalizations l10n) {
    return l10n.callModeIdleSubtitle;
  }

  String _callModeRejectedTranscriptLabel(
    AppLocalizations l10n,
    String transcript,
  ) {
    if (_recognizedSpeechRejectedSpeaker) {
      return l10n.callModeRejectedSpeakerTranscript(transcript);
    }
    if (_recognizedSpeechRejectedWakeWord) {
      return l10n.callModeRejectedWakeWordTranscript(transcript);
    }
    return transcript;
  }

  bool get _showVoiceInputStartingAsPrimary {
    if (!_voiceInputStarting) {
      return false;
    }
    return _session.status != SessionStatus.running &&
        !_callModeAwaitingPlaybackCompletion &&
        !_isSpeaking;
  }

  void _toggleCallModeSubtitles() {
    if (!mounted) {
      return;
    }
    setState(() {
      _callModeSubtitlesVisible = !_callModeSubtitlesVisible;
    });
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

  Widget _buildProviderSelector() {
    if (_providers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final currentName = _overrideProviderId == null
        ? l10n.providerAuto
        : _providers
            .where((p) => p.id == _overrideProviderId)
            .firstOrNull
            ?.name ?? l10n.providerAuto;

    return PopupMenuButton<String?>(
      tooltip: l10n.providerOverride,
      onSelected: (value) {
        final previous = _overrideProviderId;
        setState(() {
          _overrideProviderId = value;
        });
        unawaited(
          _client.updateSessionProvider(_session.id, value).catchError((e) {
            debugPrint('[provider] updateSessionProvider failed: $e');
            if (!mounted) return;
            setState(() {
              _overrideProviderId = previous;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.providerOverrideFailed),
                duration: const Duration(seconds: 3),
              ),
            );
          }),
        );
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: null,
          child: Row(
            children: [
              if (_overrideProviderId == null)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: theme.colorScheme.tertiary,
                )
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(l10n.providerAuto),
            ],
          ),
        ),
        ..._providers.map(
          (p) => PopupMenuItem(
            value: p.id,
            child: Row(
              children: [
                if (_overrideProviderId == p.id)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: theme.colorScheme.tertiary,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(p.name)),
              ],
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 20,
              color: _overrideProviderId != null
                  ? theme.colorScheme.tertiary
                  : theme.iconTheme.color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                currentName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _overrideProviderId != null
                      ? theme.colorScheme.tertiary
                      : theme.textTheme.labelSmall?.color,
                  fontWeight: _overrideProviderId != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: theme.iconTheme.color,
            ),
          ],
        ),
      ),
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
    final isAwaitingResolution = _isAwaitingSubmittedApprovalResolution;
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final actions = isAwaitingResolution
                ? null
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
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
                        if (approval.allowAcceptForSession) ...[
                          const SizedBox(width: AppSpacing.compact),
                          OutlinedButton(
                            onPressed: approval.resolvable && !isSubmitting
                                ? () => _submitApproval('accept_for_session')
                                : null,
                            child: _buildApprovalButtonChild(
                              'accept_for_session',
                              context.l10n.approveForSession,
                            ),
                          ),
                        ],
                        const SizedBox(width: AppSpacing.compact),
                        OutlinedButton(
                          onPressed: approval.resolvable && !isSubmitting
                              ? () => _submitApproval('decline')
                              : null,
                          child: _buildApprovalButtonChild(
                            'decline',
                            context.l10n.reject,
                          ),
                        ),
                        if (approval.allowCancel) ...[
                          const SizedBox(width: AppSpacing.compact),
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
                      ],
                    ),
                  );
            final actionHeight = actions == null ? 0.0 : 48.0;
            final reservedHeight =
                22.0 + AppSpacing.compact + AppSpacing.stack + actionHeight;
            final detailsMaxHeight =
                math.max(0.0, constraints.maxHeight - reservedHeight);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n
                      .agentAwaitingPermission(_agentLabel(_session.agent)),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.warningTextFor(brightness),
                  ),
                ),
                const SizedBox(height: AppSpacing.compact),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: detailsMaxHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          summary,
                          style:
                              theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                        ),
                        if (isAwaitingResolution) ...[
                          const SizedBox(height: AppSpacing.compact),
                          Text(
                            context.l10n.waitingApprovalProcessing,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.warningTextFor(brightness),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
                if (actions != null) ...[
                  const SizedBox(height: AppSpacing.stack),
                  actions,
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Resolves the error text to display when a session has failed.
  /// Prefers [SessionSummary.errorMessage], falls back to
  /// [SessionSummary.lastMessagePreview] (which the server sets to the error
  /// message on failure), and finally to the generic localized string.
  String _resolveSessionErrorText(AppLocalizations l10n) {
    final errorMessage = _session.errorMessage;
    if (errorMessage != null && errorMessage.trim().isNotEmpty) {
      return errorMessage.trim();
    }
    final preview = _session.lastMessagePreview;
    if (preview != null && preview.trim().isNotEmpty) {
      return preview.trim();
    }
    return l10n.sessionFailedGeneric;
  }

  Widget _buildErrorBanner(String message, {bool dismissable = true}) {
    final brightness = Theme.of(context).brightness;
    return Container(
      key: ValueKey(dismissable
          ? 'session-error-banner'
          : 'session-failed-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.block,
        AppSpacing.block,
        AppSpacing.block,
        0,
      ),
      padding: AppSpacing.tilePadding,
      decoration: BoxDecoration(
        color: AppColors.errorBgFor(brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: AppColors.errorBorderFor(brightness)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(
                color: AppColors.errorTextFor(brightness),
                height: 1.4,
              ),
            ),
          ),
          if (dismissable) ...[
            const SizedBox(width: AppSpacing.compact),
            IconButton(
              tooltip: context.l10n.close,
              onPressed: _dismissErrorBanner,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.mutedSoftFor(brightness),
              ),
            ),
          ],
        ],
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

  Widget _buildHistoryLoader() {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.stack),
      child: Center(
        child: Container(
          key: const ValueKey('session-history-loader'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.tileX,
            vertical: AppSpacing.compact,
          ),
          decoration: BoxDecoration(
            color: AppColors.panelDeepFor(brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: AppColors.outlineFor(brightness)),
          ),
          child: _expandingHistory
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.expand_less_rounded,
                  size: 16,
                  color: AppColors.mutedSoftFor(brightness),
                ),
        ),
      ),
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
    final imageReferences = extractMessageImageReferences(message.content);
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
              _buildMarkdownMessageBody(
                message.content,
                textColor: bubbleTextColor,
                maxWidth: maxWidth,
                imageReferences: imageReferences,
                imageAlignment: Alignment.centerRight,
                imageWrapAlignment: WrapAlignment.end,
                imageCardBuilder: (reference) =>
                    _buildUserImageCard(reference, textColor: bubbleTextColor),
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
    final imageReferences = extractMessageImageReferences(message.content);
    final isLoadingReply = message.content.trim().isEmpty &&
        _session.status == SessionStatus.running;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isSpeakingThisMessage =
        _isSpeaking && _speakingMessageId == message.id;
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
              _buildMarkdownMessageBody(
                displayContent,
                textColor: AppColors.textFor(brightness),
                maxWidth: maxWidth,
                imageReferences: imageReferences,
                imageAlignment: Alignment.centerLeft,
                imageWrapAlignment: WrapAlignment.start,
                imageCardBuilder: _buildAssistantImageCard,
              ),
              if (isSpeakingThisMessage) ...[
                const SizedBox(height: AppSpacing.tileY),
                OutlinedButton(
                  onPressed: _stopSpeaking,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.outlineStrongFor(brightness),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.tileX,
                      vertical: AppSpacing.tileY,
                    ),
                  ),
                  child: Text(context.l10n.stopPlayback),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMarkdownMessageBody(
    String content, {
    required Color textColor,
    required double maxWidth,
    required List<MessageImageReference> imageReferences,
    required Alignment imageAlignment,
    required WrapAlignment imageWrapAlignment,
    required Widget Function(MessageImageReference reference) imageCardBuilder,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final codeStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13,
      height: 1.55,
      color: textColor,
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: const <String>['monospace'],
      letterSpacing: 0.1,
    );
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        height: 1.45,
        color: textColor,
      ),
      a: theme.textTheme.bodyLarge?.copyWith(
        height: 1.45,
        color: textColor,
        decoration: TextDecoration.underline,
        decorationColor: textColor,
      ),
      code: codeStyle?.copyWith(
        backgroundColor: AppColors.tintSurfaceFor(
          brightness,
          textColor,
          base: Colors.transparent,
          darkAlpha: 0.18,
          lightAlpha: 0.10,
        ),
      ),
      strong: theme.textTheme.bodyLarge?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w700,
      ),
      em: theme.textTheme.bodyLarge?.copyWith(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      listBullet: theme.textTheme.bodyLarge?.copyWith(color: textColor),
      blockquote: theme.textTheme.bodyLarge?.copyWith(
        color: textColor.withValues(alpha: 0.9),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: textColor.withValues(alpha: 0.28),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(
        left: AppSpacing.compact,
      ),
      blockSpacing: AppSpacing.compact,
      pPadding: const EdgeInsets.symmetric(vertical: 1),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            width: 0.6,
            color: textColor.withValues(alpha: 0.22),
          ),
        ),
      ),
      codeblockPadding: const EdgeInsets.fromLTRB(
        AppSpacing.tileX,
        AppSpacing.tileY,
        AppSpacing.tileX,
        AppSpacing.tileX,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.tintSurfaceFor(
          brightness,
          textColor,
          base: Colors.transparent,
          darkAlpha: 0.14,
          lightAlpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPanel),
        border: Border.all(
          color: textColor.withValues(alpha: 0.22),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: content,
          fitContent: true,
          selectable: true,
          shrinkWrap: true,
          softLineBreak: true,
          styleSheet: styleSheet,
          syntaxHighlighter: _AssistantCodeSyntaxHighlighter(theme),
          onTapLink: (text, href, title) =>
              _handleAssistantMarkdownLinkTap(href),
        ),
        if (imageReferences.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.compact),
          Align(
            alignment: imageAlignment,
            child: Wrap(
              spacing: AppSpacing.compact,
              runSpacing: AppSpacing.compact,
              alignment: imageWrapAlignment,
              children: [
                for (final reference in imageReferences)
                  imageCardBuilder(reference),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _handleAssistantMarkdownLinkTap(String? href) {
    final reference =
        href == null ? null : MessageImageReference.tryParse(href);
    if (reference != null) {
      unawaited(_showImagePreview(reference));
      return;
    }

    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null) {
      return;
    }
    unawaited(launchUrl(uri));
  }

  Widget _buildAssistantImageCard(MessageImageReference reference) {
    final brightness = Theme.of(context).brightness;
    return _buildImageCard(
      reference,
      keyPrefix: 'assistant',
      backgroundColor: AppColors.surfaceFor(brightness),
      borderColor: AppColors.outlineStrongFor(brightness),
      thumbnailBackgroundColor: AppColors.tintSurfaceFor(
        brightness,
        AppColors.signalFor(brightness),
        base: AppColors.panelFor(brightness),
        darkAlpha: 0.18,
        lightAlpha: 0.12,
      ),
      titleColor: AppColors.textFor(brightness),
      subtitleColor: AppColors.mutedSoftFor(brightness),
      actionColor: AppColors.signalFor(brightness),
    );
  }

  Widget _buildImageCard(
    MessageImageReference reference, {
    required String keyPrefix,
    required Color backgroundColor,
    required Color borderColor,
    required Color thumbnailBackgroundColor,
    required Color titleColor,
    required Color subtitleColor,
    required Color actionColor,
  }) {
    final fileFuture = _imageFileFuture(reference);

    Widget buildCard(Widget thumbnail) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('$keyPrefix-image-card-${reference.cardKey}'),
          onTap: () => unawaited(_showImagePreview(reference)),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: thumbnailBackgroundColor,
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumbnail,
            ),
          ),
        ),
      );
    }

    if (fileFuture != null) {
      return FutureBuilder<BridgeFileResponse>(
        future: fileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return buildCard(
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const SizedBox.shrink();
          }
          return buildCard(_buildImageThumbnail(reference, snapshot.data));
        },
      );
    }

    return buildCard(_buildImageThumbnail(reference, null));
  }

  Widget _buildUserImageCard(
    MessageImageReference reference, {
    required Color textColor,
  }) {
    return _buildImageCard(
      reference,
      keyPrefix: 'user',
      backgroundColor: textColor.withValues(alpha: 0.10),
      borderColor: textColor.withValues(alpha: 0.26),
      thumbnailBackgroundColor: textColor.withValues(alpha: 0.12),
      titleColor: textColor,
      subtitleColor: textColor.withValues(alpha: 0.86),
      actionColor: textColor,
    );
  }

  void _pruneImageFileFutures() {
    if (_imageFileFutures.isEmpty) return;
    final activeKeys = <String>{};
    for (final message in _messages) {
      for (final ref in extractMessageImageReferences(message.content)) {
        if (!ref.isRemoteUrl && !ref.isDataUri) {
          activeKeys.add(ref.cardKey);
        }
      }
    }
    _imageFileFutures.removeWhere((key, _) => !activeKeys.contains(key));
  }

  Future<BridgeFileResponse>? _imageFileFuture(
    MessageImageReference reference,
  ) {
    if (reference.isRemoteUrl || reference.isDataUri) {
      return null;
    }

    return _imageFileFutures.putIfAbsent(reference.cardKey, () {
      return _client.readFile(
        reference.path,
        sessionId: reference.isAbsoluteLocalPath ? null : _session.id,
      );
    });
  }

  Widget _buildImageThumbnail(
    MessageImageReference reference,
    BridgeFileResponse? file,
  ) {
    if (reference.isDataUri) {
      final bytes = reference.dataBytes;
      if (bytes == null) {
        return const SizedBox.shrink();
      }
      if (reference.isSvg) {
        return SvgPicture.string(
          utf8.decode(bytes, allowMalformed: true),
          fit: BoxFit.cover,
        );
      }
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => const SizedBox.shrink(),
      );
    }

    if (reference.isRemoteUrl) {
      return reference.isSvg
          ? SvgPicture.network(reference.path, fit: BoxFit.cover)
          : Image.network(
              reference.path,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => const SizedBox.shrink(),
            );
    }

    if (file == null) {
      return const SizedBox.shrink();
    }

    return reference.isSvg
        ? SvgPicture.string(
            String.fromCharCodes(file.bytes),
            fit: BoxFit.cover,
          )
        : Image.memory(
            file.bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) => const SizedBox.shrink(),
          );
  }

  Future<void> _showImagePreview(MessageImageReference reference) async {
    if (!mounted) {
      return;
    }

    final bridgeFileFuture = _imageFileFuture(reference);
    var backdropMode = _ImagePreviewBackdropMode.dark;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget? buildDataUriImage() {
            final bytes = reference.dataBytes;
            if (!reference.isDataUri || bytes == null) {
              return null;
            }

            if (reference.isSvg) {
              return SvgPicture.string(
                utf8.decode(bytes, allowMalformed: true),
                fit: BoxFit.contain,
              );
            }

            return Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, _, __) {
                return _buildImagePreviewError(
                  context.l10n.imagePreviewLoadFailed,
                );
              },
            );
          }

          Widget buildFullscreenImage() {
            final isSvg = reference.isSvg;
            final dataUriChild = buildDataUriImage();
            if (dataUriChild != null) {
              return InteractiveViewer(
                child: SizedBox.expand(child: dataUriChild),
              );
            }
            if (reference.isRemoteUrl) {
              return InteractiveViewer(
                child: SizedBox.expand(
                  child: isSvg
                      ? SvgPicture.network(
                          reference.path,
                          fit: BoxFit.contain,
                          placeholderBuilder: (context) => const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Image.network(
                          reference.path,
                          fit: BoxFit.contain,
                          errorBuilder: (context, _, __) {
                            return _buildImagePreviewError(
                              context.l10n.imagePreviewLoadFailed,
                            );
                          },
                        ),
                ),
              );
            }

            return FutureBuilder<BridgeFileResponse>(
              future: bridgeFileFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _buildImagePreviewError(
                    context.l10n.imagePreviewLoadFailed,
                  );
                }
                return InteractiveViewer(
                  child: SizedBox.expand(
                    child: isSvg
                        ? SvgPicture.string(
                            String.fromCharCodes(snapshot.data!.bytes),
                            fit: BoxFit.contain,
                          )
                        : Image.memory(
                            snapshot.data!.bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (context, _, __) {
                              return _buildImagePreviewError(
                                context.l10n.imagePreviewLoadFailed,
                              );
                            },
                          ),
                  ),
                );
              },
            );
          }

          Color fullscreenBackdropColor() {
            switch (backdropMode) {
              case _ImagePreviewBackdropMode.dark:
                return const Color(0xF20F1115);
              case _ImagePreviewBackdropMode.light:
                return const Color(0xF3EEF2F6);
              case _ImagePreviewBackdropMode.checker:
                return const Color(0xF2181B21);
            }
          }

          Color stageSurfaceColor() {
            switch (backdropMode) {
              case _ImagePreviewBackdropMode.dark:
                return const Color(0xFF171B22);
              case _ImagePreviewBackdropMode.light:
                return const Color(0xFFF8FBFF);
              case _ImagePreviewBackdropMode.checker:
                return Colors.transparent;
            }
          }

          Color stageBorderColor() {
            switch (backdropMode) {
              case _ImagePreviewBackdropMode.dark:
                return Colors.white.withValues(alpha: 0.20);
              case _ImagePreviewBackdropMode.light:
                return Colors.black.withValues(alpha: 0.16);
              case _ImagePreviewBackdropMode.checker:
                return Colors.white.withValues(alpha: 0.24);
            }
          }

          List<BoxShadow> stageShadow() {
            return [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ];
          }

          Widget buildCheckerboardBackground() {
            return LayoutBuilder(
              builder: (context, constraints) {
                const cell = 24.0;
                final cols = math.max(1, (constraints.maxWidth / cell).ceil());
                final rows = math.max(1, (constraints.maxHeight / cell).ceil());
                return Column(
                  children: List.generate(rows, (row) {
                    return Expanded(
                      child: Row(
                        children: List.generate(cols, (col) {
                          final isLight = (row + col).isEven;
                          return Expanded(
                            child: ColoredBox(
                              color: isLight
                                  ? const Color(0xFFE7EBF1)
                                  : const Color(0xFFC7D0DA),
                            ),
                          );
                        }),
                      ),
                    );
                  }),
                );
              },
            );
          }

          Widget buildBackdropChip(
            _ImagePreviewBackdropMode mode,
            String label,
          ) {
            final selected = backdropMode == mode;
            return InkWell(
              key: ValueKey('image-preview-bg-$mode'),
              onTap: () => setDialogState(() {
                backdropMode = mode;
              }),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.tileX,
                  vertical: AppSpacing.compact,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.40)
                        : Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }

          return GestureDetector(
            key: const ValueKey('image-preview-fullscreen'),
            onTap: () => Navigator.of(context).pop(),
            child: ColoredBox(
              color: fullscreenBackdropColor(),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.block),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Material(
                          color: Colors.transparent,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              buildBackdropChip(
                                _ImagePreviewBackdropMode.dark,
                                context.l10n.imagePreviewBgDark,
                              ),
                              const SizedBox(width: AppSpacing.compact),
                              buildBackdropChip(
                                _ImagePreviewBackdropMode.light,
                                context.l10n.imagePreviewBgLight,
                              ),
                              const SizedBox(width: AppSpacing.compact),
                              buildBackdropChip(
                                _ImagePreviewBackdropMode.checker,
                                context.l10n.imagePreviewBgChecker,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        top: 52,
                        child: Stack(
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.zoomOut,
                              child: Container(
                                key: const ValueKey('image-preview-surface'),
                                padding: const EdgeInsets.all(AppSpacing.block),
                                decoration: BoxDecoration(
                                  color: stageSurfaceColor(),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusHero,
                                  ),
                                  border: Border.all(
                                    color: stageBorderColor(),
                                  ),
                                  boxShadow: stageShadow(),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (backdropMode ==
                                        _ImagePreviewBackdropMode.checker)
                                      buildCheckerboardBackground(),
                                    buildFullscreenImage(),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Material(
                                color: Colors.black54,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => Navigator.of(context).pop(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.white,
                                    ),
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImagePreviewError(String message) {
    final brightness = Theme.of(context).brightness;
    return Center(
      child: Container(
        width: double.infinity,
        padding: AppSpacing.tilePadding,
        decoration: BoxDecoration(
          color: AppColors.errorBgFor(brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(color: AppColors.errorBorderFor(brightness)),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.errorTextFor(brightness),
            height: 1.4,
          ),
        ),
      ),
    );
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
        _pruneImageFileFutures();
        _resetVisibleTurnWindow();
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
      final shouldAutoScroll = _isNearBottom();
      final previousTurnCount = _allTurns.length;

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
        _syncVisibleTurnWindow(previousTotalTurns: previousTurnCount);
        _loadingMessages = false;
        _pendingApproval = refreshedSession?.pendingApproval;
        if (refreshedSession != null) {
          _session = refreshedSession;
        }
        _reconcileSubmittedApprovalState();
      });
      if (shouldAutoScroll) {
        _jumpToBottom();
      }
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
        final statusError = status == SessionStatus.failed
            ? (payload['error_message'] as String? ??
                payload['error'] as String?)
            : null;
        setState(() {
          _session = _session.copyWith(
            status: status,
            updatedAt: DateTime.now(),
            errorMessage: statusError,
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
        final previousTurnCount = _allTurns.length;
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
          _syncVisibleTurnWindow(previousTotalTurns: previousTurnCount);
        });
        if (message.role != MessageRole.system) {
          _syncSessionSummaryCache();
        }
        if (message.role == MessageRole.assistant) {
          _maybeAutoSpeakAssistantMessage(message.id);
          _maybeNotifyAssistantMessage(message.id);
          _scheduleRefreshSessionSummary();
        }
        if (shouldAutoScroll) {
          _animateToBottom();
        }
        break;
      case 'message_delta':
        final shouldAutoScroll = _isNearBottom();
        final previousTurnCount = _allTurns.length;
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
          _syncVisibleTurnWindow(previousTotalTurns: previousTurnCount);
        });
        _maybeAutoSpeakAssistantMessage(messageId);
        _maybeNotifyAssistantMessage(messageId);
        if (shouldAutoScroll) {
          _jumpToBottom();
        }
        break;
      case 'agent_error':
        final errorMessage = payload['message'] as String;
        setState(() {
          _speechError = errorMessage;
          _session = _session.copyWith(
            errorMessage: errorMessage,
            updatedAt: DateTime.now(),
          );
        });
        _syncSessionSummaryCache();
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
        if (!_appInForeground) {
          unawaited(
            notificationService.showApprovalRequestNotification(
              _session,
              title: context.l10n.waitingApprovalTitle,
              body: approval.reason?.trim().isNotEmpty == true
                  ? approval.reason!.trim()
                  : approval.command?.trim().isNotEmpty == true
                      ? approval.command!.trim()
                      : context.l10n.waitingApprovalBody,
            ),
          );
        }
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
        _pendingApproval = approval;
        _session = _session.copyWith(
          updatedAt: DateTime.now(),
        );
        _submittingApproval = false;
        _submittingApprovalChoice = null;
        _submittedApprovalRequestId = approval.requestId;
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
                  _voiceInputStarting = false;
                });
              }
            },
            onError: (error, permanent) {
              if (!mounted) {
                return;
              }
              setState(() {
                _isListening = false;
                _voiceInputStarting = false;
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
                _setSpeechStatus(null);
              }
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
          _setSpeechStatus(_systemSpeechUnavailableLabel());
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
        _setSpeechStatus(
          ready ? null : context.l10n.microphonePermissionMissing,
        );
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
            _speakingMessageId = null;
            _callModeAwaitingPlaybackCompletion = false;
            _callModeSpokenReplyText = null;
            _callModeCurrentTtsText = null;
            _clearTransientTtsStatus();
          });
          _completeCallModeCommandAcceptedSpeech();
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
            _speakingMessageId = null;
            _callModeAwaitingPlaybackCompletion = false;
            _callModeSpokenReplyText = null;
            _callModeCurrentTtsText = null;
            _clearTransientTtsStatus();
          });
          _completeCallModeCommandAcceptedSpeech();
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
            _speakingMessageId = null;
            _callModeAwaitingPlaybackCompletion = false;
            _callModeSpokenReplyText = null;
            _callModeCurrentTtsText = null;
            _clearCallModeRecentTtsEcho();
            _speechError = context.l10n.ttsFailed(message);
          });
          _completeCallModeCommandAcceptedSpeech();
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
          _setSpeechStatus(_systemSpeechUnavailableLabel());
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
    final useBridgeStreaming = _usesBridgeRealtimeSpeechForCallMode();
    if (!_speechReady) {
      setState(() {
        _voiceInputStarting = true;
        _setSpeechStatus(context.l10n.reinitializingVoiceInput);
      });
      await _initializeSpeech();
      if (!_speechReady) {
        if (mounted) {
          setState(() {
            _voiceInputStarting = false;
          });
        }
        return;
      }
    }

    if (_isListening) {
      if (useSystemSpeech) {
        await _stopSystemListening();
      } else if (useBridgeStreaming) {
        await _stopBridgeRealtimeAsr();
      } else {
        await _stopRecordingAndTranscribe();
      }
      return;
    }

    if (_voiceInputStarting) {
      return;
    }

    if (useBridgeStreaming) {
      await _startBridgeRealtimeAsr();
      return;
    }

    setState(() {
      _setSpeechStatus(context.l10n.callModePreparingListening);
      _voiceInputStarting = true;
      _clearRecognizedSpeechState();
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
              if (!_callModeEnabled) {
                _controller.text = words;
                _controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: _controller.text.length),
                );
              }
              if (isFinal) {
                _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
              }
            });
            if (isFinal && _callModeEnabled) {
              unawaited(
                _handleCallModeTranscript(words, stopListeningFirst: true),
              );
            }
          },
        );
      } else {
        _recordingPath = await _audioRecordingService.start();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceInputStarting = false;
        _setSpeechStatus(context.l10n.voiceInputInProgress);
        _isListening = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _voiceInputStarting = false;
        _isListening = false;
        _speechError = context.l10n.startVoiceInputFailed('$error');
      });
    }
  }

  Future<void> _stopSystemListening() async {
    _clearCallModeSpeechHint();
    try {
      await _speechInputService.stopListening();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isListening = false;
        _voiceInputStarting = false;
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
        provider == AsrProvider.bridgeLocal;
  }

  bool _usesSystemSpeechForCallMode() {
    return appSettingsController.settings.asrProvider == AsrProvider.system;
  }

  bool _usesBridgeRealtimeSpeechForCallMode() {
    return appSettingsController.settings.asrProvider ==
        AsrProvider.bridgeLocal;
  }

  bool _usesWakeWordForBridgeCallMode() {
    return false;
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
        _voiceInputStarting = false;
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
      _voiceInputStarting = false;
      _setSpeechStatus(context.l10n.uploadingAudio);
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
        _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
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

  Future<void> _speakMessageInternal(
    String content, {
    String? messageId,
    required bool resumeCallModeOnComplete,
  }) async {
    if (!_ttsReady) {
      setState(() {
        _setSpeechStatus(context.l10n.reinitializingTts);
      });
      await _initializeTts();
      if (!_ttsReady) {
        return;
      }
    }

    setState(() {
      _speakingMessageId = messageId;
      final trimmedContent = content.trim();
      _callModeCurrentTtsText = trimmedContent;
      _callModeRecentTtsText = trimmedContent;
      _callModeRecentTtsExpiresAt =
          DateTime.now().add(_callModeTtsEchoGracePeriod);
      _callModeSpokenReplyText =
          resumeCallModeOnComplete ? trimmedContent : _callModeSpokenReplyText;
      _callModeAwaitingPlaybackCompletion = resumeCallModeOnComplete;
      _clearTransientTtsStatus();
    });
    if (resumeCallModeOnComplete && _callModeAllowInterruptions) {
      unawaited(_maybeResumeCallModeListening());
    }
    try {
      await _ttsService.speak(content);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _callModeAwaitingPlaybackCompletion = false;
        _callModeSpokenReplyText = null;
        _callModeCurrentTtsText = null;
        _speakingMessageId = null;
        _clearCallModeRecentTtsEcho();
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
        messageId: messageId,
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
      _speakingMessageId = null;
      _callModeSpokenReplyText = null;
      _callModeCurrentTtsText = null;
    });
  }

  void _clearCallModeRecentTtsEcho() {
    _callModeRecentTtsText = null;
    _callModeRecentTtsExpiresAt = null;
  }

  void _completeCallModeCommandAcceptedSpeech() {
    final completer = _callModeCommandAcceptedSpeechCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  Future<void> _speakCallModeCommandAcceptedBeforeListening() async {
    final completer = Completer<void>();
    _callModeCommandAcceptedSpeechCompleter = completer;
    try {
      await _speakMessageInternal(
        context.l10n.callModeCommandAccepted,
        messageId: null,
        resumeCallModeOnComplete: false,
      );
      await completer.future.timeout(
        _callModeCommandAcceptedSpeechTimeout,
        onTimeout: () {},
      );
    } finally {
      if (identical(_callModeCommandAcceptedSpeechCompleter, completer)) {
        _callModeCommandAcceptedSpeechCompleter = null;
      }
    }
  }

  KeyEventResult _handleMessageInputKeyEvent(FocusNode _, KeyEvent event) {
    if (_isMobilePlatform) {
      return KeyEventResult.ignored;
    }
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

  bool get _isMobilePlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        false,
    };
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
    final previousTurnCount = _allTurns.length;
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
      _syncVisibleTurnWindow(previousTotalTurns: previousTurnCount);
    });
    _jumpToBottom();

    try {
      final previousTurnCountAfterLocalInsert = _allTurns.length;
      final result = await _client.sendMessage(
        _session.id,
        content,
        inputMode: inputMode,
        systemPrompt: _messageSystemPrompt(inputMode),
        providerId: _overrideProviderId,
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
        _callModeInterruptedCurrentReply = false;
        _syncVisibleTurnWindow(
          previousTotalTurns: previousTurnCountAfterLocalInsert,
        );
      });
      _syncSessionSummaryCache();
      _scheduleRefreshSessionSummary();
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

  String? _messageSystemPrompt(String inputMode) {
    final prompts = <String>[];
    if (_session.briefReplyMode &&
        appSettingsController.settings.compressAssistantReplies) {
      final maxChars =
          appSettingsController.settings.compressAssistantReplyMaxChars;
      prompts.add(
        'Keep the assistant reply brief. Summarize what you did concisely, '
        'ideally within $maxChars characters unless the user explicitly asks for '
        'detail.',
      );
    }

    final speechPrompt = _speechPlaybackSystemPrompt(inputMode);
    if (speechPrompt != null) {
      prompts.add(speechPrompt);
    }

    return prompts.isEmpty ? null : prompts.join('\n\n');
  }

  String? _speechPlaybackSystemPrompt(String inputMode) {
    if (!appSettingsController.settings.speechPlaybackPromptEnabled) {
      return null;
    }
    final shouldPlayReplyBySpeech =
        inputMode == 'voice' || appSettingsController.settings.autoSpeakReplies;
    if (!shouldPlayReplyBySpeech) {
      return null;
    }
    return 'The assistant reply will be played aloud with text-to-speech. '
        'Prefer concise, speech-friendly prose. Avoid long raw URLs, large code '
        'blocks, tables, and other content that is difficult to listen to unless '
        'the user explicitly asks for that content.';
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
        _setSpeechStatus(context.l10n.replyStopped);
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
      _voiceInputStarting = false;
      _callModeAwaitingPlaybackCompletion = false;
      _callModeSpokenReplyText = null;
      _callModeCurrentTtsText = null;
      _clearCallModeRecentTtsEcho();
      _callModeInterruptedCurrentReply = false;
      _callModeSubmittingVoiceUtterance = false;
      _completeCallModeCommandAcceptedSpeech();
      _callModeSpeechHintState = null;
    });
    await _maybeResumeCallModeListening();
  }

  Future<void> _disableCallMode() async {
    final shouldCancelListening = _isListening && _useSystemSpeech();
    final shouldCancelBridgeStreaming =
        _streamingAsrActive && _usesBridgeRealtimeSpeechForCallMode();
    final shouldCancelBridgeStarting =
        _voiceInputStarting && _usesBridgeRealtimeSpeechForCallMode();
    _cancelCallModeSpeechHintTimer();
    setState(() {
      _callModeEnabled = false;
      _isListening = false;
      _voiceInputStarting = false;
      _streamingAsrActive = false;
      _clearRecognizedSpeechState();
      _resetBridgeRealtimeUtteranceGateState();
      _callModeAwaitingPlaybackCompletion = false;
      _callModeSpokenReplyText = null;
      _callModeCurrentTtsText = null;
      _clearCallModeRecentTtsEcho();
      _callModeInterruptedCurrentReply = false;
      _callModeSpeechHintState = null;
    });
    if (shouldCancelBridgeStreaming || shouldCancelBridgeStarting) {
      await _stopBridgeRealtimeAsr();
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
        _voiceInputStarting = false;
        _clearRecognizedSpeechState();
        _resetBridgeRealtimeUtteranceGateState();
        _callModeSpeechHintState = null;
      });
    }
  }

  Future<void> _maybeResumeCallModeListening() async {
    final listeningForInterruptions = _shouldListenForCallModeInterruptions;
    if (!_callModeEnabled ||
        _creatingSession ||
        !_appInForeground ||
        _session.status == SessionStatus.awaitingApproval ||
        _pendingApproval != null ||
        _voiceInputStarting ||
        _isListening ||
        _systemTranscriptCompleting ||
        _streamingAsrActive ||
        _callModeSubmittingVoiceUtterance ||
        (_session.status == SessionStatus.running &&
            !_callModeSendingVoiceUtterance &&
            !listeningForInterruptions) ||
        ((_callModeAwaitingPlaybackCompletion || _isSpeaking) &&
            !listeningForInterruptions) ||
        (_controller.text.trim().isNotEmpty && !listeningForInterruptions) ||
        _callModeUnavailableMessage != null) {
      return;
    }

    if (_usesSystemSpeechForCallMode()) {
      await _toggleListening();
    } else if (_usesBridgeRealtimeSpeechForCallMode()) {
      await _startBridgeRealtimeAsr();
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
        _callModeCurrentTtsText = null;
        _clearCallModeRecentTtsEcho();
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
            _voiceInputStarting = false;
            _callModeEnabled = false;
            _callModeAwaitingPlaybackCompletion = false;
            _callModeCurrentTtsText = null;
            _clearCallModeRecentTtsEcho();
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
        _callModeCurrentTtsText = null;
        _clearCallModeRecentTtsEcho();
      });
    } finally {
      _systemTranscriptCompleting = false;
    }
  }

  BridgeRealtimeAsrConfig _bridgeRealtimeAsrConfig() {
    final pauseMillis =
        appSettingsController.settings.callModeSpeechPauseMillis;
    final endpointTrailingSilenceMs = math.max(
      300,
      math.min(5000, (pauseMillis / _bridgeRealtimeEndpointRule2Ratio).ceil()),
    );
    final vadMinSilenceMs = math.max(200, math.min(5000, pauseMillis));
    debugPrint(
      '[call-mode] bridge realtime config wakeWord=disabled '
      'endpointTrailingSilenceMs=$endpointTrailingSilenceMs '
      'vadMinSilenceMs=$vadMinSilenceMs',
    );
    return BridgeRealtimeAsrConfig(
      sampleRateHz: 16000,
      channels: 1,
      enableVad: true,
      endpointTrailingSilenceMs: endpointTrailingSilenceMs,
      vadMinSilenceMs: vadMinSilenceMs,
    );
  }

  bool get _callModeAllowInterruptions =>
      appSettingsController.settings.callModeAllowInterruptions;

  bool get _shouldListenForCallModeInterruptions {
    if (!_callModeEnabled || !_callModeAllowInterruptions) {
      return false;
    }
    final provider = appSettingsController.settings.asrProvider;
    final canStream =
        provider == AsrProvider.bridgeLocal || provider == AsrProvider.system;
    if (!canStream) {
      return false;
    }
    return _session.status == SessionStatus.running ||
        _callModeAwaitingPlaybackCompletion ||
        _isSpeaking;
  }

  void _cancelCallModeSpeechHintTimer() {
    _callModeSpeechHintTimer?.cancel();
    _callModeSpeechHintTimer = null;
  }

  void _setCallModeSpeechHintState(_CallModeSpeechHintState? state) {
    if (!mounted || _callModeSpeechHintState == state) {
      return;
    }
    setState(() {
      _callModeSpeechHintState = state;
    });
  }

  void _clearCallModeSpeechHint() {
    _cancelCallModeSpeechHintTimer();
    _setCallModeSpeechHintState(null);
  }

  void _handleCallModeSpeechActivity() {
    if (!_callModeEnabled) {
      return;
    }
    _cancelCallModeSpeechHintTimer();
    _setCallModeSpeechHintState(_CallModeSpeechHintState.speaking);

    final pauseMillis =
        appSettingsController.settings.callModeSpeechPauseMillis;
    final delayMillis = math.max(
      240,
      (pauseMillis * _callModeSpeechHintDelayRatio).round(),
    );
    _callModeSpeechHintTimer = Timer(
      Duration(milliseconds: delayMillis),
      () {
        if (!mounted ||
            !_callModeEnabled ||
            !_streamingAsrActive ||
            _recognizedSpeech.trim().isEmpty) {
          return;
        }
        _setCallModeSpeechHintState(_CallModeSpeechHintState.waitingForPause);
      },
    );
  }

  bool _isCallModeTtsEcho(String transcript) {
    if (!_callModeEnabled) {
      return false;
    }
    final now = DateTime.now();
    final recentTtsText = (_callModeRecentTtsExpiresAt != null &&
            now.isBefore(_callModeRecentTtsExpiresAt!))
        ? _callModeRecentTtsText
        : null;
    if (recentTtsText == null && _callModeRecentTtsExpiresAt != null) {
      _clearCallModeRecentTtsEcho();
    }
    final candidates = <String>[
      if (_callModeCurrentTtsText?.trim().isNotEmpty == true)
        _callModeCurrentTtsText!,
      if (recentTtsText?.trim().isNotEmpty == true) recentTtsText!,
      if (_callModeSpokenReplyText?.trim().isNotEmpty == true)
        _callModeSpokenReplyText!,
      if ((_isSpeaking || _callModeAwaitingPlaybackCompletion) &&
          (_lastAssistantReplyText()?.trim().isNotEmpty == true))
        _lastAssistantReplyText()!,
    ];
    if (candidates.isEmpty) {
      return false;
    }
    final normalizedTranscript = _normalizeSpeechEchoText(transcript);
    if (normalizedTranscript.length < 4) {
      return false;
    }
    for (final candidate in candidates) {
      final normalizedReply = _normalizeSpeechEchoText(candidate);
      if (normalizedReply.length < 4) {
        continue;
      }
      if (normalizedReply.contains(normalizedTranscript) ||
          normalizedTranscript.contains(normalizedReply)) {
        return true;
      }

      final transcriptTokens = _speechEchoTokens(normalizedTranscript);
      final replyTokens = _speechEchoTokens(normalizedReply).toSet();
      if (transcriptTokens.length < 3 || replyTokens.length < 3) {
        continue;
      }
      final overlap =
          transcriptTokens.where((token) => replyTokens.contains(token)).length;
      if (overlap / transcriptTokens.length >= 0.72) {
        return true;
      }
    }
    return false;
  }

  String _normalizeSpeechEchoText(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune).toLowerCase();
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch)) {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  List<String> _speechEchoTokens(String value) {
    final tokens = <String>[];
    for (var index = 0; index < value.length; index += 1) {
      final end = math.min(value.length, index + 2);
      tokens.add(value.substring(index, end));
    }
    return tokens;
  }

  String? _lastAssistantReplyText() {
    for (final message in _messages.reversed) {
      if (message.role == MessageRole.assistant &&
          message.content.trim().isNotEmpty) {
        return message.content;
      }
    }
    return null;
  }

  Future<void> _handleCallModeSpeechStarted() async {
    if (!_callModeEnabled ||
        !_callModeAllowInterruptions ||
        _callModeInterruptedCurrentReply ||
        _callModeInterrupting) {
      return;
    }
    final shouldStopSpeaking =
        _isSpeaking || _callModeAwaitingPlaybackCompletion;
    final shouldCancelReply =
        _session.status == SessionStatus.running && !_cancellingReply;
    if (!shouldStopSpeaking && !shouldCancelReply) {
      return;
    }

    _callModeInterrupting = true;
    _callModeInterruptedCurrentReply = true;
    try {
      if (shouldStopSpeaking) {
        await _stopSpeaking();
      }
      if (shouldCancelReply) {
        await _cancelReply();
      } else if (_callModeEnabled) {
        unawaited(_maybeResumeCallModeListening());
      }
    } finally {
      _callModeInterrupting = false;
    }
  }

  Future<bool> _finalizeSystemTranscript(
    String transcript, {
    required bool autoSend,
  }) async {
    final trimmedTranscript = transcript.trim();
    _clearRecognizedSpeechState();
    if (!mounted) {
      return false;
    }
    if (trimmedTranscript.isEmpty) {
      setState(() {
        _isListening = false;
        _voiceInputStarting = false;
        _speechError = context.l10n.voiceTranscriptionNoResult;
      });
      if (autoSend) {
        unawaited(_maybeResumeCallModeListening());
      }
      return false;
    }

    setState(() {
      _isListening = false;
      _voiceInputStarting = false;
      if (!autoSend) {
        _controller.text = trimmedTranscript;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
      _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
    });

    if (!autoSend) {
      return true;
    }
    final submitted =
        await _submitLocalMessage(trimmedTranscript, inputMode: 'voice');
    if (submitted && _callModeEnabled && _callModeAllowInterruptions) {
      unawaited(_maybeResumeCallModeListening());
    }
    return submitted;
  }

  Future<void> _startBridgeRealtimeAsr() async {
    if (_streamingAsrActive) {
      return;
    }
    if (_voiceInputStarting) {
      return;
    }
    if (!_speechReady) {
      setState(() {
        _voiceInputStarting = true;
        _setSpeechStatus(context.l10n.reinitializingVoiceInput);
      });
      await _initializeSpeech();
      if (!_speechReady) {
        if (mounted) {
          setState(() {
            _voiceInputStarting = false;
          });
        }
        return;
      }
    }

    setState(() {
      _setSpeechStatus(context.l10n.callModePreparingListening);
      _voiceInputStarting = true;
      _clearRecognizedSpeechState();
      _resetBridgeRealtimeUtteranceGateState();
      _callModeSpeechHintState = null;
    });

    final startedForCallMode = _callModeEnabled;
    try {
      debugPrint('[call-mode] starting bridge realtime ASR');
      final audioStream =
          (await _audioRecordingService.startStream()).asBroadcastStream();
      await _bridgeRealtimeAsrService.start(
        audioStream: audioStream,
        config: _bridgeRealtimeAsrConfig(),
        onUtterance: (utterance) {
          debugPrint(
            '[call-mode] bridge utterance final=${utterance.isFinal} text=${utterance.text}',
          );
          if (!mounted) {
            return;
          }
          if (_callModeSubmittingVoiceUtterance &&
              !_callModeSendingVoiceUtterance) {
            return;
          }
          final rawTranscript = utterance.text;
          final transcriptText = rawTranscript;
          final isMeaningfulTranscript =
              _isMeaningfulVoiceTranscript(transcriptText);
          final isSubstantialTranscript =
              _isSubstantialVoiceTranscript(transcriptText);
          final accepted = utterance.speakerAccepted;
          final ttsEcho = accepted && _isCallModeTtsEcho(transcriptText);
          final pendingVerification = utterance.pendingVerification;
          final rejected = utterance.rejected || ttsEcho;
          final rejectedSpeaker = utterance.speakerFilterActive &&
              utterance.speakerVerified &&
              utterance.speakerMatched == false;
          final rejectedOther = rejected && !rejectedSpeaker;
          if (utterance.isFinal) {
            debugPrint(
              '[call-mode] bridge final gate accepted=$accepted ttsEcho=$ttsEcho '
              'speakerAccepted=${utterance.speakerAccepted} '
              'raw=$rawTranscript text=$transcriptText',
            );
          }
          final canInterruptCurrentSpeech =
              !_isSpeaking || utterance.speakerFilterActive;
          if (_callModeEnabled &&
              isSubstantialTranscript &&
              accepted &&
              !ttsEcho &&
              canInterruptCurrentSpeech) {
            _handleCallModeSpeechActivity();
            _callModeInterruptFuture = _handleCallModeSpeechStarted();
          }
          if (!isMeaningfulTranscript) {
            if (utterance.isFinal && _callModeEnabled) {
              unawaited(_handleBridgeRealtimeFinalUtterance(transcriptText));
            }
            return;
          }
          setState(() {
            _recognizedSpeech = transcriptText;
            _recognizedSpeechPendingSpeakerVerification = pendingVerification;
            _recognizedSpeechRejectedSpeaker = rejectedSpeaker;
            _recognizedSpeechRejectedWakeWord = false;
            _recognizedSpeechRejectedOther = rejectedOther;
            if (!_callModeEnabled) {
              _controller.text = transcriptText;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            }
            if (utterance.isFinal) {
              _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
            }
          });
          if (utterance.isFinal && _callModeEnabled && accepted && !ttsEcho) {
            _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
            debugPrint(
              '[call-mode] bridge command accepted for agent submit text=$transcriptText',
            );
            final shouldWaitForInterrupt = _callModeInterruptFuture != null;
            _callModeSubmittingVoiceUtterance = true;
            unawaited(_handleBridgeRealtimeFinalUtterance(
              transcriptText,
              waitForInterrupt: shouldWaitForInterrupt,
            ));
          }
        },
        onError: (error) {
          debugPrint('[call-mode] bridge ASR error: $error');
          if (!mounted) {
            return;
          }
          if (startedForCallMode && !_callModeEnabled) {
            return;
          }
          setState(() {
            _isListening = false;
            _voiceInputStarting = false;
            _streamingAsrActive = false;
            _callModeEnabled = false;
            _callModeAwaitingPlaybackCompletion = false;
            _callModeCurrentTtsText = null;
            _clearCallModeRecentTtsEcho();
            _callModeSubmittingVoiceUtterance = false;
            _speechError = context.l10n.voiceTranscriptionFailed(error);
          });
        },
        onSpeechStarted: () {
          debugPrint('[call-mode] bridge VAD speech_started');
        },
      );
      if (!mounted) {
        return;
      }
      if (startedForCallMode && !_callModeEnabled) {
        await _stopBridgeRealtimeAsr();
        return;
      }
      setState(() {
        _voiceInputStarting = false;
        _setSpeechStatus(context.l10n.voiceInputInProgress);
        _isListening = true;
        _streamingAsrActive = true;
      });
      debugPrint(
        '[call-mode] bridge realtime listening; wakeWord=${_usesWakeWordForBridgeCallMode()} '
        'state=${_usesWakeWordForBridgeCallMode() ? 'waiting_for_kws' : 'listening_for_command'}',
      );
    } catch (error) {
      debugPrint('[call-mode] failed to start bridge ASR: $error');
      await _cancelBridgeRealtimeAsrServices();
      if (!mounted) {
        return;
      }
      if (startedForCallMode && !_callModeEnabled) {
        setState(() {
          _voiceInputStarting = false;
          _isListening = false;
          _streamingAsrActive = false;
        });
        return;
      }
      setState(() {
        _voiceInputStarting = false;
        _isListening = false;
        _streamingAsrActive = false;
        _speechError = context.l10n.startVoiceInputFailed('$error');
      });
    }
  }

  Future<void> _cancelBridgeRealtimeAsrServices() async {
    try {
      await _bridgeRealtimeAsrService.cancel();
    } catch (error) {
      debugPrint('[call-mode] failed to cancel bridge realtime ASR: $error');
    }
    try {
      await _audioRecordingService.cancel();
    } catch (error) {
      debugPrint('[call-mode] failed to cancel audio recording: $error');
    }
  }

  Future<void> _stopBridgeRealtimeAsr({
    bool clearSubmittingVoiceUtterance = true,
  }) async {
    _clearCallModeSpeechHint();
    await _cancelBridgeRealtimeAsrServices();
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
      _voiceInputStarting = false;
      _streamingAsrActive = false;
      _clearRecognizedSpeechState();
      _resetBridgeRealtimeUtteranceGateState();
      if (clearSubmittingVoiceUtterance) {
        _callModeSubmittingVoiceUtterance = false;
        _completeCallModeCommandAcceptedSpeech();
      }
      if (!_callModeEnabled) {
        _setSpeechStatus(null);
      }
    });
  }

  Future<void> _handleBridgeRealtimeFinalUtterance(
    String transcript, {
    bool waitForInterrupt = true,
  }) async {
    _clearCallModeSpeechHint();
    final trimmedTranscript = transcript.trim();
    if (!mounted) {
      return;
    }
    if (!_isMeaningfulVoiceTranscript(trimmedTranscript)) {
      setState(() {
        _clearRecognizedSpeechState();
        _resetBridgeRealtimeUtteranceGateState();
        if (!_callModeEnabled) {
          _controller.clear();
        }
        _setSpeechStatus(context.l10n.voiceInputInProgress);
      });
      return;
    }
    setState(() {
      _recognizedSpeech = trimmedTranscript;
      _recognizedSpeechPendingSpeakerVerification = false;
      _recognizedSpeechRejectedSpeaker = false;
      _recognizedSpeechRejectedWakeWord = false;
      _recognizedSpeechRejectedOther = false;
      _callModeSubmittingVoiceUtterance = true;
      _callModeSendingVoiceUtterance = false;
      if (!_callModeEnabled) {
        _controller.text = trimmedTranscript;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
      _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
    });
    final pauseBridgeListeningForAck =
        _streamingAsrActive && _usesBridgeRealtimeSpeechForCallMode();
    if (pauseBridgeListeningForAck) {
      await _stopBridgeRealtimeAsr(clearSubmittingVoiceUtterance: false);
      if (!mounted) {
        return;
      }
    }
    await _speakCallModeCommandAcceptedBeforeListening();
    if (!mounted) {
      return;
    }
    if (_callModeAllowInterruptions) {
      setState(() {
        _callModeSubmittingVoiceUtterance = false;
        _callModeSendingVoiceUtterance = true;
      });
      unawaited(_maybeResumeCallModeListening());
    }
    if (!_callModeAllowInterruptions) {
      await _stopBridgeRealtimeAsr();
      if (!mounted) {
        return;
      }
    } else {
      final interruptFuture = _callModeInterruptFuture;
      if (waitForInterrupt && interruptFuture != null) {
        await interruptFuture;
        if (!mounted) {
          return;
        }
      } else if (_session.status == SessionStatus.running &&
          !_cancellingReply) {
        await _cancelReply();
        if (!mounted) {
          return;
        }
      }
    }
    var submitted = false;
    try {
      submitted =
          await _submitLocalMessage(trimmedTranscript, inputMode: 'voice');
      debugPrint(
        '[call-mode] bridge final submit completed submitted=$submitted text=$trimmedTranscript',
      );
    } finally {
      if (mounted) {
        setState(() {
          _callModeSendingVoiceUtterance = false;
        });
      }
    }
    if (mounted && !_callModeSendingVoiceUtterance) {
      setState(() {
        _callModeSubmittingVoiceUtterance = false;
        if (submitted) {
          _clearRecognizedSpeechState();
          _resetBridgeRealtimeUtteranceGateState();
        }
      });
    }
    if (submitted && _callModeEnabled && _callModeAllowInterruptions) {
      unawaited(_maybeResumeCallModeListening());
    }
    if (!mounted || submitted) {
      return;
    }
    setState(() {
      _callModeEnabled = false;
      _callModeAwaitingPlaybackCompletion = false;
      _callModeCurrentTtsText = null;
      _clearCallModeRecentTtsEcho();
    });
  }

  List<_ConversationTurn> _buildConversationTurns(
      Iterable<ChatMessage> messages) {
    final turns = <_ConversationTurn>[];
    _ConversationTurn? currentTurn;
    for (final message in messages) {
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

  List<_ConversationTurn> get _allTurns => _buildConversationTurns(_messages);

  List<_ConversationTurn> get _turns {
    final turns = _allTurns;
    if (turns.isEmpty) {
      return turns;
    }
    final visibleTurnCount = math.min(_visibleTurnCount, turns.length);
    if (visibleTurnCount <= 0 || visibleTurnCount >= turns.length) {
      return turns;
    }
    return turns.sublist(turns.length - visibleTurnCount);
  }

  bool get _hasHiddenTurns => _visibleTurnCount < _allTurns.length;

  void _resetVisibleTurnWindow() {
    _visibleTurnCount = math.min(_allTurns.length, _initialVisibleTurnCount);
  }

  void _syncVisibleTurnWindow({
    required int previousTotalTurns,
  }) {
    final totalTurns = _allTurns.length;
    if (totalTurns == 0) {
      _visibleTurnCount = 0;
      return;
    }

    if (_visibleTurnCount <= 0) {
      _visibleTurnCount = math.min(totalTurns, _initialVisibleTurnCount);
      return;
    }

    final showingAllTurns =
        previousTotalTurns > 0 && _visibleTurnCount >= previousTotalTurns;
    _visibleTurnCount =
        showingAllTurns ? totalTurns : math.min(_visibleTurnCount, totalTurns);
  }

  void _expandVisibleHistory({required bool preserveViewport}) {
    if (_expandingHistory || !_hasHiddenTurns) {
      return;
    }

    final previousMaxScrollExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final previousPixels =
        _scrollController.hasClients ? _scrollController.position.pixels : 0.0;

    setState(() {
      _expandingHistory = true;
      _visibleTurnCount = math.min(
        _allTurns.length,
        _visibleTurnCount + _historyTurnBatchSize,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (_scrollController.hasClients) {
        if (preserveViewport) {
          final position = _scrollController.position;
          final extentDelta =
              position.maxScrollExtent - previousMaxScrollExtent;
          final target = (previousPixels + extentDelta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          _scrollController.jumpTo(target);
        } else {
          _jumpToBottom();
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _expandingHistory = false;
      });
    });
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
    if (_hasHiddenTurns &&
        !_expandingHistory &&
        notification.metrics.pixels <= _topHistoryExpandThreshold) {
      _expandVisibleHistory(preserveViewport: true);
    }
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
    _scrollToBottom();
  }

  void _animateToBottom() {
    _scrollToBottom(animated: true);
  }

  void _scrollToBottom({
    bool animated = false,
    int remainingPasses = 4,
    double? lastMaxScrollExtent,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      final shouldMove = (target - position.pixels).abs() > 0.5;

      if (shouldMove) {
        if (animated) {
          unawaited(
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            ),
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }

      if (remainingPasses <= 1) {
        return;
      }

      final shouldContinue = lastMaxScrollExtent == null ||
          (target - lastMaxScrollExtent).abs() > 0.5 ||
          !_isNearBottom();
      if (shouldContinue) {
        WidgetsBinding.instance.scheduleFrame();
        _scrollToBottom(
          remainingPasses: remainingPasses - 1,
          lastMaxScrollExtent: target,
        );
      }
    });
  }
}

enum _ImagePreviewBackdropMode { dark, light, checker }

enum _CallModeSpeechHintState {
  speaking,
  waitingForPause,
}

class _CallModeRealtimeHint {
  const _CallModeRealtimeHint({
    required this.label,
    required this.detail,
  });

  final String label;
  final String detail;
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
