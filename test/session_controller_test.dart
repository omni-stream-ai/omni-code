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
}

class _DomainClient extends BridgeClient {
  _DomainClient(this.nextState);

  DomainSessionState nextState;
  int snapshotLoads = 0;
  int turnCreates = 0;
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
}

DomainSessionState _state({
  required int cursor,
  List<DomainTurn> turns = const [],
}) =>
    DomainSessionState(
      session: DomainSession.fromJson(_sessionJson(version: cursor)),
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
