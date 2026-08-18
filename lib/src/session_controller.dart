import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'bridge_client.dart';
import 'models.dart';

enum SessionConnectionState { disconnected, connecting, connected, recovering }

class PendingSessionCommand {
  const PendingSessionCommand(
      {required this.commandId,
      required this.turnId,
      required this.userMessageId,
      required this.content});
  final String commandId, turnId, userMessageId, content;
}

class SessionController extends ChangeNotifier {
  SessionController({required BridgeClient client, required this.sessionId})
      : _client = client;

  final BridgeClient _client;
  final String sessionId;
  DomainSessionState? _state;
  DomainSessionState? get state => _state;
  SessionConnectionState connectionState = SessionConnectionState.disconnected;
  Object? error;
  final List<PendingSessionCommand> queuedCommands = [];
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _recoveryInFlight = false;
  bool _loadingOlderTurns = false;
  bool get loadingOlderTurns => _loadingOlderTurns;

  Future<void> start() async {
    final generation = ++_generation;
    connectionState = SessionConnectionState.connecting;
    error = null;
    notifyListeners();
    try {
      final snapshot = await _client.getDomainSessionState(sessionId);
      if (_disposed || generation != _generation) return;
      _state = snapshot;
      final acceptedTurnIds = snapshot.turns.map((turn) => turn.id).toSet();
      queuedCommands.removeWhere(
        (command) => acceptedTurnIds.contains(command.turnId),
      );
      connectionState = SessionConnectionState.connected;
      notifyListeners();
      _subscribe(generation, snapshot.cursor);
    } catch (value) {
      if (_disposed || generation != _generation) return;
      error = value;
      connectionState = SessionConnectionState.disconnected;
      notifyListeners();
      _scheduleRecovery(generation);
    }
  }

  Future<void> recover() async {
    if (_disposed || _recoveryInFlight) return;
    _recoveryInFlight = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    connectionState = SessionConnectionState.recovering;
    notifyListeners();
    try {
      await _subscription?.cancel();
      await start();
    } finally {
      _recoveryInFlight = false;
    }
    if (!_disposed && connectionState == SessionConnectionState.disconnected) {
      _scheduleRecovery(_generation);
    }
  }

  void _subscribe(int generation, int cursor) {
    _subscription?.cancel();
    _subscription =
        _client.subscribeToDomainSessionEvents(sessionId, after: cursor).listen(
      (event) {
        if (_disposed || generation != _generation) return;
        _applyEvent(event);
      },
      onError: (Object value) {
        if (_disposed || generation != _generation) return;
        error = value;
        _scheduleRecovery(generation);
      },
      onDone: () {
        if (!_disposed && generation == _generation) {
          _scheduleRecovery(generation);
        }
      },
      cancelOnError: true,
    );
  }

  void _scheduleRecovery(int generation) {
    if (_reconnectTimer?.isActive ?? false) return;
    final exponent = _reconnectAttempt.clamp(0, 5);
    final delay = Duration(milliseconds: 250 * (1 << exponent));
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && generation == _generation) unawaited(recover());
    });
  }

  void _applyEvent(Map<String, dynamic> event) {
    if (event['event_type'] == 'stream.reset_required') {
      unawaited(recover());
      return;
    }
    final current = _state;
    final eventId = (event['event_id'] as num?)?.toInt();
    if (current == null || eventId == null) return;
    if (eventId <= current.cursor) return;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (eventId != current.cursor + 1 && payload?['coalesced'] != true) {
      unawaited(recover());
      return;
    }
    final turnJson = payload?['turn'] as Map<String, dynamic>?;
    final sessionJson = payload?['session'] as Map<String, dynamic>?;
    if (sessionJson != null && turnJson == null) {
      _state = DomainSessionState(
        session: DomainSession.fromJson(sessionJson),
        turns: current.turns,
        cursor: eventId,
        hasMoreTurns: current.hasMoreTurns,
        nextBeforeSequence: current.nextBeforeSequence,
      );
      _markConnectionHealthy();
      notifyListeners();
      return;
    }
    if (turnJson == null || sessionJson == null) {
      unawaited(recover());
      return;
    }
    final incoming = DomainTurn.fromJson(turnJson);
    final turns = current.turns.toList(growable: true);
    final index = turns.indexWhere((turn) => turn.id == incoming.id);
    if (index >= 0) {
      if (turns[index].version <= incoming.version) turns[index] = incoming;
    } else {
      turns.add(incoming);
      turns.sort((left, right) => left.sequence.compareTo(right.sequence));
    }
    _state = DomainSessionState(
      session: DomainSession.fromJson(sessionJson),
      turns: turns,
      cursor: eventId,
      hasMoreTurns: current.hasMoreTurns,
      nextBeforeSequence: current.nextBeforeSequence,
    );
    queuedCommands.removeWhere((command) => command.turnId == incoming.id);
    _markConnectionHealthy();
    notifyListeners();
  }

  void _markConnectionHealthy() {
    _reconnectAttempt = 0;
    error = null;
    connectionState = SessionConnectionState.connected;
  }

  Future<PendingSessionCommand> send(
    String content, {
    String inputMode = 'text',
    String? systemPrompt,
    String? providerId,
    ReasoningEffort? reasoningEffort,
    String? model,
    String? commandId,
    String? turnId,
    String? userMessageId,
    List<DomainAttachment> attachments = const [],
  }) async {
    final uuid = const Uuid();
    final command = PendingSessionCommand(
      commandId: commandId ?? uuid.v4(),
      turnId: turnId ?? uuid.v4(),
      userMessageId: userMessageId ?? uuid.v4(),
      content: content,
    );
    queuedCommands.add(command);
    notifyListeners();
    try {
      await _client.createDomainTurn(
        sessionId,
        content,
        commandId: command.commandId,
        turnId: command.turnId,
        userMessageId: command.userMessageId,
        inputMode: inputMode,
        systemPrompt: systemPrompt,
        attachments: attachments,
        providerId: providerId,
        reasoningEffort: reasoningEffort,
        model: model,
      );
      final acceptedByStream = _state?.turns.any(
            (turn) =>
                turn.id == command.turnId ||
                turn.userMessage.id == command.userMessageId,
          ) ??
          false;
      if (!acceptedByStream) {
        await recover();
      }
    } catch (value) {
      queuedCommands.remove(command);
      error = value;
      notifyListeners();
      rethrow;
    }
    return command;
  }

  Future<void> loadOlderTurns() async {
    final current = _state;
    final before = current?.nextBeforeSequence;
    if (_disposed || current == null || !current.hasMoreTurns ||
        before == null || _loadingOlderTurns) {
      return;
    }
    _loadingOlderTurns = true;
    notifyListeners();
    try {
      final page = await _client.getDomainSessionState(
        sessionId,
        beforeSequence: before,
      );
      if (_disposed || _state == null) return;
      final byId = <String, DomainTurn>{
        for (final turn in page.turns) turn.id: turn,
        for (final turn in _state!.turns) turn.id: turn,
      };
      final turns = byId.values.toList()
        ..sort((left, right) => left.sequence.compareTo(right.sequence));
      _state = DomainSessionState(
        session: _state!.session,
        turns: turns,
        cursor: _state!.cursor,
        hasMoreTurns: page.hasMoreTurns,
        nextBeforeSequence: page.nextBeforeSequence,
      );
    } finally {
      _loadingOlderTurns = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
