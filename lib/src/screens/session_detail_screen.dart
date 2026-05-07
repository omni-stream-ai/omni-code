import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_routes.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../models.dart';
import '../services/cloud_speech_service.dart';
import '../services/notification_service.dart';
import '../services/audio_recording_service.dart';
import '../services/speech_input_service.dart';
import '../services/tts_service.dart';
import '../settings/app_settings.dart';
import '../widgets/copyable_message.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.session,
    this.sessionInitializer,
  });

  static const routeName = '/session';

  final SessionSummary session;
  final Future<SessionSummary>? sessionInitializer;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with WidgetsBindingObserver {
  static const double _bottomAutoScrollThreshold = 96;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecordingService = AudioRecordingService();
  final _speechInputService = SpeechInputService();
  final _ttsService = TtsService();
  final Set<String> _autoSpokenAssistantMessageIds = <String>{};
  final Set<String> _notifiedAssistantMessageIds = <String>{};
  final Map<String, _LocalMessageDraft> _localMessageStates = {};
  late SessionSummary _session;
  final List<ChatMessage> _messages = [];
  StreamSubscription<Map<String, dynamic>>? _eventsSubscription;
  Timer? _eventsReconnectTimer;

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
  bool _appInForeground = true;
  bool _creatingSession = false;
  bool _submittingApproval = false;
  String? _submittingApprovalChoice;
  bool _cancellingReply = false;

  bool get _isSpeechReadyStatus => _speechStatus == _readySpeechStatusLabel();

  String _readySpeechStatusLabel() => context.l10n.speechReadyStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session;
    _pendingApproval = _session.pendingApproval;
    _creatingSession = widget.sessionInitializer != null;
    _initializeSpeech();
    _initializeTts();
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
    bridgeClient.syncSessionSummary(_session);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSessionBusy = _session.status == SessionStatus.running;
    final hasActiveTurn = _session.status == SessionStatus.running ||
        _session.status == SessionStatus.awaitingApproval ||
        _pendingApproval != null;
    final canCancelReply = hasActiveTurn && !_cancellingReply;
    final turns = _turns;
    final approvalCardMaxHeight = MediaQuery.of(context).size.height * 0.42;

    return Scaffold(
      appBar: AppBar(
        title: Text(_session.title),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: Column(
        children: [
          if (_creatingSession)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
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
              _pendingApproval == null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2111),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF92400E)),
              ),
              child: Text(
                l10n.waitingApprovalProcessing,
                style: const TextStyle(height: 1.4),
              ),
            ),
          if (_speechError != null ||
              (_speechStatus != null && !_isSpeechReadyStatus))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CopyableMessage(
                message: _speechError ?? _speechStatus!,
                copyLabel: context.l10n.copy,
                copiedLabel: context.l10n.copied,
                backgroundColor: _speechError == null
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF3F1D1D),
                borderColor: _speechError == null
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF7F1D1D),
                iconColor: _speechError == null
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFFFCA5A5),
                textColor: _speechError == null
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFFECACA),
              ),
            ),
          if (_pendingApproval != null)
            _buildPendingApprovalCard(approvalCardMaxHeight),
          Expanded(
            child: _creatingSession
                ? const Center(child: CircularProgressIndicator())
                : _loadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: turns.length,
                          itemBuilder: (context, index) {
                            final turn = turns[index];
                            return _buildTurn(context, turn);
                          },
                        ),
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
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
                            const SizedBox(width: 10),
                            Text(
                              l10n.waitingProcessApproval,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                      TextField(
                        controller: _controller,
                        enabled: !isSessionBusy,
                        maxLines: 4,
                        minLines: 3,
                        decoration: InputDecoration(
                          hintText: l10n.messageInputHint,
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide:
                                const BorderSide(color: Color(0xFF1E293B)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (isSessionBusy ||
                                      (!_speechReady && !_isListening))
                                  ? null
                                  : _toggleListening,
                              child: Text(
                                _isListening ? l10n.stopVoice : l10n.voiceInput,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
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

  String _agentLabel(AgentKind agent) {
    return agent.label;
  }

  Widget _buildPendingApprovalCard(double maxHeight) {
    final approval = _pendingApproval!;
    final summary = approval.reason ?? approval.command ?? approval.kind;
    final isSubmitting = _submittingApproval;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF92400E)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.agentAwaitingPermission(_agentLabel(_session.agent)),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(summary, style: const TextStyle(height: 1.4)),
                    if (approval.command != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1917),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF78350F)),
                        ),
                        child: SelectableText(
                          approval.command!,
                          style: const TextStyle(
                            color: Color(0xFFFDE68A),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                    if (!approval.resolvable) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.desktopOnlyApproval,
                        style: const TextStyle(color: Color(0xFFFDE68A)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text(context.l10n.processing),
      ],
    );
  }

  Widget _buildTurn(BuildContext context, _ConversationTurn turn) {
    final turnId = turn.id;
    final unreadCount = _unreadToolCounts[turnId] ?? 0;
    final hasHighlight = unreadCount > 0 && turnId == _activeTurnId;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (turn.userMessage != null) _buildUserMessage(turn.userMessage!),
          if (turn.toolMessages.isNotEmpty)
            _buildToolEntry(
              count: turn.toolMessages.length,
              highlighted: hasHighlight,
              onTap: () => _showAllSystemMessages(turn),
            ),
          ...turn.assistantMessages.map(_buildAssistantMessage),
        ],
      ),
    );
  }

  Widget _buildUserMessage(ChatMessage message) {
    final localState = _localMessageStates[message.id];
    final canRetry = localState?.state == _LocalMessageState.failed;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: canRetry ? () => _retryLocalMessage(message.id) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: const Color(0xFF1D4ED8),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                message.content,
                style: const TextStyle(height: 1.45),
              ),
              if (localState != null) ...[
                const SizedBox(height: 8),
                Text(
                  localState.label(context),
                  style: TextStyle(
                    fontSize: 11,
                    color: localState.state == _LocalMessageState.failed
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFBFDBFE),
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: highlighted
                    ? const Color(0xFF0C4A6E)
                    : const Color(0xFF111827),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: highlighted
                      ? const Color(0xFF7DD3FC)
                      : const Color(0xFF334155),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 12,
                    color: highlighted
                        ? const Color(0xFFE0F2FE)
                        : const Color(0xFFCBD5E1),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.toolActivity,
                    style: TextStyle(
                      color: highlighted
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFFCBD5E1),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      color: highlighted
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFF94A3B8),
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

  Widget _buildAssistantMessage(ChatMessage message) {
    final displayContent = _displayContentForMessage(message);
    final isLoadingReply = message.content.trim().isEmpty &&
        _session.status == SessionStatus.running;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF1E293B)),
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
                  const SizedBox(width: 10),
                  Text(
                    context.l10n.working,
                    style: const TextStyle(
                      height: 1.45,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              )
            else ...[
              SelectableText(
                displayContent,
                style: const TextStyle(height: 1.45),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _isSpeaking
                    ? _stopSpeaking
                    : () => _speakMessage(message.content),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF334155)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Text(
                  _isSpeaking
                      ? context.l10n.stopPlayback
                      : context.l10n.playback,
                ),
              ),
            ],
          ],
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
      final messages = await bridgeClient.listMessages(_session.id);
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
    _eventsSubscription =
        bridgeClient.subscribeToSessionEvents(_session.id).listen(
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
        bridgeClient.listMessages(_session.id),
        bridgeClient.listProjectSessions(_session.projectId,
            forceRefresh: true),
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
      });
      _maybeAutoScrollToBottom();
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
        });
        _syncSessionSummaryCache();
        break;
      case 'approval_resolved':
        final requestId = payload['request_id'] as String? ?? '';
        final choice = parseApprovalChoice(payload['choice'] as String? ?? '');
        final preview = _approvalResolvedLabel(choice);
        debugPrint(
          '[approval] resolved session=${_session.id} request=$requestId '
          'choice=${payload["choice"]}',
        );
        setState(() {
          _pendingApproval = null;
          _session = _session.copyWith(
            status: SessionStatus.running,
            updatedAt: DateTime.now(),
            lastMessagePreview: preview,
            clearPendingApproval: true,
          );
          _speechStatus = preview;
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
      await bridgeClient.submitApproval(
          _session.id, approval.requestId, choice);
      if (!mounted) {
        return;
      }
      setState(() {
        _submittingApproval = false;
        _submittingApprovalChoice = null;
        _speechError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submittingApproval = false;
        _submittingApprovalChoice = null;
        _speechError = context.l10n.approvalSubmitFailed('$error');
      });
    }
  }

  String _approvalResolvedLabel(ApprovalChoice choice) {
    switch (choice) {
      case ApprovalChoice.accept:
        return context.l10n.approvalAccepted;
      case ApprovalChoice.acceptForSession:
        return context.l10n.approvalAcceptedForSession;
      case ApprovalChoice.alwaysAllow:
        return context.l10n.approvalAlwaysAllow;
      case ApprovalChoice.decline:
        return context.l10n.approvalRejected;
      case ApprovalChoice.cancel:
        return context.l10n.approvalCancelled;
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      final useSystemSpeech =
          appSettingsController.settings.asrProvider == AsrProvider.system;
      _systemAsrUnavailable = false;
      if (useSystemSpeech) {
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
              _speechStatus = null;
              _speechError = null;
            });
            return;
          }
          _systemAsrUnavailable = true;
        } catch (_) {
          _systemAsrUnavailable = true;
        }
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
          });
        },
        onComplete: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
          });
        },
        onCancel: () {
          if (!mounted) {
            return;
          }
          setState(() {
            _isSpeaking = false;
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
      setState(() {
        _ttsReady = true;
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
      _speechStatus = context.l10n.voiceTranscriptionComplete;
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
      _speechStatus = context.l10n.requestingTts;
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
    if (!appSettingsController.settings.autoSpeakReplies || _isSpeaking) {
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
      final result = await bridgeClient.sendMessage(
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
      await bridgeClient.cancelReply(_session.id);
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

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(context.l10n.allToolActivity),
        content: SizedBox(
          width: 360,
          height: 420,
          child: ListView.separated(
            itemCount: systemMessages.length,
            itemBuilder: (context, index) => InkWell(
              onTap: () => _showToolMessageDetail(systemMessages[index]),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  _toolMessagePreview(systemMessages[index]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ),
            separatorBuilder: (_, __) => const Divider(
              height: 16,
              color: Color(0xFF1E293B),
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
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
          const SizedBox(height: 10),
          _detailRow(context.l10n.detailExtra, parsed.trailingNote!),
        ],
        const SizedBox(height: 16),
        Text(
          context.l10n.detailRawContent,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          rawContent,
          style: const TextStyle(height: 1.5),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(value, style: const TextStyle(height: 1.5)),
      ],
    );
  }

  Widget _detailList(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 8),
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
