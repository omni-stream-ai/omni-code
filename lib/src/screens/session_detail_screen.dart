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
import '../services/speech_input_service.dart';
import '../services/tts_service.dart';
import '../settings/app_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_back_header.dart';
import '../widgets/app_skeleton.dart';

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
    with WidgetsBindingObserver {
  static const double _bottomAutoScrollThreshold = 96;
  static const double _topHistoryExpandThreshold = 72;
  static const double _messageBubbleMaxWidth = 320;
  static const double _assistantMessageBubbleWidthFactor = 0.82;
  static const int _initialVisibleTurnCount = 10;
  static const int _historyTurnBatchSize = 10;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final AudioRecordingService _audioRecordingService;
  late final SpeechInputService _speechInputService;
  late final TtsService _ttsService;
  final Set<String> _autoSpokenAssistantMessageIds = <String>{};
  final Set<String> _notifiedAssistantMessageIds = <String>{};
  final Map<String, _LocalMessageDraft> _localMessageStates = {};
  late SessionSummary _session;
  final List<ChatMessage> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _eventsSubscription;
  Timer? _eventsReconnectTimer;
  Timer? _speechStatusAutoDismissTimer;

  String? _recordingPath;
  String _recognizedSpeech = '';
  String? _systemAsrLocaleId;
  bool _systemAsrUnavailable = false;
  bool _loadingMessages = true;
  bool _speechReady = false;
  bool _ttsReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
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

  bool get _isSpeechReadyStatus => _speechStatus == _readySpeechStatusLabel();
  BridgeClient get _client => widget.client ?? bridgeClient;

  String _readySpeechStatusLabel() => context.l10n.speechReadyStatus;
  String _systemSpeechUnavailableLabel() =>
      context.l10n.systemSpeechUnavailable;
  String? get _systemSpeechUnavailableStatus =>
      _speechError == null && _speechStatus == _systemSpeechUnavailableLabel()
          ? _speechStatus
          : null;

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
    final previousStatus = _speechStatus;
    _speechStatus = status;
    _syncSpeechStatusAutoDismiss();
    if (status == null ||
        status == previousStatus ||
        status == _readySpeechStatusLabel() ||
        status == _systemSpeechUnavailableLabel()) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _speechStatus != status) {
        return;
      }
      _showTransientSpeechStatus(status);
    });
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

  void _showTransientSpeechStatus(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(message),
        ),
      );
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
    WidgetsBinding.instance.addObserver(this);
    _audioRecordingService =
        widget.audioRecordingService ?? AudioRecordingService();
    _speechInputService = widget.speechInputService ?? SpeechInputService();
    _ttsService = widget.ttsService ?? TtsService();
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
    WidgetsBinding.instance.removeObserver(this);
    _eventsSubscription?.cancel();
    _eventsReconnectTimer?.cancel();
    _speechStatusAutoDismissTimer?.cancel();
    unawaited(_audioRecordingService.cancel());
    unawaited(_speechInputService.cancel());
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
    final approvalCardMaxHeight = MediaQuery.of(context).size.height * 0.42;
    final isAwaitingSubmittedApprovalResolution =
        _isAwaitingSubmittedApprovalResolution;
    final systemSpeechUnavailableMessage = _systemSpeechUnavailableStatus;
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
      ),
      body: Column(
        children: [
          if (_shouldShowErrorBanner) _buildErrorBanner(_speechError!.trim()),
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
            const SizedBox(height: AppSpacing.stack),
            if (!isAwaitingResolution)
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

  Widget _buildErrorBanner(String message) {
    final brightness = Theme.of(context).brightness;
    return Container(
      key: const ValueKey('session-error-banner'),
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
              _buildMarkdownMessageBody(
                displayContent,
                textColor: AppColors.textFor(brightness),
                maxWidth: maxWidth,
                imageReferences: imageReferences,
                imageCardBuilder: _buildAssistantImageCard,
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

  Widget _buildMarkdownMessageBody(
    String content, {
    required Color textColor,
    required double maxWidth,
    required List<MessageImageReference> imageReferences,
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
      blockSpacing: AppSpacing.compact,
      pPadding: const EdgeInsets.symmetric(vertical: 1),
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
          const SizedBox(height: AppSpacing.stack),
          ...imageReferences.map(
            (reference) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.compact),
              child: imageCardBuilder(reference),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('assistant-image-card-${reference.cardKey}'),
        onTap: () => unawaited(_showImagePreview(reference)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        child: Container(
          width: double.infinity,
          padding: AppSpacing.tilePadding,
          decoration: BoxDecoration(
            color: AppColors.surfaceFor(brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            border: Border.all(color: AppColors.outlineStrongFor(brightness)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.tintSurfaceFor(
                    brightness,
                    AppColors.signalFor(brightness),
                    base: AppColors.panelFor(brightness),
                    darkAlpha: 0.18,
                    lightAlpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: AppColors.signalFor(brightness),
                ),
              ),
              const SizedBox(width: AppSpacing.tileX),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.imageAttachment,
                      style: TextStyle(
                        color: AppColors.textFor(brightness),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      reference.displayPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.mutedSoftFor(brightness),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Text(
                context.l10n.previewImage,
                style: TextStyle(
                  color: AppColors.signalFor(brightness),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserImageCard(
    MessageImageReference reference, {
    required Color textColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('user-image-card-${reference.cardKey}'),
        onTap: () => unawaited(_showImagePreview(reference)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        child: Container(
          width: double.infinity,
          padding: AppSpacing.tilePadding,
          decoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            border: Border.all(
              color: textColor.withValues(alpha: 0.26),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: textColor,
                ),
              ),
              const SizedBox(width: AppSpacing.tileX),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.imageAttachment,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.micro),
                    Text(
                      reference.displayPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.86),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.compact),
              Text(
                context.l10n.previewImage,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showImagePreview(MessageImageReference reference) async {
    if (!mounted) {
      return;
    }

    final brightness = Theme.of(context).brightness;
    final bridgeFileFuture = reference.isRemoteUrl || reference.isDataUri
        ? null
        : _client.readFile(
            reference.path,
            sessionId: reference.isAbsoluteLocalPath ? null : _session.id,
          );
    var isFullscreen = false;
    var backdropMode = _ImagePreviewBackdropMode.dark;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget wrapPreviewSurface(Widget child) {
            return MouseRegion(
              cursor: isFullscreen
                  ? SystemMouseCursors.zoomOut
                  : SystemMouseCursors.zoomIn,
              child: GestureDetector(
                key: const ValueKey('image-preview-surface'),
                onTap: () => setDialogState(() {
                  isFullscreen = !isFullscreen;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: double.infinity,
                  height: 320,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDeepFor(brightness),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusCard,
                    ),
                    border: Border.all(
                      color: AppColors.outlineStrongFor(brightness),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
            );
          }

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

          Widget buildImage() {
            final isSvg = reference.isSvg;
            final dataUriChild = buildDataUriImage();
            if (dataUriChild != null) {
              return wrapPreviewSurface(
                InteractiveViewer(child: dataUriChild),
              );
            }
            if (reference.isRemoteUrl) {
              final remoteChild = isSvg
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
                    );
              return wrapPreviewSurface(
                InteractiveViewer(child: remoteChild),
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

                final localChild = isSvg
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
                      );

                return wrapPreviewSurface(
                  InteractiveViewer(child: localChild),
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

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AlertDialog(
                  key: const ValueKey('image-preview-dialog'),
                  backgroundColor: AppColors.panelFor(brightness),
                  title: Text(context.l10n.imagePreviewTitle),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reference.displayPath,
                          style: TextStyle(
                            color: AppColors.mutedSoftFor(brightness),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.block),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 420,
                              minHeight: 180,
                            ),
                            child: buildImage(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.close),
                    ),
                  ],
                ),
              ),
              if (isFullscreen)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('image-preview-fullscreen'),
                    onTap: () => setDialogState(() {
                      isFullscreen = false;
                    }),
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
                                      const SizedBox(
                                        width: AppSpacing.compact,
                                      ),
                                      buildBackdropChip(
                                        _ImagePreviewBackdropMode.light,
                                        context.l10n.imagePreviewBgLight,
                                      ),
                                      const SizedBox(
                                        width: AppSpacing.compact,
                                      ),
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
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.zoomOut,
                                  child: Container(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.block,
                                    ),
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
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
        _speechError = null;
        if (refreshedSession != null) {
          _session = refreshedSession;
        }
        _reconcileSubmittedApprovalState();
      });
      if (shouldAutoScroll) {
        _jumpToBottom();
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
        if (latestAssistantMessage != null) {
          _maybeAutoSpeakAssistantMessage(latestAssistantMessage.id);
          _maybeNotifyAssistantMessage(latestAssistantMessage.id);
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
        _pendingApproval = approval;
        _session = _session.copyWith(
          updatedAt: DateTime.now(),
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
                _setSpeechStatus(null);
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
          _setSpeechStatus(_systemSpeechUnavailableLabel());
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
        _setSpeechStatus(
          ready ? null : context.l10n.microphonePermissionMissing,
        );
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
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
            _clearTransientTtsStatus();
          });
        },
        onCancel: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
            _clearTransientTtsStatus();
          });
        },
        onError: (message) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
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
          _setSpeechStatus(_systemSpeechUnavailableLabel());
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
    if (!_speechReady) {
      setState(() {
        _setSpeechStatus(context.l10n.reinitializingVoiceInput);
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
      } else {
        await _stopRecordingAndTranscribe();
      }
      return;
    }

    setState(() {
      _speechError = null;
      _setSpeechStatus(context.l10n.voiceInputInProgress);
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
                _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
                _speechError = null;
              }
            });
          },
        );
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

    final transcript = _recognizedSpeech.trim();
    _recognizedSpeech = '';
    if (!mounted) {
      return;
    }
    if (transcript.isEmpty) {
      setState(() {
        _isListening = false;
        _speechError = context.l10n.voiceTranscriptionNoResult;
      });
      return;
    }
    setState(() {
      _isListening = false;
      _controller.text = transcript;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _setSpeechStatus(context.l10n.voiceTranscriptionComplete);
      _speechError = null;
    });
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
    if (!_ttsReady) {
      setState(() {
        _setSpeechStatus(context.l10n.reinitializingTts);
        _speechError = null;
      });
      await _initializeTts();
      if (!_ttsReady) {
        return;
      }
    }

    setState(() {
      _speechError = null;
      _clearTransientTtsStatus();
    });
    try {
      await _ttsService.speak(content);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechError = context.l10n.ttsPlaybackFailed('$error');
      });
    }
  }

  void _maybeAutoSpeakAssistantMessage(String messageId) {
    if (!appSettingsController.settings.autoSpeakReplies ||
        _isSpeaking ||
        !_ttsReady) {
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
    if (content.isEmpty || _autoSpokenAssistantMessageIds.contains(messageId)) {
      return;
    }
    if (_session.status == SessionStatus.running) {
      return;
    }
    _autoSpokenAssistantMessageIds.add(messageId);
    unawaited(_speakMessage(content));
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

  Future<void> _submitLocalMessage(
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
      );
      if (!mounted) {
        return;
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
        _syncVisibleTurnWindow(
          previousTotalTurns: previousTurnCountAfterLocalInsert,
        );
      });
      _syncSessionSummaryCache();
    } catch (error) {
      if (!mounted) {
        return;
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
        _setSpeechStatus(context.l10n.replyStopped);
        _session = _session.copyWith(
          status: SessionStatus.idle,
          updatedAt: DateTime.now(),
          clearPendingApproval: true,
        );
      });
      _syncSessionSummaryCache();
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
