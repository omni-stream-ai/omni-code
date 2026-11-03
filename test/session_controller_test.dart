import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/session_controller.dart';

void main() {
  test('applies a contiguous turn event without reloading the snapshot',
      () async {
    final client = _DomainClient(_state(cursor: 1));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });

    await controller.start();
    client.events.add({
      'event_id': 2,
      'payload': {
        'session': _sessionJson(version: 2, activeTurnId: 'turn-1'),
        'turn': _turnJson(),
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(client.snapshotLoads, 1);
    expect(controller.state!.cursor, 2);
    expect(controller.state!.turns.single.id, 'turn-1');
  });

  test('a coalesced cursor jump applies its authoritative snapshot', () async {
    final client = _DomainClient(_state(cursor: 1));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });

    await controller.start();
    client.events.add({
      'event_id': 4,
      'payload': {
        'coalesced': true,
        'session': _sessionJson(version: 4, activeTurnId: 'turn-1'),
        'turn': _turnJson(),
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(client.snapshotLoads, 1);
    expect(controller.state!.cursor, 4);
    expect(controller.state!.turns.single.id, 'turn-1');
  });

  test('an unmarked cursor gap still triggers snapshot recovery', () async {
    final client = _DomainClient(_state(cursor: 1));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });

    await controller.start();
    client.nextState =
        _state(cursor: 4, turns: [DomainTurn.fromJson(_turnJson())]);
    client.events.add({'event_id': 4, 'payload': <String, dynamic>{}});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(client.snapshotLoads, 2);
    expect(controller.state!.cursor, 4);
  });

  test('reset event recovers even when its id is behind the current cursor',
      () async {
    final client = _DomainClient(_state(cursor: 20));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });

    await controller.start();
    client.nextState = _state(cursor: 30);
    client.events.add({
      'event_id': 2,
      'event_type': 'stream.reset_required',
      'payload': <String, dynamic>{},
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(client.snapshotLoads, 2);
    expect(controller.state!.cursor, 30);
  });

  test('send reconciles an accepted turn when its stream event is missed',
      () async {
    final client = _DomainClient(_state(cursor: 1));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });

    await controller.start();
    client.nextState =
        _state(cursor: 2, turns: [DomainTurn.fromJson(_turnJson())]);
    await controller.send(
      'hello',
      commandId: 'command-1',
      turnId: 'turn-1',
      userMessageId: 'user-1',
    );

    expect(client.turnCreates, 1);
    expect(client.snapshotLoads, 2);
    expect(controller.state!.turns.single.userMessage.id, 'user-1');
    expect(controller.queuedCommands, isEmpty);
  });
  test(
      'execution check refreshes authoritative state without creating another turn',
      () async {
    final client = _DomainClient(_state(
        cursor: 1,
        activeTurnId: 'turn-1',
        turns: [DomainTurn.fromJson(_turnJson())]));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });
    await controller.start();
    expect(await controller.checkExecution('turn-1'), isTrue);
    expect(client.executionChecks, ['turn-1']);
    expect(client.snapshotLoads, 2);
    expect(client.cancelledTurns, isEmpty);
    expect(client.turnCreates, 0);
  });

  test(
      'recovery conditionally cancels the selected turn then sends one fresh continuation',
      () async {
    final original = DomainTurn.fromJson(_turnJson());
    final client = _DomainClient(
        _state(cursor: 1, activeTurnId: 'turn-1', turns: [original]));
    client.acceptCreatedTurns = true;
    client.stateAfterCancel = _state(cursor: 2, turns: [
      DomainTurn.fromJson({..._turnJson(), 'status': 'cancelled', 'version': 2})
    ]);
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });
    await controller.start();
    await controller.stopAndContinue('turn-1',
        'Continue remaining work without repeating completed commands');
    expect(client.cancelledTurns, ['turn-1']);
    expect(client.turnCreates, 1);
    expect(client.createdCommands.single.content,
        startsWith('Continue remaining'));
    expect(client.createdCommands.single.turnId, isNot('turn-1'));
    expect(client.createdCommands.single.userMessageId, isNot('user-1'));
    expect(controller.state!.turns.first.userMessage.content,
        original.userMessage.content);
    expect(controller.state!.turns.first.status, DomainTurnStatus.cancelled);
    expect(controller.state!.turns, hasLength(2));
  });

  test('an old recovery action never cancels or resends the current turn',
      () async {
    final client = _DomainClient(_state(cursor: 2, activeTurnId: 'turn-2'));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });
    await controller.start();
    await expectLater(
        controller.stopAndContinue('turn-1', 'continue'), throwsStateError);
    expect(client.cancelledTurns, isEmpty);
    expect(client.turnCreates, 0);
  });

  test('an unconfirmed cancellation never starts another turn', () async {
    final client = _DomainClient(_state(
        cursor: 1,
        activeTurnId: 'turn-1',
        turns: [DomainTurn.fromJson(_turnJson())]));
    final controller =
        SessionController(client: client, sessionId: 'session-1');
    addTearDown(() async {
      controller.dispose();
      await client.close();
    });
    await controller.start();
    await expectLater(
        controller.stopAndContinue('turn-1', 'continue'), throwsStateError);
    expect(client.cancelledTurns, ['turn-1']);
    expect(client.turnCreates, 0);
  });
}

