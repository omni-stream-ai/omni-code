import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/session_detail_screen.dart';
import 'package:omni_code/src/services/audio_recording_service.dart';
import 'package:omni_code/src/services/speech_input_service.dart';
import 'package:omni_code/src/services/tts_service.dart';
import 'package:omni_code/src/settings/app_settings.dart';

const _localNotificationsChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  setUp(() {
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
    FlutterLocalNotificationsPlatform.instance =
        _FakeAndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localNotificationsChannel, (call) async {
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_localNotificationsChannel, null);
  });

  testWidgets('pressing enter sends the current draft', (tester) async {
    final sentBodies = <Map<String, dynamic>>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            '',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentBodies.add(body);
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:01.000',
                ),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byType(TextField);
    await tester.tap(input);
    await tester.pump();
    await tester.enterText(input, 'Hello from enter');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['content'], 'Hello from enter');
    expect(sentBodies.single['input_mode'], 'text');
  });

  testWidgets('session shows chat skeleton while loading messages',
      (tester) async {
    final gate = Completer<void>();
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          await gate.future;
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Loaded reply',
                  createdAt: '2026-05-09T10:00:01.000',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            '',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('session-chat-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Loaded reply'), findsOneWidget);
  });

  testWidgets('pressing shift enter does not send the current draft',
      (tester) async {
    final sentBodies = <Map<String, dynamic>>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            '',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('unexpected send', 500);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byType(TextField);
    await tester.tap(input);
    await tester.pump();
    await tester.enterText(input, 'Hello');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    final field = tester.widget<TextField>(input);
    expect(sentBodies, isEmpty);
    expect(field.controller!.text, 'Hello');
  });

  testWidgets('tool activity is shown below assistant replies', (tester) async {
    final client = _clientForMessages([
      _messageJson(
        id: 'user-1',
        sessionId: 'session-1',
        role: 'user',
        content: 'Inspect this project',
        createdAt: '2026-05-09T10:00:00.000',
      ),
      _messageJson(
        id: 'assistant-1',
        sessionId: 'session-1',
        role: 'assistant',
        content: 'I checked the relevant files.',
        createdAt: '2026-05-09T10:00:01.000',
      ),
      _messageJson(
        id: 'system-1',
        sessionId: 'session-1',
        role: 'system',
        content: '[command:completed] rg -n "tool" lib/src (exit 0)',
        createdAt: '2026-05-09T10:00:02.000',
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final assistantReply = find.text('I checked the relevant files.');
    final toolActivity = find.text('Tool activity');
    expect(assistantReply, findsOneWidget);
    expect(toolActivity, findsOneWidget);
    expect(
      tester.getTopLeft(toolActivity).dy,
      greaterThan(tester.getBottomLeft(assistantReply).dy),
    );
  });

  testWidgets('assistant replies render markdown content', (tester) async {
    final client = _clientForMessages([
      _messageJson(
        id: 'assistant-1',
        sessionId: 'session-1',
        role: 'assistant',
        content: 'Read the **guide** at [docs](https://example.com/docs).',
        createdAt: '2026-05-09T10:00:01.000',
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Read the guide at docs.'), findsOneWidget);
    expect(
      find.text('Read the **guide** at [docs](https://example.com/docs).'),
      findsNothing,
    );
  });

  testWidgets('assistant replies render styled code blocks', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final client = _clientForMessages([
        _messageJson(
          id: 'assistant-code',
          sessionId: 'session-1',
          role: 'assistant',
          content: '''
```dart
void main() {
  print("hi");
}
```
''',
          createdAt: '2026-05-09T10:00:01.000',
        ),
      ]);

      await tester.pumpWidget(
        _TestApp(
          home: SessionDetailScreen(
            session: _session(),
            client: client,
            enableSpeechServices: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('void main() {'), findsOneWidget);
      expect(find.byType(Scrollbar), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('assistant reply bubble expands on wider layouts',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = _clientForMessages([
      _messageJson(
        id: 'assistant-wide',
        sessionId: 'session-1',
        role: 'assistant',
        content:
            'This is a long assistant reply that should use more horizontal space on wider layouts. '
            'It includes enough text to wrap across multiple lines so the message bubble can grow '
            'close to its responsive maximum width instead of staying pinned to the old fixed width.',
        createdAt: '2026-05-09T10:00:01.000',
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final bubbleFinder =
        find.byKey(const ValueKey('assistant-message-bubble-assistant-wide'));
    expect(bubbleFinder, findsOneWidget);
    expect(tester.getSize(bubbleFinder).width, greaterThan(500));
    expect(tester.getSize(bubbleFinder).width, lessThanOrEqualTo(620));
  });

  testWidgets('user reply bubble expands on wider layouts', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final client = _clientForMessages([
      _messageJson(
        id: 'user-wide',
        sessionId: 'session-1',
        role: 'user',
        content:
            'This is a long user message that should use more horizontal space on wider layouts. '
            'It includes enough text to wrap across multiple lines so the message bubble can grow '
            'close to its responsive maximum width instead of staying pinned to the old fixed width.',
        createdAt: '2026-05-09T10:00:00.000',
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final bubbleFinder =
        find.byKey(const ValueKey('user-message-bubble-user-wide'));
    expect(bubbleFinder, findsOneWidget);
    expect(tester.getSize(bubbleFinder).width, greaterThan(500));
    expect(tester.getSize(bubbleFinder).width, lessThanOrEqualTo(620));
  });

  testWidgets(
      'system speech stays disabled when system providers are unavailable',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.system,
        ttsProvider: TtsProvider.system,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final speechService = _FakeSpeechInputService(initializeResult: false);
    final ttsService = _FakeTtsService(systemAvailable: false);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages([
            _messageJson(
              id: 'assistant-1',
              sessionId: 'session-1',
              role: 'assistant',
              content: 'Reply ready',
              createdAt: '2026-05-09T10:00:01.000',
            ),
          ]),
          audioRecordingService: audioService,
          speechInputService: speechService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    final voiceButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Voice input'));
    final playButton = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Play'));

    expect(voiceButton.onPressed, isNull);
    expect(playButton.onPressed, isNull);
    expect(audioService.hasPermissionCalls, 0);
    expect(
      find.text(
        'System speech is unavailable on this device. Switch providers in Settings to use cloud speech.',
      ),
      findsNothing,
    );
  });

  testWidgets(
      'disabled voice input shows system speech unavailable tooltip on tap and hides it',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.system,
        ttsProvider: TtsProvider.system,
      ),
    );
    final speechService = _FakeSpeechInputService(initializeResult: false);
    final ttsService = _FakeTtsService(systemAvailable: false);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages([
            _messageJson(
              id: 'assistant-1',
              sessionId: 'session-1',
              role: 'assistant',
              content: 'Reply ready',
              createdAt: '2026-05-09T10:00:01.000',
            ),
          ]),
          speechInputService: speechService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    const message =
        'System speech is unavailable on this device. Switch providers in Settings to use cloud speech.';
    expect(find.text(message), findsNothing);

    final voiceButtonFinder =
        find.widgetWithText(OutlinedButton, 'Voice input');
    await tester.tap(voiceButtonFinder);
    await tester.pump();

    expect(find.text(message), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text(message), findsNothing);
  });

  testWidgets('cloud speech can be enabled explicitly from settings',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.zhipu,
        ttsProvider: TtsProvider.zhipu,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final speechService = _FakeSpeechInputService(initializeResult: false);
    final ttsService = _FakeTtsService(systemAvailable: false);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages([
            _messageJson(
              id: 'assistant-1',
              sessionId: 'session-1',
              role: 'assistant',
              content: 'Reply ready',
              createdAt: '2026-05-09T10:00:01.000',
            ),
          ]),
          audioRecordingService: audioService,
          speechInputService: speechService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    final voiceButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Voice input'));
    final playButton = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Play'));

    expect(voiceButton.onPressed, isNotNull);
    expect(playButton.onPressed, isNotNull);
    expect(audioService.hasPermissionCalls, 1);
    expect(speechService.initializeCalls, 0);
  });

  testWidgets('playing TTS does not show requesting status banner',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.zhipu,
      ),
    );
    final ttsService = _FakeTtsService(systemAvailable: false);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages([
            _messageJson(
              id: 'assistant-1',
              sessionId: 'session-1',
              role: 'assistant',
              content: 'Reply ready',
              createdAt: '2026-05-09T10:00:01.000',
            ),
          ]),
          ttsService: ttsService,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Play'));
    await tester.pump();

    expect(find.text('Requesting TTS playback...'), findsNothing);
  });

  testWidgets('auto speak still triggers while app is backgrounded',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        autoSpeakReplies: true,
        asrProvider: AsrProvider.zhipu,
        ttsProvider: TtsProvider.zhipu,
      ),
    );
    final eventGate = Completer<void>();
    final ttsService = _FakeTtsService(systemAvailable: false);
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          await eventGate.future;
          return http.Response(
            _eventStreamBody([
              {
                'type': 'message_created',
                'payload': _messageJson(
                  id: 'assistant-lockscreen-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply while locked',
                  createdAt: '2026-05-09T10:00:01.000',
                ),
              },
            ]),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          ttsService: ttsService,
          audioRecordingService:
              _FakeAudioRecordingService(hasPermissionResult: true),
          speechInputService: _FakeSpeechInputService(initializeResult: false),
          enableSpeechServices: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    eventGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ttsService.spokenTexts, ['Reply while locked']);
  });

  testWidgets('awaiting approval uses consolidated status overview',
      (tester) async {
    final approval = _approvalRequest(
      requestId: 'approval-1',
      command: 'rm -rf /tmp/safe-test',
      reason: 'Needs escalation',
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session().copyWith(
            status: SessionStatus.awaitingApproval,
            pendingApproval: approval,
          ),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('session-status-overview')), findsOneWidget);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('Waiting to process approval...'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
  });

  testWidgets(
      'submitting approval enters waiting processing state and hides actions',
      (tester) async {
    final submitGate = Completer<http.Response>();
    var approvalSubmitCalls = 0;
    final approval = _approvalRequest(
      requestId: 'approval-1',
      command: 'rm -rf /tmp/safe-test',
      reason: 'Needs escalation',
    );
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            '',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path ==
                '/sessions/session-1/approvals/${approval.requestId}') {
          approvalSubmitCalls += 1;
          return submitGate.future;
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session().copyWith(
            status: SessionStatus.awaitingApproval,
            pendingApproval: approval,
          ),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pump();

    expect(approvalSubmitCalls, 1);
    expect(find.text('Processing...'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    submitGate.complete(http.Response('', 204));
    await tester.pump();

    expect(approvalSubmitCalls, 1);
    expect(find.text('Waiting for approval processing...'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
    expect(find.text('rm -rf /tmp/safe-test'), findsNothing);
  });

  testWidgets('stopped reply status auto dismisses', (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            '',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/projects/project-1/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                _sessionJson(
                  status: 'idle',
                ),
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/cancel') {
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session().copyWith(status: SessionStatus.running),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop reply'));
    await tester.pump();

    expect(find.text('Stopped this reply'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-status-overview')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('Stopped this reply'), findsNothing);
    expect(
      find.byKey(const ValueKey('session-status-overview')),
      findsNothing,
    );
  });

  testWidgets('status overview can be dismissed manually', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session().copyWith(status: SessionStatus.running),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('session-status-overview')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('session-status-overview')),
      findsNothing,
    );
  });

  testWidgets('error detail in status overview does not show copy button',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response('boom', 500);
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            '',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('session-status-overview')),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byIcon(Icons.copy), findsNothing);
    expect(find.byTooltip('Copy'), findsNothing);
  });

  testWidgets('approval resolved does not show approval granted banner',
      (tester) async {
    final approval = _approvalRequest(
      requestId: 'approval-1',
      command: 'rm -rf /tmp/safe-test',
    );
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response(
            _eventStreamBody([
              {
                'type': 'approval_resolved',
                'payload': {
                  'request_id': approval.requestId,
                  'choice': 'accept',
                },
              },
            ]),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session().copyWith(
            status: SessionStatus.awaitingApproval,
            pendingApproval: approval,
          ),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Approval granted'), findsNothing);
    expect(find.text('Waiting for approval processing...'), findsNothing);
    expect(find.text('rm -rf /tmp/safe-test'), findsNothing);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.home,
  });

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: home,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

SessionSummary _session() {
  return SessionSummary(
    id: 'session-1',
    projectId: 'project-1',
    title: 'Test Session',
    agent: AgentKind.codex,
    briefReplyMode: false,
    status: SessionStatus.idle,
    updatedAt: DateTime(2026, 5, 9, 10),
    unreadCount: 0,
    lastMessagePreview: null,
    pendingApproval: null,
  );
}

BridgeClient _clientForMessages(List<Map<String, dynamic>> messages) {
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/sessions/session-1/messages') {
        return http.Response(
          jsonEncode({'data': messages}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/sessions/session-1/events') {
        return http.Response(
          '',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response('not found', 404);
    }),
  );
}

Map<String, dynamic> _messageJson({
  required String id,
  required String sessionId,
  required String role,
  required String content,
  required String createdAt,
}) {
  return {
    'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'created_at': createdAt,
  };
}

Map<String, dynamic> _sessionJson({
  String status = 'idle',
}) {
  return {
    'id': 'session-1',
    'project_id': 'project-1',
    'title': 'Test Session',
    'agent': 'codex',
    'brief_reply_mode': false,
    'status': status,
    'updated_at': '2026-05-09T10:00:00.000',
    'unread_count': 0,
    'last_message_preview': null,
    'pending_approval': null,
  };
}

ApprovalRequest _approvalRequest({
  required String requestId,
  String? command,
  String? reason,
}) {
  return ApprovalRequest(
    requestId: requestId,
    kind: 'command',
    command: command,
    reason: reason,
    allowAcceptForSession: true,
    allowCancel: true,
    resolvable: true,
  );
}

String _eventStreamBody(List<Map<String, dynamic>> events) {
  return events
      .map((event) => 'event: session\ndata: ${jsonEncode(event)}\n\n')
      .join();
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      nextRequest.body = request.body;
      nextRequest.encoding = request.encoding;
    }
    final response = await _handler(nextRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

class _FakeAudioRecordingService extends AudioRecordingService {
  _FakeAudioRecordingService({
    required this.hasPermissionResult,
  });

  final bool hasPermissionResult;
  int hasPermissionCalls = 0;

  @override
  Future<bool> hasPermission() async {
    hasPermissionCalls += 1;
    return hasPermissionResult;
  }
}

class _FakeAndroidFlutterLocalNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    return true;
  }

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel notificationChannel,
  ) async {}

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {}
}

class _FakeSpeechInputService extends SpeechInputService {
  _FakeSpeechInputService({
    required this.initializeResult,
  });

  final bool initializeResult;
  int initializeCalls = 0;

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String error, bool permanent)? onError,
  }) async {
    initializeCalls += 1;
    return initializeResult;
  }
}

class _FakeTtsService extends TtsService {
  _FakeTtsService({
    required this.systemAvailable,
  });

  final bool systemAvailable;
  final List<String> spokenTexts = <String>[];
  int initializeCalls = 0;

  @override
  bool get isSystemTtsAvailable => systemAvailable;

  @override
  Future<void> initialize({
    void Function()? onStart,
    void Function()? onComplete,
    void Function()? onCancel,
    void Function(String message)? onError,
  }) async {
    initializeCalls += 1;
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop({bool notifyCancel = true}) async {}
}
