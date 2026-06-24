import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
import 'package:omni_code/src/services/bridge_realtime_asr_service.dart';
import 'package:omni_code/src/services/speech_input_service.dart';
import 'package:omni_code/src/services/tts_service.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_spacing.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/widgets/anchored_overlay_panel.dart';
import 'package:omni_code/src/widgets/session_call_mode_view.dart';
import 'package:speech_to_text/speech_to_text.dart';

const _localNotificationsChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');

_FakeAndroidFlutterLocalNotificationsPlugin _fakeNotifications() {
  return FlutterLocalNotificationsPlatform.instance
      as _FakeAndroidFlutterLocalNotificationsPlugin;
}

bool _primaryFocusIsWithin(WidgetTester tester, Finder finder) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext == null) {
    return false;
  }
  return find
      .descendant(
        of: finder,
        matching: find.byWidget(focusedContext.widget),
      )
      .evaluate()
      .isNotEmpty;
}

Future<void> _tabUntilFocusWithin(
  WidgetTester tester,
  Finder finder, {
  required int maxTabs,
  bool reverse = false,
}) async {
  for (var i = 0; i < maxTabs; i++) {
    if (_primaryFocusIsWithin(tester, finder)) {
      return;
    }
    if (reverse) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (reverse) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.pump();
  }
}