class _DomainClient extends BridgeClient {
  _DomainClient(this.nextState);

  DomainSessionState nextState;
  int snapshotLoads = 0;
  int turnCreates = 0;
  final executionChecks = <String>[];
  final cancelledTurns = <String?>[];
  final createdCommands = <PendingSessionCommand>[];
  DomainSessionState? stateAfterCancel;
  bool acceptCreatedTurns = false;
  final events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<DomainSessionState> getDomainSessionState(
    String sessionId, {
    int limit = 50,
    int? beforeSequence,
  }) async {
    snapshotLoads += 1;
    return nextState;
  }

  @override
  Future<Map<String, dynamic>> createDomainTurn(
    String sessionId,
    String content, {
    required String commandId,
    required String turnId,
    required String userMessageId,
    List<DomainAttachment> attachments = const [],
    String inputMode = 'text',
    String? systemPrompt,
    String? providerId,
    ReasoningEffort? reasoningEffort,
    String? model,
  }) async {
    turnCreates += 1;
    createdCommands.add(PendingSessionCommand(
        commandId: commandId,
        turnId: turnId,
        userMessageId: userMessageId,
        content: content));
    if (acceptCreatedTurns) {
      nextState =
          _state(cursor: nextState.cursor + 1, activeTurnId: turnId, turns: [
        ...nextState.turns,
        DomainTurn.fromJson({
          ..._turnJson(),
          'id': turnId,
          'sequence': nextState.turns.length + 1,
          'user_message': {
            ...(_turnJson()['user_message'] as Map<String, dynamic>),
            'id': userMessageId,
            'turn_id': turnId,
            'content': content
          }
        }),
      ]);
    }
    return {
      'data': {'accepted': true, 'turn_id': turnId},
    };
  }

  @override
  Stream<Map<String, dynamic>> subscribeToDomainSessionEvents(
    String sessionId, {
    required int after,
  }) =>
      events.stream;

  Future<void> close() => events.close();

  @override
  Future<void> recoverSessionExecution(
      String sessionId, String turnId, String content) async {
    final cancelled = await cancelReply(sessionId, expectedTurnId: turnId);
    if (!cancelled || nextState.session.activeTurnId != null) {
      throw StateError('The session is still busy');
    }
    await createDomainTurn(sessionId, content,
        commandId: 'recovery-command',
        turnId: 'recovery-turn',
        userMessageId: 'recovery-user');
  }

  @override
  Future<bool> checkSessionExecution(String sessionId, String turnId) async {
    executionChecks.add(turnId);
    return true;
  }

  @override
  Future<bool> cancelReply(String sessionId, {String? expectedTurnId}) async {
    cancelledTurns.add(expectedTurnId);
    if (stateAfterCancel != null) nextState = stateAfterCancel!;
    return true;
  }
}

DomainSessionState _state({
  required int cursor,
  String? activeTurnId,
  List<DomainTurn> turns = const [],
}) =>
    DomainSessionState(
      session: DomainSession.fromJson(
          _sessionJson(version: cursor, activeTurnId: activeTurnId)),
      turns: turns,
      cursor: cursor,
    );

Map<String, dynamic> _sessionJson({
  required int version,
  String? activeTurnId,
}) =>
    {
      'id': 'session-1',
      'project_id': 'project-1',
      'title': 'Session',
      'agent': 'codex',
      'status': activeTurnId == null ? 'idle' : 'running',
      'version': version,
      'active_turn_id': activeTurnId,
      'unread_count': 0,
      'created_at': '2026-08-11T00:00:00Z',
      'updated_at': '2026-08-11T00:00:01Z',
    };

Map<String, dynamic> _turnJson() => {
      'id': 'turn-1',
      'session_id': 'session-1',
      'sequence': 1,
      'version': 1,
      'status': 'accepted',
      'input_mode': 'text',
      'user_message': {
        'id': 'user-1',
        'turn_id': 'turn-1',
        'sequence': 1,
        'revision': 1,
        'purpose': 'user',
        'state': 'completed',
        'content': 'hello',
        'attachments': <dynamic>[],
        'created_at': '2026-08-11T00:00:00Z',
        'updated_at': '2026-08-11T00:00:00Z',
      },
      'segments': <dynamic>[],
      'artifacts': <dynamic>[],
      'created_at': '2026-08-11T00:00:00Z',
    };
