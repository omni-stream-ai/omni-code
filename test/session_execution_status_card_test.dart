import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/widgets/session_execution_status_card.dart';

void main() {
  final now = DateTime.utc(2026, 10, 30, 15);
  ExecutionHealth health(
          {ExecutionPhase phase = ExecutionPhase.waitingForTool,
          int age = 600}) =>
      ExecutionHealth(
        phase: phase,
        phaseStartedAt: now.subtract(Duration(seconds: age)),
        lastProgressAt: now.subtract(Duration(seconds: age)),
      );
  Widget app(ExecutionHealth value,
          {Future<bool> Function()? check,
          Future<void> Function()? recover,
          DateTime Function()? clock,
          Locale locale = const Locale('en')}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: SessionExecutionStatusCard(
                health: value,
                now: clock ?? () => now,
                onCheck: check ?? () async => true,
                onStopAndContinue: recover ?? () async {})),
      );

  test(
      'execution health monitors stage deadlines without expiring approval or active output',
      () {
    expect(health(age: 119).needsAttention(now), isFalse);
    expect(health(age: 120).needsAttention(now), isTrue);
    expect(
        health(phase: ExecutionPhase.awaitingApproval, age: 86400)
            .needsAttention(now),
        isFalse);
    expect(
        ExecutionHealth(
                phase: ExecutionPhase.runningCommand,
                phaseStartedAt: now.subtract(const Duration(hours: 1)),
                lastProgressAt: now.subtract(const Duration(seconds: 10)))
            .needsAttention(now),
        isFalse);
  });

  testWidgets(
      'stalled status shows the wait reason and checks without cancelling or resending',
      (tester) async {
    var checks = 0;
    var recoveries = 0;
    await tester.pumpWidget(app(health(), check: () async {
      checks += 1;
      return true;
    }, recover: () async {
      recoveries += 1;
    }));
    expect(find.text('No recent progress'), findsOneWidget);
    expect(find.textContaining('Waiting for tool results'), findsOneWidget);
    expect(find.textContaining('10 min'), findsOneWidget);
    expect(checks, 0);
    expect(recoveries, 0);
    await tester.tap(find.byKey(const Key('session-execution-check')));
    await tester.pump();
    expect(checks, 1);
    expect(recoveries, 0);
    expect(find.textContaining('10 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'keep waiting snoozes the warning without resetting progress or executing actions',
      (tester) async {
    var time = now;
    var actions = 0;
    await tester.pumpWidget(app(health(),
        clock: () => time,
        check: () async {
          actions += 1;
          return true;
        },
        recover: () async {
          actions += 1;
        }));
    await tester.tap(find.byKey(const Key('session-execution-wait')));
    await tester.pump();
    expect(find.text('No recent progress'), findsNothing);
    expect(find.textContaining('10 min'), findsOneWidget);
    expect(actions, 0);
    time = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(find.text('No recent progress'), findsOneWidget);
    expect(find.textContaining('15 min'), findsOneWidget);
    expect(actions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('waiting for approval has no hang warning even after an hour',
      (tester) async {
    await tester.pumpWidget(
        app(health(phase: ExecutionPhase.awaitingApproval, age: 3600)));
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('No recent progress'), findsNothing);
    expect(
        find.byKey(const Key('session-execution-stop-continue')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'stop and continue requires a click and prevents duplicate recovery',
      (tester) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(app(health(), recover: () {
      calls += 1;
      return pending.future;
    }));
    expect(calls, 0);
    final button = find.byKey(const Key('session-execution-stop-continue'));
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.text('Continuing task'), findsOneWidget);
    expect(calls, 1);
    pending.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('new real progress clears the warning', (tester) async {
    await tester.pumpWidget(app(health()));
    expect(find.text('No recent progress'), findsOneWidget);
    await tester.pumpWidget(app(health(age: 0)));
    expect(find.text('No recent progress'), findsNothing);
    expect(find.text('Recent progress received'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a failed status check stays recoverable and does not hide the wait duration',
      (tester) async {
    await tester.pumpWidget(
        app(health(), check: () async => throw StateError('offline')));
    await tester.tap(find.byKey(const Key('session-execution-check')));
    await tester.pump();
    expect(find.textContaining('Unable to confirm execution status'),
        findsOneWidget);
    expect(find.textContaining('10 min'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const Key('session-execution-check')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a check that never starts or returns exposes its own timeout',
      (tester) async {
    final old = health();
    await tester.pumpWidget(app(ExecutionHealth(
        phase: old.phase,
        phaseStartedAt: old.phaseStartedAt,
        lastProgressAt: old.lastProgressAt,
        checkStartedAt: now.subtract(const Duration(seconds: 31)))));
    expect(find.textContaining('did not respond in time'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const Key('session-execution-check')))
            .onPressed,
        isNotNull);
    expect(find.textContaining('10 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('legacy snapshots exclude watchdog timestamps from effective progress',
      () {
    final began = now.subtract(const Duration(minutes: 10)).toIso8601String();
    final turn = DomainTurn.fromJson({
      'id': 'turn',
      'sequence': 1,
      'version': 1,
      'status': 'running',
      'input_mode': 'text',
      'artifacts': <dynamic>[],
      'user_message': {
        'id': 'user',
        'turn_id': 'turn',
        'sequence': 1,
        'revision': 1,
        'purpose': 'user',
        'state': 'completed',
        'content': 'Build APK',
        'attachments': <dynamic>[],
        'created_at': began,
        'updated_at': began
      },
      'segments': [
        {
          'id': 'execution',
          'sequence': 1,
          'revision': 1,
          'kind': 'execution',
          'state': 'running',
          'activities': [
            {
              'id': 'tool',
              'segment_id': 'execution',
              'revision': 1,
              'kind': 'tool_call',
              'state': 'running',
              'title': '[command:started] curl',
              'payload': <String, dynamic>{},
              'created_at': began,
              'updated_at': began
            },
            {
              'id': 'heartbeat',
              'segment_id': 'execution',
              'revision': 1,
              'kind': 'progress',
              'state': 'running',
              'title': '[status] command still running',
              'payload': <String, dynamic>{},
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String()
            },
          ]
        }
      ],
    });
    final derived = ExecutionHealth.forTurn(turn);
    expect(derived.lastProgressAt, now.subtract(const Duration(minutes: 10)));
    expect(derived.phase, ExecutionPhase.waitingForTool);
    expect(derived.needsAttention(now), isTrue);
  });

  testWidgets('Chinese recovery actions fit on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(health(), locale: const Locale('zh')));
    expect(find.text('长时间没有新进展'), findsOneWidget);
    expect(find.text('停止本轮后继续'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