void main() {
  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
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

  testWidgets('shows session title in the session detail header',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const []),
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Test Session'), findsOneWidget);
  });

  testWidgets('loads current session title from bridge on first open',
      (tester) async {
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
            request.url.path == '/sessions/session-1') {
          return http.Response(
            jsonEncode({
              'data': {
                'session': _sessionJson(title: 'Bridge Generated Title'),
                'git_status': null,
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
          session: _session(title: 'New session'),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Bridge Generated Title'), findsOneWidget);
  });

  testWidgets('pressing enter sends the current draft on desktop',
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
            request.url.path == '/sessions/session-1/cancel') {
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
            }),
            200,
            headers: {'content-type': 'application/json'},
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
    expect(sentBodies.single.containsKey('system_prompt'), isFalse);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets('image picker sends image markdown without text', (tester) async {
    final photo = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('omni-code-test-');
      final file = File('${dir.path}/photo.png');
      await file.writeAsBytes([1, 2, 3]);
      return file;
    });
    final sentBodies = <Map<String, dynamic>>[];
    final uploadedPaths = <String>[];
    final client = _UploadingBridgeClient(
      uploadHandler: (path) async {
        uploadedPaths.add(path);
        return const BridgeUploadResponse(
          id: 'uuid-photo.png',
          fileName: 'photo.png',
          contentType: 'image/png',
          sizeBytes: 12345,
          url: '/uploads/uuid-photo.png',
          absoluteUrl: 'http://127.0.0.1:8787/uploads/uuid-photo.png',
          localPath: '/tmp/uuid-photo.png',
        );
      },
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
                  id: 'server-user-image-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-image-1',
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
          pickImages: () async => [photo!.path],
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('session-pending-image-strip')), findsNothing);

    await tester.tap(find.byKey(const Key('session-image-picker-button')));
    await tester.pump();

    expect(
        find.byKey(const Key('session-pending-image-strip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    for (var i = 0; i < 20 && sentBodies.isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sentBodies, hasLength(1));
    expect(uploadedPaths, [photo!.path]);
    expect(sentBodies.single['content'], '![photo.png](/tmp/uuid-photo.png)');
    expect(sentBodies.single['input_mode'], 'text');
    expect(find.byKey(const Key('session-pending-image-strip')), findsNothing);
  });

  testWidgets('text and picked images send together', (tester) async {
    final files = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('omni-code-test-');
      final photo = File('${dir.path}/photo.png');
      final report = File('${dir.path}/report.pdf');
      await photo.writeAsBytes([1, 2, 3]);
      await report.writeAsBytes([4, 5, 6]);
      return [photo, report];
    });
    final sentBodies = <Map<String, dynamic>>[];
    var uploadCount = 0;
    final uploadedPaths = <String>[];
    final client = _UploadingBridgeClient(
      uploadHandler: (path) async {
        uploadedPaths.add(path);
        uploadCount += 1;
        final fileName = uploadCount == 1 ? 'photo.png' : 'report.pdf';
        final contentType = uploadCount == 1 ? 'image/png' : 'application/pdf';
        return BridgeUploadResponse(
          id: 'uuid-$fileName',
          fileName: fileName,
          contentType: contentType,
          sizeBytes: uploadCount,
          url: '/uploads/uuid-$fileName',
          absoluteUrl: 'http://127.0.0.1:8787/uploads/uuid-$fileName',
          localPath: '/tmp/uuid-$fileName',
        );
      },
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
                  id: 'server-user-image-2',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-image-2',
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
          pickImages: () async => files!.map((file) => file.path).toList(),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('session-message-input')),
      'Please inspect these images',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-image-picker-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    for (var i = 0; i < 20 && sentBodies.isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(sentBodies, hasLength(1));
    expect(
      sentBodies.single['content'],
      'Please inspect these images\n\n'
      '![photo.png](/tmp/uuid-photo.png)\n'
      '[report.pdf](/tmp/uuid-report.pdf)',
    );
    expect(uploadCount, 2);
    expect(uploadedPaths, files!.map((file) => file.path).toList());
  });

  testWidgets('pasted file path is inserted as text', (tester) async {
    final files = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('omni-code-test-');
      final report = File('${dir.path}/report.pdf');
      await report.writeAsBytes([4, 5, 6]);
      return [report];
    });
    final sentBodies = <Map<String, dynamic>>[];
    var uploadCount = 0;
    final client = _UploadingBridgeClient(
      uploadHandler: (path) async {
        uploadCount += 1;
        return const BridgeUploadResponse(
          id: 'uuid-report.pdf',
          fileName: 'report.pdf',
          contentType: 'application/pdf',
          sizeBytes: 3,
          url: '/uploads/uuid-report.pdf',
          absoluteUrl: 'http://127.0.0.1:8787/uploads/uuid-report.pdf',
        );
      },
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
                  id: 'server-user-file-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-file-1',
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
          readClipboardText: () async => files!.single.path,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-message-input')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const Key('session-pending-image-strip')), findsNothing);

    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    for (var i = 0; i < 20 && sentBodies.isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(uploadCount, 0);
    expect(sentBodies.single['content'], files!.single.path);
  });

  testWidgets('pasted plain text with slash is not treated as file',
      (tester) async {
    final sentBodies = <Map<String, dynamic>>[];
    var uploadCount = 0;
    final client = _UploadingBridgeClient(
      uploadHandler: (path) async {
        uploadCount += 1;
        return const BridgeUploadResponse(
          id: 'unexpected-upload',
          fileName: 'unexpected.txt',
          contentType: 'text/plain',
          sizeBytes: 3,
          url: '/uploads/unexpected-upload',
          absoluteUrl: 'http://127.0.0.1:8787/uploads/unexpected-upload',
        );
      },
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
                  id: 'server-user-text-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-text-1',
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
          readClipboardText: () async => '随便粘贴一点文本 / 不是文件路径',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-message-input')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const Key('session-pending-image-strip')), findsNothing);

    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    for (var i = 0; i < 20 && sentBodies.isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(uploadCount, 0);
    expect(
      sentBodies.single['content'],
      '随便粘贴一点文本 / 不是文件路径',
    );
  });

  testWidgets('pasted image attachment is queued and uploaded', (tester) async {
    final files = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('omni-code-test-');
      final image = File('${dir.path}/clipboard.png');
      await image.writeAsBytes([1, 2, 3]);
      return [image];
    });
    final sentBodies = <Map<String, dynamic>>[];
    var uploadCount = 0;
    final client = _UploadingBridgeClient(
      uploadHandler: (path) async {
        uploadCount += 1;
        expect(path, files!.single.path);
        return const BridgeUploadResponse(
          id: 'uuid-clipboard.png',
          fileName: 'clipboard.png',
          contentType: 'image/png',
          sizeBytes: 3,
          url: '/uploads/uuid-clipboard.png',
          absoluteUrl: 'http://127.0.0.1:8787/uploads/uuid-clipboard.png',
          localPath: '/tmp/uuid-clipboard.png',
        );
      },
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
                  id: 'server-user-clipboard-image-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-clipboard-image-1',
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
          readClipboardAttachments: () async =>
              files!.map((file) => file.path).toList(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-message-input')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
        find.byKey(const Key('session-pending-image-strip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    for (var i = 0; i < 20 && sentBodies.isEmpty; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(uploadCount, 1);
    expect(sentBodies.single['content'],
        '![clipboard.png](/tmp/uuid-clipboard.png)');
  });

  testWidgets('slash input shows command suggestions', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'kind': 'codex',
                  'commands': [
                    {
                      'name': '/review',
                      'description': 'Review the diff',
                      'aliases': ['/rev'],
                    },
                    {
                      'name': '/summarize',
                      'description': 'Summarize the current changes',
                    },
                  ],
                },
              ],
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

    await tester.tap(find.byKey(const Key('session-message-input')));
    await tester.enterText(find.byKey(const Key('session-message-input')), '/');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
        find.byKey(const Key('session-command-suggestions')), findsOneWidget);
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('Review the diff'), findsOneWidget);
    expect(find.text('/summarize'), findsOneWidget);
  });

  testWidgets('command suggestions overlay does not change composer height',
      (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'kind': 'codex',
                  'commands': [
                    {
                      'name': '/review',
                      'description': 'Review the diff',
                    },
                  ],
                },
              ],
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

    final composer = find.byKey(const Key('session-message-composer'));
    final input = find.byKey(const Key('session-message-input'));

    await tester.tap(input);
    await tester.pump();
    final expandedHeight = tester.getSize(composer).height;

    await tester.enterText(input, '/');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      tester.getSize(composer).height,
      expandedHeight,
    );
    expect(
      find.byKey(const Key('session-command-suggestions')),
      findsOneWidget,
    );
  });

  testWidgets('anchored overlay flips above when bottom space is tight',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      _TestApp(
        home: Scaffold(
          body: _AnchoredOverlayTestHost(
            targetKey: targetKey,
            child: Container(
              key: const Key('anchored-overlay-test-panel'),
              height: 120,
              color: Colors.red,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final targetRect = tester.getRect(find.byKey(targetKey));
    final panelRect =
        tester.getRect(find.byKey(const Key('anchored-overlay-test-panel')));

    expect(panelRect.bottom, lessThanOrEqualTo(targetRect.top));
  });

  testWidgets('anchored overlay keeps tight gap above for short content',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      _TestApp(
        home: Scaffold(
          body: _AnchoredOverlayTestHost(
            targetKey: targetKey,
            child: Container(
              key: const Key('anchored-overlay-short-test-panel'),
              height: 36,
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final targetRect = tester.getRect(find.byKey(targetKey));
    final panelRect = tester.getRect(
      find.byKey(const Key('anchored-overlay-short-test-panel')),
    );

    expect(targetRect.top - panelRect.bottom, AppSpacing.compact);
  });

  testWidgets('anchored overlay aligns to target right edge near screen edge',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      _TestApp(
        home: Scaffold(
          body: _AnchoredOverlayTestHost(
            targetKey: targetKey,
            alignment: Alignment.bottomRight,
            child: Container(
              key: const Key('anchored-overlay-right-edge-test-panel'),
              height: 60,
              color: Colors.green,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final targetRect = tester.getRect(find.byKey(targetKey));
    final panelRect = tester.getRect(
      find.byKey(const Key('anchored-overlay-right-edge-test-panel')),
    );

    expect(panelRect.right, 800 - AppSpacing.screenX);
    expect(panelRect.right, lessThanOrEqualTo(targetRect.right));
    expect(panelRect.left, greaterThanOrEqualTo(AppSpacing.screenX));
  });

  testWidgets('anchored overlay prefers target width before max width',
      (tester) async {
    final targetKey = GlobalKey();

    await tester.pumpWidget(
      _TestApp(
        home: Scaffold(
          body: _AnchoredOverlayTestHost(
            targetKey: targetKey,
            child: Container(
              key: const Key('anchored-overlay-width-test-panel'),
              height: 60,
              color: Colors.orange,
            ),
            overlayBuilder: (targetKey, child) => AnchoredOverlayPanel(
              targetKey: targetKey,
              maxWidth: 760,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final targetRect = tester.getRect(find.byKey(targetKey));
    final panelRect = tester.getRect(
      find.byKey(const Key('anchored-overlay-width-test-panel')),
    );

    expect(panelRect.width, 240);
    expect(panelRect.width, lessThan(760));
    expect(panelRect.width, greaterThanOrEqualTo(targetRect.width));
  });

  testWidgets('pressing enter accepts selected command suggestion',
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'kind': 'codex',
                  'commands': [
                    {
                      'name': '/review',
                      'description': 'Review the diff',
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: '/review',
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, '/');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tester.widget<TextField>(input).controller!.text, '/review ');
    expect(sentBodies, isEmpty);
  },
      variant:
          const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('at input shows file suggestions', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/files/completions') {
          expect(request.url.queryParameters['prefix'], 'lib/src/scr');
          expect(request.url.queryParameters['session_id'], 'session-1');
          return http.Response(
            jsonEncode({
              'data': [
                {'path': 'lib/src/screens/', 'is_dir': true},
                {
                  'path': 'lib/src/screens/session_detail_screen.dart',
                  'is_dir': false,
                },
              ],
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, 'open @lib/src/scr');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('session-file-suggestions')), findsOneWidget);
    expect(find.text('lib/src/screens/'), findsOneWidget);
    expect(
      find.text('lib/src/screens/session_detail_screen.dart'),
      findsOneWidget,
    );
  });

  testWidgets('at input filters broad file suggestions locally', (
    tester,
  ) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/files/completions') {
          return http.Response(
            jsonEncode({
              'data': [
                {'path': 'README.md', 'is_dir': false},
                {'path': 'lib/', 'is_dir': true},
                {'path': 'lib/src/screens/', 'is_dir': true},
                {'path': 'assets/app-icon.svg', 'is_dir': false},
              ],
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, 'open @lib');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('session-file-suggestions')), findsOneWidget);
    expect(find.text('lib/'), findsOneWidget);
    expect(find.text('lib/src/screens/'), findsOneWidget);
    expect(find.text('README.md'), findsNothing);
    expect(find.text('assets/app-icon.svg'), findsNothing);
  });

  testWidgets('bare at shows root file suggestions', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/files/completions') {
          expect(request.url.queryParameters['prefix'], '');
          expect(request.url.queryParameters['session_id'], 'session-1');
          return http.Response(
            jsonEncode({
              'data': [
                {'path': 'lib/', 'is_dir': true},
                {'path': 'README.md', 'is_dir': false},
              ],
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, '@');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('session-file-suggestions')), findsOneWidget);
    expect(find.text('lib/'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
  });

  testWidgets('dot-prefixed at input shows hidden file suggestions', (
    tester,
  ) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/files/completions') {
          expect(request.url.queryParameters['prefix'], '.');
          return http.Response(
            jsonEncode({
              'data': [
                {'path': '.github/', 'is_dir': true},
                {'path': '.gitignore', 'is_dir': false},
              ],
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, '@.');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('session-file-suggestions')), findsOneWidget);
    expect(find.text('.github/'), findsOneWidget);
    expect(find.text('.gitignore'), findsOneWidget);
  });

  testWidgets('inline at text does not show file suggestions', (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/files/completions') {
          fail('should not request file completions for inline @ text');
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, 'email foo@bar');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('session-file-suggestions')), findsNothing);
  });

  testWidgets('pressing enter accepts selected file suggestion',
      (tester) async {
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
        if (request.method == 'GET' && request.url.path == '/agents/commands') {
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/files/completions') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'path': 'lib/src/screens/session_detail_screen.dart',
                  'is_dir': false,
                },
              ],
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.enterText(input, 'open @lib/src/scr');
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      tester.widget<TextField>(input).controller!.text,
      'open @lib/src/screens/session_detail_screen.dart',
    );
  },
      variant:
          const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('composer focus stays in input after send', (tester) async {
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
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: 'Focus flow',
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
    await tester.pump();

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(
      input,
      'Focus flow',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    await tester.pump();

    expect(_primaryFocusIsWithin(tester, input), isTrue);
  });

  testWidgets('composer focus returns to input when reply finishes',
      (tester) async {
    final events = StreamController<List<int>>();
    final client = BridgeClient(
      httpClient: _StreamingEventHttpClient(
        events: events.stream,
        handler: (request) async {
          if (request.method == 'GET' &&
              request.url.path == '/sessions/session-1/messages') {
            return http.Response(
              jsonEncode({'data': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/sessions/session-1/messages') {
            return http.Response(
              jsonEncode({
                'data': {
                  'user_message': _messageJson(
                    id: 'server-user-1',
                    sessionId: 'session-1',
                    role: 'user',
                    content: 'Focus flow',
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
        },
      ),
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(
      input,
      'Focus flow',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    await tester.pump();

    expect(_primaryFocusIsWithin(tester, input), isTrue);

    events.add(
      utf8.encode(
        _eventStreamBody([
          {
            'type': 'session_status',
            'payload': {'status': 'idle'},
          }
        ]),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'session-message-input-focus',
    );

    await events.close();
  });

  testWidgets('approval focus moves to primary action then back to stop',
      (tester) async {
    var approvalSubmitCalls = 0;
    final approval = _approvalRequest(
      requestId: 'approval-1',
      command: 'run tests',
    );
    final events = StreamController<List<int>>();
    final client = BridgeClient(
      httpClient: _StreamingEventHttpClient(
        events: events.stream,
        handler: (request) async {
          if (request.method == 'GET' &&
              request.url.path == '/sessions/session-1/messages') {
            return http.Response(
              jsonEncode({'data': []}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path ==
                  '/sessions/session-1/approvals/${approval.requestId}') {
            approvalSubmitCalls += 1;
            return http.Response(
              jsonEncode({
                'data': {'ok': true}
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        },
      ),
    );

    void sendApprovalEvent(Map<String, dynamic> event) {
      events.add(utf8.encode(_eventStreamBody([event])));
    }

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

    sendApprovalEvent({
      'type': 'approval_requested',
      'payload': {
        'request': {
          'request_id': approval.requestId,
          'kind': approval.kind,
          'command': approval.command,
          'reason': approval.reason,
          'allow_accept_for_session': approval.allowAcceptForSession,
          'allow_cancel': approval.allowCancel,
          'resolvable': approval.resolvable,
        },
      },
    });
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'session-approval-primary-focus',
    );

    await tester.tap(find.byKey(const Key('session-approval-accept-button')));
    await tester.pump();
    await tester.pump();

    expect(approvalSubmitCalls, 1);

    sendApprovalEvent({
      'type': 'approval_resolved',
      'payload': {
        'request_id': approval.requestId,
        'choice': 'accept',
      },
    });
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'session-stop-reply-focus',
    );

    await events.close();
  });

  testWidgets('voice input action is embedded at the end of the message field',
      (tester) async {
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
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('session-voice-mode-toggle')), findsOneWidget);
    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);
    expect(
        find.byKey(const Key('session-image-picker-button')), findsOneWidget);
    expect(find.byKey(const Key('session-send-button')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('session-voice-mode-toggle'))).height,
      tester
          .getSize(find.byKey(const Key('session-text-composer-surface')))
          .height,
    );

    await tester.enterText(
      find.byKey(const Key('session-message-input')),
      'Ready to send',
    );
    await tester.pump();

    expect(find.byKey(const Key('session-voice-mode-toggle')), findsNothing);
    expect(find.byKey(const Key('session-voice-input-button')), findsNothing);
    expect(find.byKey(const Key('session-send-button')), findsOneWidget);
  });

  testWidgets('can queue another message while waiting for bridge reply',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
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
          sendBodies.add(body);
          if (sendBodies.length == 1) {
            return firstSendCompleter.future;
          }
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    expect(sendBodies, hasLength(1));
    expect(find.text('First message'), findsOneWidget);

    await tester.enterText(input, 'Second message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    final l10n = AppLocalizations.of(tester.element(input))!;
    expect(sendBodies, hasLength(1));
    expect(find.text('Second message'), findsOneWidget);
    expect(find.text(l10n.draftPending), findsNWidgets(2));
  });

  testWidgets('submitting a message immediately shows pending state',
      (tester) async {
    final firstSendCompleter = Completer<http.Response>();
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
          return firstSendCompleter.future;
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    final l10n = AppLocalizations.of(tester.element(input))!;
    expect(find.text('First message'), findsOneWidget);
    expect(find.text(l10n.draftPending), findsOneWidget);
    expect(find.byKey(const Key('session-stop-reply-button')), findsOneWidget);
  });

  testWidgets('composer tab navigation still works while waiting for reply',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
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
          sendBodies.add(body);
          if (sendBodies.length == 1) {
            return firstSendCompleter.future;
          }
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.pump();
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    expect(sendBodies, hasLength(1));
    expect(find.byKey(const Key('session-image-picker-button')), findsOneWidget);
    expect(find.byKey(const Key('session-stop-reply-button')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-stop-reply-button')),
      ),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-image-picker-button')),
      ),
      isTrue,
    );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('stopping a waiting local message restores it to the composer',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
    var cancelCalls = 0;
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
          sendBodies.add(body);
          return firstSendCompleter.future;
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/cancel') {
          cancelCalls += 1;
          return http.Response('', 204);
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'Interrupt me');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    expect(sendBodies, hasLength(1));
    expect(find.text('Interrupt me'), findsOneWidget);
    expect(find.byKey(const Key('session-stop-reply-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-stop-reply-button')));
    await tester.pump();

    expect(cancelCalls, 0);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-bubble-local-'),
      ),
      findsNothing,
    );
    expect(tester.widget<TextField>(input).controller?.text, 'Interrupt me');
  });

  testWidgets('stopping after reply starts sends cancel request',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    var cancelCalls = 0;
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
          sendBodies.add(body);
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:01.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:02.000',
                ),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/cancel') {
          cancelCalls += 1;
          return http.Response('', 204);
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'Interrupt after running');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    expect(sendBodies, hasLength(1));
    expect(find.byKey(const Key('session-stop-reply-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-stop-reply-button')));
    await tester.pump();

    expect(cancelCalls, 1);
  });

  testWidgets('queued message can be edited back into the composer',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
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
          sendBodies.add(body);
          if (sendBodies.length == 1) {
            return firstSendCompleter.future;
          }
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    await tester.enterText(input, 'Queued draft');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    expect(sendBodies, hasLength(1));
    expect(find.text('Queued draft'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('Queued draft'),
        matching: find.byType(GestureDetector),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(tester.element(input))!;
    expect(find.text('Queued draft'), findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller?.text,
      'Queued draft',
    );
    expect(find.text(l10n.draftPending), findsOneWidget);
  });

  testWidgets('withdrawing a queued message removes it and all following messages',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
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
          sendBodies.add(body);
          if (sendBodies.length == 1) {
            return firstSendCompleter.future;
          }
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    await tester.enterText(input, 'Queued one');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    await tester.enterText(input, 'Queued two');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    final queuedHoverRegion = find.ancestor(
      of: find.text('Queued one'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-hover-'),
      ),
    );
    await mouse.moveTo(tester.getCenter(queuedHoverRegion));
    await tester.pump();

    final withdrawAction = find.byKey(
      const Key('user-message-withdraw-action'),
    );
    expect(withdrawAction.first, findsOneWidget);
    await tester.tap(withdrawAction.first);
    await tester.pump();

    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Queued one'), findsNothing);
    expect(find.text('Queued two'), findsNothing);
    expect(tester.widget<TextField>(input).controller?.text, isEmpty);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('composer action icons are reachable by tab', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.pump();
    await tester.enterText(input, 'Tab flow');
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'session-message-input-focus',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('session-message-input-focus'),
    );
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-image-picker-button')),
      ),
      isTrue,
    );

    await _tabUntilFocusWithin(
      tester,
      find.byKey(const Key('session-send-button')),
      maxTabs: 3,
    );
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-send-button')),
      ),
      isTrue,
    );

    await _tabUntilFocusWithin(
      tester,
      input,
      maxTabs: 3,
    );
    expect(
      _primaryFocusIsWithin(tester, input),
      isTrue,
    );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('composer stays expanded while action buttons are focused',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.pump();

    expect(find.byKey(const Key('session-send-button')), findsNothing);

    await tester.enterText(input, 'Tab flow');
    await tester.pump();
    expect(find.byKey(const Key('session-send-button')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(find.byKey(const Key('session-send-button')), findsOneWidget);
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-image-picker-button')),
      ),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(find.byKey(const Key('session-send-button')), findsOneWidget);
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-send-button')),
      ),
      isTrue,
    );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('composer action icons are reachable by shift tab in reverse',
      (tester) async {
    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byKey(const Key('session-message-input'));
    await tester.tap(input);
    await tester.pump();
    await tester.enterText(input, 'Reverse tab flow');
    await tester.pump();

    await _tabUntilFocusWithin(
      tester,
      find.byKey(const Key('session-send-button')),
      maxTabs: 4,
    );

    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-send-button')),
      ),
      isTrue,
    );

    await _tabUntilFocusWithin(
      tester,
      find.byKey(const Key('session-image-picker-button')),
      maxTabs: 3,
      reverse: true,
    );
    expect(
      _primaryFocusIsWithin(
        tester,
        find.byKey(const Key('session-image-picker-button')),
      ),
      isTrue,
    );

    await _tabUntilFocusWithin(
      tester,
      input,
      maxTabs: 3,
      reverse: true,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'session-message-input-focus',
    );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('tool activity stays with active reply turn when a queued message exists',
      (tester) async {
    final events = StreamController<List<int>>();
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
    final client = BridgeClient(
      httpClient: _StreamingEventHttpClient(
        events: events.stream,
        handler: (request) async {
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
          sendBodies.add(body);
          if (sendBodies.length == 1) {
            return firstSendCompleter.future;
          }
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
                ),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
          return http.Response('not found', 404);
        },
      ),
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    await tester.enterText(input, 'Second message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    events.add(
      utf8.encode(
        _eventStreamBody([
          {
            'type': 'message_created',
            'payload': _messageJson(
              id: 'assistant-tool-anchor',
              sessionId: 'session-1',
              role: 'assistant',
              content: 'Still working',
              createdAt: '2026-05-09T10:00:02.000',
            ),
          },
          {
            'type': 'message_created',
            'payload': _messageJson(
              id: 'system-tool-1',
              sessionId: 'session-1',
              role: 'system',
              content: '[command:completed] ls',
              createdAt: '2026-05-09T10:00:03.000',
            ),
          },
        ]),
      ),
    );
    await tester.pump();
    await tester.pump();

    final toolChip = find.ancestor(
      of: find.byIcon(Icons.build_outlined),
      matching: find.byType(InkWell),
    ).first;
    final firstMessageBubble = find.ancestor(
      of: find.text('First message'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-bubble-'),
      ),
    ).first;
    final secondMessageBubble = find.ancestor(
      of: find.text('Second message'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-bubble-'),
      ),
    ).first;

    expect(
      find.descendant(
        of: firstMessageBubble,
        matching: find.byIcon(Icons.build_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: secondMessageBubble,
        matching: find.byIcon(Icons.build_outlined),
      ),
      findsNothing,
    );
    expect(tester.getTopLeft(toolChip).dy, greaterThan(0));

    await events.close();
  });

  testWidgets('queued follow-up message stays visually after the active reply turn',
      (tester) async {
    final events = StreamController<List<int>>();
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
    final client = BridgeClient(
      httpClient: _StreamingEventHttpClient(
        events: events.stream,
        handler: (request) async {
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
            sendBodies.add(body);
            if (sendBodies.length == 1) {
              return firstSendCompleter.future;
            }
            return http.Response(
              jsonEncode({
                'data': {
                  'user_message': _messageJson(
                    id: 'server-user-${sendBodies.length}',
                    sessionId: 'session-1',
                    role: 'user',
                    content: body['content'] as String,
                    createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                  ),
                  'reply': _messageJson(
                    id: 'server-reply-${sendBodies.length}',
                    sessionId: 'session-1',
                    role: 'assistant',
                    content: '',
                    createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
                  ),
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        },
      ),
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    await tester.enterText(input, 'Second message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    events.add(
      utf8.encode(
        _eventStreamBody([
          {
            'type': 'message_created',
            'payload': _messageJson(
              id: 'assistant-tool-anchor-2',
              sessionId: 'session-1',
              role: 'assistant',
              content: 'Still working',
              createdAt: '2026-05-09T10:00:02.000',
            ),
          },
          {
            'type': 'message_created',
            'payload': _messageJson(
              id: 'system-tool-2',
              sessionId: 'session-1',
              role: 'system',
              content: '[command:completed] ls',
              createdAt: '2026-05-09T10:00:03.000',
            ),
          },
        ]),
      ),
    );
    await tester.pump();
    await tester.pump();

    final firstMessageBubble = find.ancestor(
      of: find.text('First message'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-bubble-'),
      ),
    ).first;
    final secondMessageBubble = find.ancestor(
      of: find.text('Second message'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-bubble-'),
      ),
    ).first;

    expect(
      tester.getTopLeft(secondMessageBubble).dy,
      greaterThan(tester.getTopLeft(firstMessageBubble).dy),
    );

    await events.close();
  });

  testWidgets('hovering queued message shows edit action',
      (tester) async {
    final sendBodies = <Map<String, dynamic>>[];
    final firstSendCompleter = Completer<http.Response>();
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
          sendBodies.add(body);
          if (sendBodies.length == 1) {
            return firstSendCompleter.future;
          }
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:0${sendBodies.length}.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-${sendBodies.length}',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:1${sendBodies.length}.000',
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

    final input = find.byKey(const Key('session-message-input'));
    await tester.enterText(input, 'First message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    await tester.enterText(input, 'Queued draft');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    final queuedHoverRegion = find.ancestor(
      of: find.text('Queued draft'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('user-message-hover-'),
      ),
    );
    await mouse.moveTo(
      tester.getCenter(queuedHoverRegion),
    );
    await tester.pump();

    final withdrawAction = find.byKey(
      const Key('user-message-withdraw-action'),
    );
    final editAction = find.byKey(const Key('user-message-edit-action'));
    expect(withdrawAction.first, findsOneWidget);
    expect(editAction.first, findsOneWidget);

    await tester.tap(editAction.first);
    await tester.pump();

    expect(
      tester.widget<TextField>(input).controller?.text,
      'Queued draft',
    );
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.linux}));

  testWidgets('voice mode toggle switches composer to hold-to-talk',
      (tester) async {
    final speechService = _FakeSpeechInputService(initializeResult: true);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          speechInputService: speechService,
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('session-message-input')), findsOneWidget);
    expect(
      find.byKey(const Key('session-hold-to-talk-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('session-voice-mode-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('session-message-input')), findsNothing);
    expect(
      find.byKey(const Key('session-hold-to-talk-button')),
      findsOneWidget,
    );
    expect(speechService.startListeningCalls, 0);
    expect(
      tester
          .getSize(find.byKey(const Key('session-hold-to-talk-button')))
          .height,
      tester.getSize(find.byKey(const Key('session-voice-mode-toggle'))).height,
    );

    final holdButton = find.byKey(const Key('session-hold-to-talk-button'));
    final start = tester.getCenter(holdButton);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('Slide up for text or cancel'), findsOneWidget);
    expect(speechService.startListeningCalls, 1);

    await gesture.moveTo(Offset(start.dx - 120, start.dy - 120));
    await tester.pump();

    expect(
        find.byKey(const Key('session-voice-release-insert')), findsOneWidget);
    expect(
        find.byKey(const Key('session-voice-release-cancel')), findsOneWidget);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('pressing enter keeps the current draft on mobile',
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
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final field = tester.widget<TextField>(input);
    expect(sentBodies, isEmpty);
    expect(field.controller!.text, 'Hello');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('assistant reply refreshes generated session title',
      (tester) async {
    var refreshedSession = false;
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
                  content: 'Done',
                  createdAt: '2026-05-09T10:00:01.000',
                ),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1') {
          refreshedSession = true;
          return http.Response(
            jsonEncode({
              'data': {
                'session': _sessionJson(title: 'Generated title'),
                'git_status': null,
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
          session: _session(title: 'New session'),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Generated title'), findsOneWidget);

    final input = find.byType(TextField);
    await tester.tap(input);
    await tester.enterText(input, 'Name this session');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(refreshedSession, isTrue);
    expect(find.text('Generated title'), findsOneWidget);
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.linux,
      }));

  testWidgets('auto speak sends speech playback system prompt', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(autoSpeakReplies: true),
    );
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
            request.url.path == '/sessions/session-1/cancel') {
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
            }),
            200,
            headers: {'content-type': 'application/json'},
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
                  id: 'server-user-auto-speak-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-auto-speak-1',
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
    await tester.enterText(input, 'Read this back');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['input_mode'], 'text');
    expect(
      sentBodies.single['system_prompt'],
      allOf(
        isA<String>(),
        contains('played aloud with text-to-speech'),
        contains('unless the user explicitly asks'),
      ),
    );
  });

  testWidgets('brief reply session sends compression system prompt',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        compressAssistantReplies: true,
        compressAssistantReplyMaxChars: 80,
      ),
    );
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
            request.url.path == '/sessions/session-1/cancel') {
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
            }),
            200,
            headers: {'content-type': 'application/json'},
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
                  id: 'server-user-brief-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-brief-1',
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
          session: _session(briefReplyMode: true),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byType(TextField);
    await tester.enterText(input, 'Summarize this');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['input_mode'], 'text');
    expect(
      sentBodies.single['system_prompt'],
      allOf(
        isA<String>(),
        contains('Keep the assistant reply brief'),
        contains('ideally within 80 characters'),
        contains('unless the user explicitly asks for detail'),
      ),
    );
  });

  testWidgets('disabled compression setting omits compression system prompt',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(compressAssistantReplies: false),
    );
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
            request.url.path == '/sessions/session-1/cancel') {
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
            }),
            200,
            headers: {'content-type': 'application/json'},
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
                  id: 'server-user-compression-disabled-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-compression-disabled-1',
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
          session: _session(briefReplyMode: true),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    final input = find.byType(TextField);
    await tester.enterText(input, 'Do not compress this');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['input_mode'], 'text');
    expect(sentBodies.single.containsKey('system_prompt'), isFalse);
  });

  testWidgets('disabled speech playback prompt omits system prompt',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        autoSpeakReplies: true,
        speechPlaybackPromptEnabled: false,
      ),
    );
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
                  id: 'server-user-no-playback-prompt-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:00.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-no-playback-prompt-1',
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
    await tester.enterText(input, 'Read this back');
    await tester.pump();
    await tester.tap(find.byKey(const Key('session-send-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['input_mode'], 'text');
    expect(sentBodies.single.containsKey('system_prompt'), isFalse);
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
    final toolActivity = find.byIcon(Icons.build_outlined);
    expect(assistantReply, findsOneWidget);
    expect(toolActivity, findsOneWidget);
    expect(
      tester.getTopLeft(toolActivity.first).dy,
      greaterThan(tester.getBottomLeft(assistantReply).dy),
    );
  });

  testWidgets('session initially shows only the most recent turns',
      (tester) async {
    final client = _clientForMessages(_conversationMessages(12));

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
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Question 1'), findsNothing);
    expect(find.text('Answer 1'), findsNothing);
    expect(find.text('Answer 12'), findsOneWidget);
  });

  testWidgets('scrolling to the top expands earlier turns', (tester) async {
    final client = _clientForMessages(_conversationMessages(12));

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
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Question 1'), findsNothing);

    final messageList = find.byType(ListView).first;
    for (var attempt = 0;
        attempt < 6 && find.text('Question 1').evaluate().isEmpty;
        attempt += 1) {
      await tester.drag(messageList, const Offset(0, 1200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Question 1'), findsOneWidget);
    expect(find.text('Answer 1'), findsOneWidget);
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

  testWidgets('user messages render markdown content', (tester) async {
    final client = _clientForMessages([
      _messageJson(
        id: 'user-1',
        sessionId: 'session-1',
        role: 'user',
        content: 'Please check **this** [image](assets/result.png).',
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

    expect(find.text('Please check this image.'), findsOneWidget);
    expect(
      find.text('Please check **this** [image](assets/result.png).'),
      findsNothing,
    );
  });

  testWidgets('user image path shows preview card and loads via bridge',
      (tester) async {
    final requests = <http.Request>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'user-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: 'Please check assets/result.png',
                  createdAt: '2026-05-09T10:00:00.000',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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
        find.byKey(const ValueKey('user-image-card-user-1-assets/result.png')),
        findsOneWidget);

    await tester.tap(find.byKey(
      const ValueKey('user-image-card-user-1-assets/result.png'),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Image preview'), findsNothing);
    expect(find.byKey(const ValueKey('image-preview-dialog')), findsNothing);
    expect(
      find.byKey(const ValueKey('image-preview-fullscreen')),
      findsOneWidget,
    );

    final fileRequest = requests.singleWhere(
      (request) => request.url.path == '/files',
    );
    expect(fileRequest.url.queryParameters, {
      'path': 'assets/result.png',
      'session_id': 'session-1',
    });
  });

  testWidgets('assistant image path shows preview card and loads via bridge',
      (tester) async {
    final requests = <http.Request>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved image at assets/result.png',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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
        find.byKey(const ValueKey(
            'assistant-image-card-assistant-1-assets/result.png')),
        findsOneWidget);

    await tester.tap(find.byKey(
      const ValueKey('assistant-image-card-assistant-1-assets/result.png'),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Image preview'), findsNothing);
    expect(find.byKey(const ValueKey('image-preview-dialog')), findsNothing);
    expect(
      find.byKey(const ValueKey('image-preview-fullscreen')),
      findsOneWidget,
    );

    final fileRequest = requests.singleWhere(
      (request) => request.url.path == '/files',
    );
    expect(fileRequest.url.queryParameters, {
      'path': 'assets/result.png',
      'session_id': 'session-1',
    });
  });

  testWidgets('assistant mp4 path shows video preview card', (tester) async {
    final requests = <http.Request>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved video at assets/demo.mp4',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            const <int>[0, 0, 0, 0],
            200,
            headers: {'content-type': 'video/mp4'},
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
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('assistant-image-card-assistant-1-assets/demo.mp4'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'video-thumbnail-icon-assistant-1-assets/demo.mp4',
        ),
      ),
      findsOneWidget,
    );

    final fileRequest = requests.singleWhere(
      (request) => request.url.path == '/files',
    );
    expect(fileRequest.url.queryParameters, {
      'path': 'assets/demo.mp4',
      'session_id': 'session-1',
    });
  });

  testWidgets('same image path in separate assistant messages reloads file',
      (tester) async {
    final requests = <http.Request>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'First image at assets/result.png',
                  createdAt: '2026-05-09T10:00:01.000',
                ),
                _messageJson(
                  id: 'assistant-2',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Updated image at assets/result.png',
                  createdAt: '2026-05-09T10:00:02.000',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey('assistant-image-card-assistant-1-assets/result.png'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('assistant-image-card-assistant-2-assets/result.png'),
      ),
      findsOneWidget,
    );
    expect(
      requests.where((request) => request.url.path == '/files'),
      hasLength(2),
    );
  });

  testWidgets(
      'same remote image url in separate assistant messages is distinct',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'First image at https://example.com/result.png',
                  createdAt: '2026-05-09T10:00:01.000',
                ),
                _messageJson(
                  id: 'assistant-2',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Updated image at https://example.com/result.png',
                  createdAt: '2026-05-09T10:00:02.000',
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
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey(
          'assistant-image-card-assistant-1-https://example.com/result.png',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'assistant-image-card-assistant-2-https://example.com/result.png',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'remote-image-thumbnail-assistant-1-https://example.com/result.png',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'remote-image-thumbnail-assistant-2-https://example.com/result.png',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('absolute image path preview does not send session scope',
      (tester) async {
    final requests = <http.Request>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved image at /tmp/result.png',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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

    await tester.tap(find.byKey(
      const ValueKey('assistant-image-card-assistant-1-/tmp/result.png'),
    ));
    await tester.pump();
    await tester.pump();

    final fileRequest = requests.singleWhere(
      (request) => request.url.path == '/files',
    );
    expect(fileRequest.url.queryParameters, {
      'path': '/tmp/result.png',
    });
  });

  testWidgets('base64 image markdown shows preview card without bridge file',
      (tester) async {
    final requests = <http.Request>[];
    const dataUri = 'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQImWP4z8AA'
        'AAMBAQAY3Y2xAAAAAElFTkSuQmCC';
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Preview inline image ![preview]($dataUri)',
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

    final imageCard = find.byWidgetPredicate(
      (widget) =>
          widget is InkWell &&
          widget.key is ValueKey &&
          (widget.key as ValueKey<String>)
              .value
              .startsWith('assistant-image-card-assistant-1-data-image-'),
    );
    expect(imageCard, findsOneWidget);

    await tester.tap(imageCard);
    await tester.pump();
    await tester.pump();

    expect(find.text('Image preview'), findsNothing);
    expect(find.byKey(const ValueKey('image-preview-dialog')), findsNothing);
    expect(
      find.byKey(const ValueKey('image-preview-fullscreen')),
      findsOneWidget,
    );
    expect(
      requests.where((request) => request.url.path == '/files'),
      isEmpty,
    );
  });

  testWidgets('markdown image renders only the preview card', (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Preview:\n\n![result](assets/result.png)',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(
      find.byKey(
          const ValueKey('assistant-image-card-assistant-1-assets/result.png')),
      findsOneWidget,
    );
  });

  testWidgets('image preview opens directly fullscreen', (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved image at assets/result.png',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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

    await tester.tap(find.byKey(
      const ValueKey('assistant-image-card-assistant-1-assets/result.png'),
    ));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('image-preview-fullscreen')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('image-preview-dialog')), findsNothing);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Checker'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(
      'image-preview-bg-_ImagePreviewBackdropMode.light',
    )));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('image-preview-fullscreen')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      find.byKey(const ValueKey('image-preview-fullscreen')),
      findsNothing,
    );
  });

  testWidgets('image preview can navigate images in the same message',
      (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved images at assets/one.png and assets/two.png',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response.bytes(
            _tinyPngBytes,
            200,
            headers: {'content-type': 'image/png'},
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
    await tester.pump();

    await tester.tap(find.byKey(
      const ValueKey('assistant-image-card-assistant-1-assets/one.png'),
    ));
    await tester.pump();
    await tester.pump();

    final previousButton = find.byKey(const ValueKey('image-preview-previous'));
    final nextButton = find.byKey(const ValueKey('image-preview-next'));
    expect(previousButton, findsOneWidget);
    expect(nextButton, findsOneWidget);
    expect(tester.widget<IconButton>(previousButton).onPressed, isNull);
    expect(tester.widget<IconButton>(nextButton).onPressed, isNotNull);

    await tester.tap(nextButton);
    await tester.pump();

    expect(tester.widget<IconButton>(previousButton).onPressed, isNotNull);
    expect(tester.widget<IconButton>(nextButton).onPressed, isNull);
  });

  testWidgets('invalid local image path hides preview card', (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved image at assets/missing.png',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response('missing', 404);
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
    await tester.pump();

    expect(
      find.byKey(const ValueKey(
          'assistant-image-card-assistant-1-assets/missing.png')),
      findsNothing,
    );
    expect(find.text('Image attachment'), findsNothing);
  });

  testWidgets('svg image path opens preview', (tester) async {
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Saved image at assets/diagram.svg',
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
        if (request.method == 'GET' && request.url.path == '/files') {
          return http.Response(
            _tinySvg,
            200,
            headers: {'content-type': 'image/svg+xml'},
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
        find.byKey(const ValueKey(
            'assistant-image-card-assistant-1-assets/diagram.svg')),
        findsOneWidget);

    await tester.tap(find.byKey(
      const ValueKey('assistant-image-card-assistant-1-assets/diagram.svg'),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Image preview'), findsNothing);
    expect(find.byKey(const ValueKey('image-preview-dialog')), findsNothing);
    expect(
      find.byKey(const ValueKey('image-preview-fullscreen')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('image-preview-surface')), findsOneWidget);
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

  testWidgets('markdown message body uses one selection area per message',
      (tester) async {
    final client = _clientForMessages([
      _messageJson(
        id: 'assistant-multiline',
        sessionId: 'session-1',
        role: 'assistant',
        content: 'First paragraph\n\nSecond paragraph',
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

    final markdown = find.byType(MarkdownBody);
    expect(markdown, findsOneWidget);
    expect(
      find.ancestor(of: markdown, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    expect(tester.widget<MarkdownBody>(markdown).selectable, isFalse);
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

  testWidgets('user image message bubble shrinks around image preview',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 1600);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const dataUri = 'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
    final client = _clientForMessages([
      _messageJson(
        id: 'user-image',
        sessionId: 'session-1',
        role: 'user',
        content: '你现在能看到这个图片吗\n\n![image]($dataUri)',
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
        find.byKey(const ValueKey('user-message-bubble-user-image'));
    expect(bubbleFinder, findsOneWidget);
    expect(tester.getSize(bubbleFinder).width, lessThan(360));
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

    final callModeButton = tester.widget<IconButton>(
      find.byKey(const Key('session-call-mode-button')),
    );

    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Play'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Stop playback'), findsNothing);
    expect(callModeButton.onPressed, isNull);
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
        find.byKey(const Key('session-voice-input-button'));
    await tester.tap(voiceButtonFinder);
    await tester.pump();

    expect(find.text(message), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(message), findsNothing);
  });

  testWidgets('call mode entry is shown in the app bar instead of composer',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: false,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
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
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    final callModeButton = tester.widget<IconButton>(
      find.byKey(const Key('session-call-mode-button')),
    );

    expect(find.byKey(const Key('session-call-mode-button')), findsOneWidget);
    expect(
        find.widgetWithText(OutlinedButton, 'Start call mode'), findsNothing);
    expect(callModeButton.onPressed, isNotNull);
  });

  testWidgets('bridge local ASR also enables the call mode entry',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: false,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final ttsService = _FakeTtsService(systemAvailable: false);
    final client = _clientForMessages([
      _messageJson(
        id: 'assistant-1',
        sessionId: 'session-1',
        role: 'assistant',
        content: 'Reply ready',
        createdAt: '2026-05-09T10:00:01.000',
      ),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          audioRecordingService: audioService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    final callModeButton = tester.widget<IconButton>(
      find.byKey(const Key('session-call-mode-button')),
    );

    expect(find.byKey(const Key('session-call-mode-button')), findsOneWidget);
    expect(callModeButton.onPressed, isNotNull);
  });

  testWidgets('bridge local call mode sends final realtime transcript',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: false,
      ),
    );
    final sentBodies = <Map<String, dynamic>>[];
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply ready',
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
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentBodies.add(body);
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-bridge-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:02.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-bridge-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:03.000',
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
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(bridgeRealtimeService.startCalls, 1);
    expect(
      bridgeRealtimeService.lastConfig?.endpointTrailingSilenceMs,
      (defaultCallModeSpeechPauseMillis / 0.7).ceil(),
    );
    expect(
      bridgeRealtimeService.lastConfig?.vadMinSilenceMs,
      defaultCallModeSpeechPauseMillis,
    );
    bridgeRealtimeService.emitFinal('。');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, isEmpty);

    bridgeRealtimeService.emitPartial('Bridge partial transcript');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));

    expect(sentBodies, isEmpty);
    bridgeRealtimeService.emitFinal('Bridge final transcript');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['content'], 'Bridge final transcript');
    expect(sentBodies.single['input_mode'], 'voice');
    expect(
      sentBodies.single['system_prompt'],
      allOf(
        isA<String>(),
        contains('played aloud with text-to-speech'),
        contains('unless the user explicitly asks'),
      ),
    );
    expect(bridgeRealtimeService.startCalls, 1);
    expect(
      find.text('Thinking through your request').evaluate().length,
      greaterThanOrEqualTo(1),
    );
    expect(find.text('Preparing microphone'), findsNothing);
    expect(find.text('Preparing to listen'), findsNothing);
    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .isStarting,
      isFalse,
    );
  });

  testWidgets('bridge local call mode does not fill composer text',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: false,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-bridge-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:02.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-bridge-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:03.000',
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
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitPartial('Bridge partial transcript');
    await tester.pump();
    bridgeRealtimeService.emitFinal('Bridge final transcript');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('call-mode-close-button')));
    await tester.pump();

    final field = find.byType(TextField);
    if (field.evaluate().isNotEmpty) {
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    }
  });

  testWidgets('bridge realtime startup failure cancels active recorder',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService(
      startError: StateError('websocket rejected'),
    );

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(bridgeRealtimeService.startCalls, 1);
    expect(bridgeRealtimeService.cancelCalls, greaterThanOrEqualTo(1));
    expect(audioService.cancelCalls, greaterThanOrEqualTo(1));
    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);
  });

  testWidgets(
      'bridge local call mode stops realtime ASR before submitting without interruptions',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: false,
      ),
    );
    final events = <String>[];
    final sentBodies = <Map<String, dynamic>>[];
    final audioService = _FakeAudioRecordingService(
      hasPermissionResult: true,
      events: events,
    );
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService(
      events: events,
    );
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply ready',
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
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          events.add('submit-message');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentBodies.add(body);
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-bridge-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:02.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-bridge-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:03.000',
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
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitFinal('Bridge final transcript');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['content'], 'Bridge final transcript');
    expect(bridgeRealtimeService.cancelCalls, greaterThanOrEqualTo(1));
    expect(audioService.cancelCalls, greaterThanOrEqualTo(1));
    expect(
      events,
      containsAllInOrder([
        'bridge-cancel',
        'audio-cancel',
        'submit-message',
      ]),
    );
  });

  testWidgets('closing active call mode immediately leaves voice input state',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: false,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(find.byKey(const Key('call-mode-screen')), findsOneWidget);
    expect(bridgeRealtimeService.startCalls, 1);

    await tester.ensureVisible(find.byKey(const Key('call-mode-close-button')));
    await tester.tap(find.byKey(const Key('call-mode-close-button')));
    await tester.pump();

    expect(find.byKey(const Key('call-mode-screen')), findsNothing);
    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);
    expect(bridgeRealtimeService.cancelCalls, 1);
  });

  testWidgets('bridge local call mode can interrupt an in-flight reply',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: true,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final ttsService = _FakeTtsService(systemAvailable: false);
    final cancelledSessionIds = <String>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply ready',
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
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/cancel') {
          cancelledSessionIds.add('session-1');
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
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
          session: _session(status: SessionStatus.running),
          client: client,
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitSpeechStarted();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cancelledSessionIds, isEmpty);

    bridgeRealtimeService.emitPartial('interrupt now');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cancelledSessionIds, ['session-1']);
    expect(ttsService.stopCalls, 0);
  });

  testWidgets('entering call mode switches to immersive voice chat screen',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final ttsService = _FakeTtsService(systemAvailable: false);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(find.text('Voice chat'), findsOneWidget);
    expect(find.text('Reply ready'), findsNothing);
    expect(find.byKey(const Key('call-mode-screen')), findsOneWidget);
    expect(find.byKey(const Key('call-mode-orb-gif')), findsOneWidget);
    expect(find.byKey(const Key('call-mode-status-chip')), findsNothing);
    expect(find.byKey(const Key('call-mode-body-card')), findsOneWidget);
    expect(find.byKey(const Key('call-mode-realtime-hint')), findsOneWidget);
    expect(find.text('Listening now'), findsOneWidget);
    expect(
      find.byKey(const Key('call-mode-subtitle-toggle-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('call-mode-primary-button')), findsOneWidget);
    expect(find.byKey(const Key('session-voice-input-button')), findsNothing);
    expect(find.byKey(const Key('session-send-button')), findsNothing);

    tester
        .widget<InkWell>(
            find.byKey(const Key('call-mode-subtitle-toggle-button')))
        .onTap!();
    await tester.pump();

    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .subtitlesVisible,
      isFalse,
    );
    expect(find.byIcon(Icons.subtitles_off_rounded), findsOneWidget);

    tester
        .widget<InkWell>(
            find.byKey(const Key('call-mode-subtitle-toggle-button')))
        .onTap!();
    await tester.pump();

    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .subtitlesVisible,
      isTrue,
    );
    expect(find.byIcon(Icons.subtitles_rounded), findsOneWidget);
  });

  testWidgets('call mode realtime hint updates during bridge speech capture',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(find.text('Listening now'), findsOneWidget);

    bridgeRealtimeService.emitPartial('hello there');
    await tester.pump();

    expect(find.text('Speech detected'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Waiting for you to finish'), findsOneWidget);
  });

  testWidgets('call mode shows spoken assistant reply instead of ASR subtitles',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: true,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
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
              content: '**Reply** ready',
              createdAt: '2026-05-09T10:00:01.000',
            ),
          ]),
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('call-mode-primary-button')));
    await tester.pump();

    expect(ttsService.spokenTexts, ['**Reply** ready']);
    expect(find.byKey(const Key('call-mode-body-markdown')), findsOneWidget);

    bridgeRealtimeService.emitPartial('bad subtitle from speaker');
    await tester.pump();

    expect(find.byKey(const Key('call-mode-body-markdown')), findsOneWidget);
    expect(find.text('bad subtitle from speaker'), findsNothing);
    expect(find.byKey(const Key('call-mode-body-text')), findsNothing);
  });

  testWidgets(
      'call mode shows pending speaker transcript but does not interrupt until matched',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: true,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final ttsService = _FakeTtsService(systemAvailable: false);
    final cancelledSessionIds = <String>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply ready',
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
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/cancel') {
          cancelledSessionIds.add('session-1');
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
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
          session: _session(status: SessionStatus.running),
          client: client,
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitPartial(
      'other speaker',
      speakerFilterActive: true,
    );
    await tester.pump();

    expect(cancelledSessionIds, isEmpty);
    final pendingText =
        tester.widget<Text>(find.byKey(const Key('call-mode-body-text')));
    expect(pendingText.data, 'other speaker');
    expect(pendingText.style?.fontWeight, FontWeight.w600);
    expect(pendingText.style?.color?.a, lessThan(1));

    bridgeRealtimeService.emitFinal(
      'other speaker',
      speakerFilterActive: true,
      speakerVerified: true,
      speakerMatched: false,
    );
    await tester.pump();

    expect(cancelledSessionIds, isEmpty);
    final rejectedText =
        tester.widget<Text>(find.byKey(const Key('call-mode-body-text')));
    expect(rejectedText.data, 'other speaker (not selected speaker)');
    expect(rejectedText.style?.fontWeight, FontWeight.w600);
    expect(rejectedText.style?.color?.a, lessThan(1));

    bridgeRealtimeService.emitFinal(
      'target speaker',
      speakerFilterActive: true,
      speakerVerified: true,
      speakerMatched: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cancelledSessionIds, ['session-1']);
    ttsService.completeSpeech();
    await tester.pump();
  });

  testWidgets('call mode requires speaker filtering to interrupt spoken reply',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: true,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final ttsService = _FakeTtsService(systemAvailable: false);
    final cancelledSessionIds = <String>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({
              'data': [
                _messageJson(
                  id: 'assistant-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply ready',
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
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/cancel') {
          cancelledSessionIds.add('session-1');
          return http.Response(
            jsonEncode({
              'data': {'ok': true}
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
          session: _session(status: SessionStatus.running),
          client: client,
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(bridgeRealtimeService.startCalls, 1);

    ttsService.startSpeech();
    await tester.pump();

    bridgeRealtimeService.emitPartial('Reply ready');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cancelledSessionIds, isEmpty);

    bridgeRealtimeService.emitPartial('interrupt now');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cancelledSessionIds, isEmpty);

    bridgeRealtimeService.emitPartial(
      'interrupt now',
      speakerFilterActive: true,
      speakerVerified: true,
      speakerMatched: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cancelledSessionIds, ['session-1']);
  });

  testWidgets('call mode pauses bridge ASR while speaking command accepted',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: true,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final ttsService = _FakeTtsService(systemAvailable: false);
    final sentBodies = <Map<String, dynamic>>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
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
                  createdAt: '2026-05-09T10:00:02.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:03.000',
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
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitFinal('帮我总结这个项目');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, isEmpty);
    expect(ttsService.spokenTexts, isNotEmpty);
    expect(audioService.cancelCalls, 1);
    expect(bridgeRealtimeService.cancelCalls, 1);

    bridgeRealtimeService.emitFinal(ttsService.spokenTexts.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, isEmpty);

    ttsService.completeSpeech();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['content'], '帮我总结这个项目');
    expect(bridgeRealtimeService.startCalls, 2);
  });

  testWidgets(
      'call mode resumes bridge ASR after command ack before send returns',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
        callModeAllowInterruptions: true,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final ttsService = _FakeTtsService(systemAvailable: false);
    final sendCompleter = Completer<http.Response>();
    final sentBodies = <Map<String, dynamic>>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentBodies.add(body);
          return sendCompleter.future;
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: client,
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitFinal('帮我总结这个项目');
    await tester.pump();

    expect(bridgeRealtimeService.startCalls, 1);
    expect(bridgeRealtimeService.cancelCalls, 1);
    expect(sentBodies, isEmpty);

    ttsService.completeSpeech();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sentBodies, hasLength(1));
    expect(bridgeRealtimeService.startCalls, 2);

    final body = sentBodies.single;
    sendCompleter.complete(
      http.Response(
        jsonEncode({
          'data': {
            'user_message': _messageJson(
              id: 'server-user-1',
              sessionId: 'session-1',
              role: 'user',
              content: body['content'] as String,
              createdAt: '2026-05-09T10:00:02.000',
            ),
            'reply': _messageJson(
              id: 'server-reply-1',
              sessionId: 'session-1',
              role: 'assistant',
              content: '',
              createdAt: '2026-05-09T10:00:03.000',
            ),
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pump();
  });

  testWidgets('call mode submits command that starts with and', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        ttsProvider: TtsProvider.bridgeLocal,
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();
    final sentBodies = <Map<String, dynamic>>[];
    final client = BridgeClient(
      httpClient: _FakeHttpClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-1/events') {
          return http.Response('', 200,
              headers: {'content-type': 'text/event-stream'});
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentBodies.add(body);
          return http.Response(
            jsonEncode({
              'data': {
                'user_message': _messageJson(
                  id: 'server-user-wake-and-1',
                  sessionId: 'session-1',
                  role: 'user',
                  content: body['content'] as String,
                  createdAt: '2026-05-09T10:00:02.000',
                ),
                'reply': _messageJson(
                  id: 'server-reply-wake-and-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: '',
                  createdAt: '2026-05-09T10:00:03.000',
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
          audioRecordingService: audioService,
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(
            systemAvailable: false,
            completeOnSpeak: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    bridgeRealtimeService.emitSpeechStarted();
    bridgeRealtimeService.emitPartial('and');
    bridgeRealtimeService.emitPartial('and 这个项目有几个页面');
    bridgeRealtimeService.emitFinal('and 这个项目有几个页面');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['content'], 'and 这个项目有几个页面');
  });

  testWidgets('call mode ignores stale wake word setting', (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
        callModeWakeWordEnabled: true,
        callModeWakeWords: '你好小欧',
      ),
    );
    final audioService = _FakeAudioRecordingService(hasPermissionResult: true);
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(systemAvailable: false),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(find.text('Listening now'), findsOneWidget);
    expect(find.text('Waiting for wake word'), findsNothing);
    expect(bridgeRealtimeService.lastConfig?.enableWakeWord, isFalse);
    expect(bridgeRealtimeService.lastConfig?.wakeWordDetector, isNull);
    expect(bridgeRealtimeService.lastConfig?.wakeWords, isEmpty);
    expect(audioService.startStreamCalls, 1);
  });

  testWidgets('call mode shows preparing state until realtime ASR starts',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    final startStreamCompleter = Completer<void>();
    final audioService = _FakeAudioRecordingService(
      hasPermissionResult: true,
      startStreamCompleter: startStreamCompleter,
    );
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(systemAvailable: false),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(find.text('Preparing to listen'), findsOneWidget);
    expect(
      find.text('Preparing microphone').evaluate().length,
      greaterThanOrEqualTo(1),
    );
    expect(
      find.text(
          'Speak naturally. I will listen, send, and read the reply back.'),
      findsNothing,
    );
    expect(find.text('Listening now'), findsNothing);
    expect(find.byKey(const Key('call-mode-orb-static')), findsOneWidget);
    expect(find.byKey(const Key('call-mode-orb-gif')), findsNothing);
    expect(
      find.byKey(const Key('call-mode-realtime-starting-spinner')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .isStarting,
      isTrue,
    );
    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .isListening,
      isFalse,
    );

    startStreamCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Listening now'), findsOneWidget);
    expect(find.byKey(const Key('call-mode-orb-static')), findsNothing);
    expect(find.byKey(const Key('call-mode-orb-gif')), findsOneWidget);
    expect(
      find.byKey(const Key('call-mode-realtime-starting-spinner')),
      findsNothing,
    );
    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .isStarting,
      isFalse,
    );
    expect(
      tester
          .widget<SessionCallModeView>(find.byType(SessionCallModeView))
          .isListening,
      isTrue,
    );
  });

  testWidgets('closing call mode while preparing does not show startup error',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.bridgeLocal,
      ),
    );
    final startStreamCompleter = Completer<void>();
    final audioService = _FakeAudioRecordingService(
      hasPermissionResult: true,
      startStreamCompleter: startStreamCompleter,
    );
    final bridgeRealtimeService = _FakeBridgeRealtimeAsrService();

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
          bridgeRealtimeAsrService: bridgeRealtimeService,
          ttsService: _FakeTtsService(systemAvailable: false),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-call-mode-button')));
    await tester.pump();

    expect(find.text('Preparing to listen'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('call-mode-close-button')));
    await tester.tap(find.byKey(const Key('call-mode-close-button')));
    await tester.pump();

    expect(find.byKey(const Key('call-mode-screen')), findsNothing);
    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);

    startStreamCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('call-mode-screen')), findsNothing);
    expect(find.textContaining('Failed to start voice input'), findsNothing);
    expect(find.textContaining('Bridge realtime'), findsNothing);
  });

  testWidgets('cloud speech can be enabled explicitly from settings',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        asrProvider: AsrProvider.whisper,
        ttsProvider: TtsProvider.bridgeLocal,
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

    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Play'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Stop playback'), findsNothing);
    expect(audioService.hasPermissionCalls, 1);
    expect(speechService.initializeCalls, 0);
  });

  testWidgets('voice transcription inserts at cursor without replacing draft',
      (tester) async {
    final speechService = _FakeSpeechInputService(initializeResult: true);

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
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();

    final input = find.byType(TextField);
    await tester.enterText(input, 'before after');
    final field = tester.widget<TextField>(input);
    field.controller!.selection = const TextSelection.collapsed(offset: 6);

    await tester.tap(find.byKey(const Key('session-voice-input-button')));
    await tester.pump();
    expect(speechService.startListeningCalls, 1);
    speechService.emitResult('spoken words', isFinal: true);
    await tester.pump();

    expect(field.controller!.text, 'before spoken words after');
    expect(field.controller!.selection.baseOffset, 19);
    expect(find.byKey(const Key('session-voice-input-button')), findsOneWidget);
    expect(find.byKey(const Key('session-send-button')), findsOneWidget);
  });

  testWidgets('hold voice sends transcript when released in place',
      (tester) async {
    final sentBodies = <Map<String, dynamic>>[];
    final speechService = _FakeSpeechInputService(initializeResult: true);
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
          speechInputService: speechService,
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();

    final holdButton = find.byKey(const Key('session-voice-input-button'));
    final gesture = await tester.startGesture(tester.getCenter(holdButton));
    await tester.pump(const Duration(milliseconds: 600));
    expect(speechService.startListeningCalls, 1);
    speechService.emitResult('spoken words', isFinal: true);
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(sentBodies, hasLength(1));
    expect(sentBodies.single['content'], 'spoken words');
    expect(sentBodies.single['input_mode'], 'voice');
    expect(speechService.stopListeningCalls, 1);
  });

  testWidgets('hold voice waits for microphone warmup then records',
      (tester) async {
    final initializeCompleter = Completer<bool>();
    final speechService = _FakeSpeechInputService(
      initializeResult: true,
      initializeCompleter: initializeCompleter,
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          speechInputService: speechService,
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();

    expect(speechService.initializeCalls, 1);
    expect(speechService.startListeningCalls, 0);

    final holdButton = find.byKey(const Key('session-voice-input-button'));
    final gesture = await tester.startGesture(tester.getCenter(holdButton));
    await tester.pump(const Duration(milliseconds: 600));

    expect(speechService.initializeCalls, 1);
    expect(speechService.startListeningCalls, 0);

    initializeCompleter.complete(true);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(speechService.initializeCalls, 1);
    expect(speechService.startListeningCalls, 1);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('warmed hold voice does not show microphone loading',
      (tester) async {
    final speechService = _FakeSpeechInputService(initializeResult: true);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(),
          client: _clientForMessages(const <Map<String, dynamic>>[]),
          speechInputService: speechService,
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(speechService.initializeCalls, 1);

    final holdButton = find.byKey(const Key('session-voice-input-button'));
    final gesture = await tester.startGesture(tester.getCenter(holdButton));
    await tester.pump(const Duration(milliseconds: 600));

    expect(speechService.startListeningCalls, 1);
    expect(find.text('Preparing microphone'), findsNothing);
    expect(speechService.startListeningCalls, 1);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('hold voice slide up left inserts transcript without sending',
      (tester) async {
    final sentBodies = <Map<String, dynamic>>[];
    final speechService = _FakeSpeechInputService(initializeResult: true);
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
          return http.Response(
            jsonEncode({'data': {}}),
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
          speechInputService: speechService,
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();

    final holdButton = find.byKey(const Key('session-voice-input-button'));
    final start = tester.getCenter(holdButton);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(speechService.startListeningCalls, 1);
    speechService.emitResult('draft words', isFinal: true);
    await tester.pump();
    await gesture.moveTo(Offset(start.dx - 120, start.dy - 120));
    await tester.pump();

    expect(
        find.byKey(const Key('session-voice-release-insert')), findsOneWidget);

    await gesture.up();
    await tester.pump();
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'draft words');
    expect(sentBodies, isEmpty);
    expect(speechService.stopListeningCalls, 1);
  });

  testWidgets('voice input action is reachable from keyboard tab order',
      (tester) async {
    final speechService = _FakeSpeechInputService(initializeResult: true);

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
          ttsService: _FakeTtsService(systemAvailable: true),
        ),
      ),
    );
    await tester.pump();

    var focusedVoiceInput = false;
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null &&
          find
              .descendant(
                of: find.byKey(const Key('session-voice-input-button')),
                matching: find.byWidget(focusedContext.widget),
              )
              .evaluate()
              .isNotEmpty) {
        focusedVoiceInput = true;
        break;
      }
    }

    expect(focusedVoiceInput, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(speechService.startListeningCalls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final nextFocusedContext = FocusManager.instance.primaryFocus?.context;
    final stillFocusedVoiceInput = nextFocusedContext != null &&
        find
            .descendant(
              of: find.byKey(const Key('session-voice-input-button')),
              matching: find.byWidget(nextFocusedContext.widget),
            )
            .evaluate()
            .isNotEmpty;

    expect(stillFocusedVoiceInput, isFalse);
  });

  testWidgets('assistant replies do not show manual playback buttons',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        ttsProvider: TtsProvider.bridgeLocal,
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

    expect(find.widgetWithText(OutlinedButton, 'Play'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Stop playback'), findsNothing);
  });

  testWidgets('auto speaking assistant reply shows stop playback only',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        autoSpeakReplies: true,
        ttsProvider: TtsProvider.bridgeLocal,
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
                  id: 'assistant-speaking-1',
                  sessionId: 'session-1',
                  role: 'assistant',
                  content: 'Reply being spoken',
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
          speechInputService: _FakeSpeechInputService(initializeResult: true),
          enableSpeechServices: true,
        ),
      ),
    );
    await tester.pump();

    eventGate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ttsService.spokenTexts, ['Reply being spoken']);
    expect(find.widgetWithText(OutlinedButton, 'Play'), findsNothing);
    expect(
        find.widgetWithText(OutlinedButton, 'Stop playback'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop playback'));
    await tester.pump();

    expect(ttsService.stopCalls, 1);
  });

  testWidgets('auto speak still triggers while app is backgrounded',
      (tester) async {
    appSettingsController.debugReplaceSettings(
      AppSettings.defaults().copyWith(
        autoSpeakReplies: true,
        asrProvider: AsrProvider.whisper,
        ttsProvider: TtsProvider.bridgeLocal,
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

  testWidgets(
      'approval request triggers notification while app is backgrounded',
      (tester) async {
    final eventGate = Completer<void>();
    final approval = _approvalRequest(
      requestId: 'approval-lockscreen-1',
      command: 'git push origin main',
      reason: 'Needs network access',
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
          await eventGate.future;
          return http.Response(
            _eventStreamBody([
              {
                'type': 'approval_requested',
                'payload': {
                  'request': {
                    'request_id': approval.requestId,
                    'kind': approval.kind,
                    'command': approval.command,
                    'reason': approval.reason,
                    'allow_accept_for_session': approval.allowAcceptForSession,
                    'allow_cancel': approval.allowCancel,
                    'resolvable': approval.resolvable,
                  },
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

    final notifications = _fakeNotifications();

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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    eventGate.complete();
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications.shownNotifications, hasLength(1));
    final notification = notifications.shownNotifications.single;
    expect(notification.title, 'Waiting for approval');
    expect(notification.body, 'Needs network access');
  },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
      }));

  testWidgets('awaiting approval shows pending approval card', (tester) async {
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

    expect(find.text('Needs escalation'), findsOneWidget);
    expect(find.text('Waiting to process approval...'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
  });

  testWidgets('pending approval card does not overflow on short windows',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(668, 298);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final approval = _approvalRequest(
      requestId: 'approval-1',
      command: 'git reset --soft HEAD~1',
      reason: '你想用哪个方案？如果选 reset --soft，我可以先帮你看看'
          '哪些文件该归到哪个提交里。',
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

    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await tester.pump();

    expect(approvalSubmitCalls, 1);
    expect(find.text('Waiting for approval processing...'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
    expect(find.text('rm -rf /tmp/safe-test'), findsOneWidget);
  });

  testWidgets('stopped reply status does not show duplicate snackbar',
      (tester) async {
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

    await tester.tap(find.byKey(const Key('session-stop-reply-button')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Stopped this reply'), findsNothing);
  });

  testWidgets('error banner can be dismissed manually', (tester) async {
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
      find.byKey(const ValueKey('session-error-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byIcon(Icons.copy), findsNothing);
    expect(find.byTooltip('Copy'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('session-error-banner')),
      findsNothing,
    );
  });

  testWidgets('session reasoning effort selector patches session default',
      (tester) async {
    final patchBodies = <Map<String, dynamic>>[];
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
        if (request.method == 'PATCH' &&
            request.url.path == '/sessions/session-1') {
          patchBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 204);
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

    await tester.tap(find.byKey(const Key('session-reasoning-effort-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('High').last);
    await tester.pump();

    expect(patchBodies, hasLength(1));
    expect(patchBodies.single['reasoning_effort'], 'high');
  });

  testWidgets('session reasoning effort selector only exposes common efforts',
      (tester) async {
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

    await tester.tap(find.byKey(const Key('session-reasoning-effort-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Default'), findsWidgets);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Xhigh'), findsNothing);
    expect(find.text('Max'), findsNothing);
  });

  testWidgets('session reasoning effort selector can clear back to default',
      (tester) async {
    final patchBodies = <Map<String, dynamic>>[];
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
        if (request.method == 'PATCH' &&
            request.url.path == '/sessions/session-1') {
          patchBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(reasoningEffort: ReasoningEffort.high),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-reasoning-effort-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Default').last);
    await tester.pump();

    expect(patchBodies, hasLength(1));
    expect(patchBodies.single.containsKey('reasoning_effort'), isTrue);
    expect(patchBodies.single['reasoning_effort'], isNull);
  });

  testWidgets('clearing reasoning effort updates cached session summary',
      (tester) async {
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
        if (request.method == 'PATCH' &&
            request.url.path == '/sessions/session-1') {
          return http.Response('', 204);
        }
        return http.Response('not found', 404);
      }),
    );
    client.debugSeedSessions([
      _session(reasoningEffort: ReasoningEffort.high),
    ]);

    await tester.pumpWidget(
      _TestApp(
        home: SessionDetailScreen(
          session: _session(reasoningEffort: ReasoningEffort.high),
          client: client,
          enableSpeechServices: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('session-reasoning-effort-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Default').last);
    await tester.pump();

    final cached = client.peekSessions();
    expect(cached, isNotNull);
    expect(cached!.single.reasoningEffort, isNull);
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
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
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

SessionSummary _session({
  SessionStatus status = SessionStatus.idle,
  bool briefReplyMode = false,
  String title = 'Test Session',
  ReasoningEffort? reasoningEffort,
}) {
  return SessionSummary(
    id: 'session-1',
    projectId: 'project-1',
    title: title,
    agentId: 'codex',
    briefReplyMode: briefReplyMode,
    status: status,
    updatedAt: DateTime(2026, 5, 9, 10),
    unreadCount: 0,
    lastMessagePreview: null,
    pendingApproval: null,
    reasoningEffort: reasoningEffort,
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

List<Map<String, dynamic>> _conversationMessages(int turnCount) {
  final messages = <Map<String, dynamic>>[];
  for (var index = 1; index <= turnCount; index += 1) {
    messages
      ..add(
        _messageJson(
          id: 'user-$index',
          sessionId: 'session-1',
          role: 'user',
          content: 'Question $index',
          createdAt:
              '2026-05-09T10:00:${(index * 2).toString().padLeft(2, '0')}.000',
        ),
      )
      ..add(
        _messageJson(
          id: 'assistant-$index',
          sessionId: 'session-1',
          role: 'assistant',
          content: 'Answer $index',
          createdAt:
              '2026-05-09T10:00:${(index * 2 + 1).toString().padLeft(2, '0')}.000',
        ),
      );
  }
  return messages;
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
  String title = 'Test Session',
  String? reasoningEffort,
}) {
  return {
    'id': 'session-1',
    'project_id': 'project-1',
    'title': title,
    'agent': 'codex',
    'brief_reply_mode': false,
    'status': status,
    'updated_at': '2026-05-09T10:00:00.000',
    'unread_count': 0,
    'last_message_preview': null,
    'pending_approval': null,
    'reasoning_effort': reasoningEffort,
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

class _UploadingBridgeClient extends BridgeClient {
  _UploadingBridgeClient({
    required this.uploadHandler,
    required super.httpClient,
  });

  final Future<BridgeUploadResponse> Function(String path) uploadHandler;

  @override
  Future<BridgeUploadResponse> uploadFile(String path) => uploadHandler(path);
}

class _StreamingEventHttpClient extends http.BaseClient {
  _StreamingEventHttpClient({
    required this.events,
    required this.handler,
  });

  final Stream<List<int>> events;
  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path == '/sessions/session-1/events') {
      return http.StreamedResponse(
        events,
        200,
        headers: {'content-type': 'text/event-stream'},
        request: request,
      );
    }

    final nextRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      nextRequest.body = request.body;
      nextRequest.encoding = request.encoding;
    }
    final response = await handler(nextRequest);
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
    this.startStreamCompleter,
    this.events,
  });

  final bool hasPermissionResult;
  final Completer<void>? startStreamCompleter;
  final List<String>? events;
  int hasPermissionCalls = 0;
  int startStreamCalls = 0;
  int cancelCalls = 0;
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  @override
  Future<bool> hasPermission() async {
    hasPermissionCalls += 1;
    return hasPermissionResult;
  }

  @override
  Future<Stream<Uint8List>> startStream() async {
    startStreamCalls += 1;
    await startStreamCompleter?.future;
    events?.add('audio-start-stream');
    return _audioStreamController.stream;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    events?.add('audio-cancel');
  }
}

class _FakeBridgeRealtimeAsrService extends BridgeRealtimeAsrService {
  _FakeBridgeRealtimeAsrService({
    this.startError,
    this.events,
  });

  final Object? startError;
  final List<String>? events;
  void Function(BridgeRealtimeAsrUtterance utterance)? _onUtterance;
  void Function()? _onSpeechStarted;
  void Function(String error)? _onError;
  int startCalls = 0;
  int cancelCalls = 0;
  BridgeRealtimeAsrConfig? lastConfig;

  @override
  Future<void> start({
    required Stream<Uint8List> audioStream,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String keyword)? onWakeWordDetected,
    void Function(String error)? onError,
    BridgeRealtimeAsrConfig? config,
  }) async {
    startCalls += 1;
    events?.add('bridge-start');
    if (startError != null) {
      throw startError!;
    }
    _onUtterance = onUtterance;
    _onSpeechStarted = onSpeechStarted;
    _onError = onError;
    lastConfig = config;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    events?.add('bridge-cancel');
  }

  void emitPartial(
    String text, {
    bool speakerFilterActive = false,
    bool speakerVerified = false,
    bool? speakerMatched,
    bool wakeWordActive = false,
    bool wakeWordVerified = false,
    bool? wakeWordMatched,
  }) {
    _onUtterance?.call(
      BridgeRealtimeAsrUtterance(
        text: text,
        isFinal: false,
        speakerFilterActive: speakerFilterActive,
        speakerVerified: speakerVerified,
        speakerMatched: speakerMatched,
        wakeWordActive: wakeWordActive,
        wakeWordVerified: wakeWordVerified,
        wakeWordMatched: wakeWordMatched,
      ),
    );
  }

  void emitSpeechStarted() {
    _onSpeechStarted?.call();
  }

  void emitFinal(
    String text, {
    bool speakerFilterActive = false,
    bool speakerVerified = false,
    bool? speakerMatched,
    bool wakeWordActive = false,
    bool wakeWordVerified = false,
    bool? wakeWordMatched,
  }) {
    _onUtterance?.call(
      BridgeRealtimeAsrUtterance(
        text: text,
        isFinal: true,
        speakerFilterActive: speakerFilterActive,
        speakerVerified: speakerVerified,
        speakerMatched: speakerMatched,
        wakeWordActive: wakeWordActive,
        wakeWordVerified: wakeWordVerified,
        wakeWordMatched: wakeWordMatched,
      ),
    );
  }

  void emitError(String message) {
    _onError?.call(message);
  }
}

class _FakeAndroidFlutterLocalNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  final List<_ShownNotification> shownNotifications = <_ShownNotification>[];

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
  }) async {
    shownNotifications.add(
      _ShownNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }
}

class _ShownNotification {
  const _ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

class _FakeSpeechInputService extends SpeechInputService {
  _FakeSpeechInputService({
    required this.initializeResult,
    this.initializeCompleter,
  });

  final bool initializeResult;
  final Completer<bool>? initializeCompleter;
  int initializeCalls = 0;
  int startListeningCalls = 0;
  int stopListeningCalls = 0;
  int cancelCalls = 0;
  void Function(String words, bool isFinal)? _onResult;

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String error, bool permanent)? onError,
  }) async {
    initializeCalls += 1;
    final completer = initializeCompleter;
    if (completer != null) {
      return completer.future;
    }
    return initializeResult;
  }

  @override
  Future<List<LocaleName>> availableLocales() async {
    return const <LocaleName>[];
  }

  @override
  Future<void> startListening({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  }) async {
    startListeningCalls += 1;
    _onResult = onResult;
  }

  @override
  Future<void> stopListening() async {
    stopListeningCalls += 1;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  void emitResult(String words, {required bool isFinal}) {
    _onResult?.call(words, isFinal);
  }
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _FakeTtsService extends TtsService {
  _FakeTtsService({
    required this.systemAvailable,
    this.completeOnSpeak = false,
  });

  final bool systemAvailable;
  final bool completeOnSpeak;
  final List<String> spokenTexts = <String>[];
  void Function()? _onStart;
  void Function()? _onComplete;
  int initializeCalls = 0;
  int stopCalls = 0;

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
    _onStart = onStart;
    _onComplete = onComplete;
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
    _onStart?.call();
    if (completeOnSpeak) {
      _onComplete?.call();
    }
  }

  void startSpeech() {
    _onStart?.call();
  }

  void completeSpeech() {
    _onComplete?.call();
  }

  @override
  Future<void> stop({bool notifyCancel = true}) async {
    stopCalls += 1;
  }
}

const List<int> _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

const String _tinySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="#66C8FF"/>'
    '</svg>';

class _AnchoredOverlayTestHost extends StatefulWidget {
  const _AnchoredOverlayTestHost({
    required this.targetKey,
    required this.child,
    this.alignment = Alignment.bottomLeft,
    this.overlayBuilder,
  });

  final GlobalKey targetKey;
  final Widget child;
  final Alignment alignment;
  final Widget Function(GlobalKey targetKey, Widget child)? overlayBuilder;

  @override
  State<_AnchoredOverlayTestHost> createState() =>
      _AnchoredOverlayTestHostState();
}

class _AnchoredOverlayTestHostState extends State<_AnchoredOverlayTestHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: widget.alignment,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KeyedSubtree(
              key: widget.targetKey,
              child: const SizedBox(width: 220, height: 44),
            ),
          ),
        ),
        (widget.overlayBuilder ?? _defaultOverlayBuilder)(
          widget.targetKey,
          widget.child,
        ),
      ],
    );
  }

  Widget _defaultOverlayBuilder(GlobalKey targetKey, Widget child) {
    return AnchoredOverlayPanel(
      targetKey: targetKey,
      child: child,
    );
  }
}
