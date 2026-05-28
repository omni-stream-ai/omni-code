import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' as flutter_test;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/home_screen.dart';
import 'package:omni_code/src/screens/session_detail_screen.dart';
import 'package:omni_code/src/screens/settings_screen.dart';
import 'package:omni_code/src/services/audio_recording_service.dart';
import 'package:omni_code/src/services/bridge_realtime_asr_service.dart';
import 'package:omni_code/src/services/notification_service.dart';
import 'package:omni_code/src/services/speech_input_service.dart';
import 'package:omni_code/src/services/tts_service.dart';
import 'package:omni_code/src/settings/app_settings.dart';
import 'package:omni_code/src/settings/app_settings_store.dart';
import 'package:omni_code/src/theme/app_theme.dart';
import 'package:omni_code/src/widgets/session_call_mode_view.dart';
import 'package:speech_to_text/speech_to_text.dart';

const _enabled = bool.fromEnvironment('UPDATE_README_PREVIEWS');
const _recordChannel = MethodChannel('com.llfbandit.record/messages');
const _previewAudioPlayerId = 'preview-player';
const _audioPlayersChannel = MethodChannel('xyz.luan/audioplayers');
const _audioPlayersGlobalChannel =
    MethodChannel('xyz.luan/audioplayers.global');
const _audioPlayersGlobalEventsChannel =
    MethodChannel('xyz.luan/audioplayers.global/events');
const _audioPlayersEventsChannel =
    MethodChannel('xyz.luan/audioplayers/events/$_previewAudioPlayerId');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadPreviewFonts();

    final current = flutter_test.goldenFileComparator;
    if (current is flutter_test.LocalFileComparator) {
      flutter_test.goldenFileComparator = flutter_test.LocalFileComparator(
        Uri.file('${Directory.current.path}/preview_base.dart'),
      );
    }
  });

  setUp(() {
    appSettingsController.debugReplaceStore(_MemoryAppSettingsStore());
    appSettingsController.debugReplaceSettings(AppSettings.defaults());
    FlutterLocalNotificationsPlatform.instance =
        _FakeFlutterLocalNotificationsPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_recordChannel, (call) async {
      return switch (call.method) {
        'create' => 'preview-recorder',
        'hasPermission' => true,
        'cancel' || 'stop' || 'dispose' => null,
        _ => null,
      };
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayersChannel, (call) async {
      return switch (call.method) {
        'create' => _previewAudioPlayerId,
        'dispose' || 'stop' || 'release' => null,
        _ => null,
      };
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_audioPlayersGlobalChannel, (call) async {
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _audioPlayersGlobalEventsChannel,
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _audioPlayersEventsChannel,
      (call) async => null,
    );
  });

  testWidgets(
    'generate README showcase image',
    (tester) async {
      final outputDir = Directory('preview');
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _PreviewApp(
          home: _ShowcaseCanvas(
            items: [
              _ShowcaseItem(
                title: 'Home',
                child: HomeScreen(client: _dashboardClient()),
              ),
              _ShowcaseItem(
                title: 'Session',
                child: SessionDetailScreen(
                  session: _previewSession.copyWith(status: SessionStatus.idle),
                  client: _sessionClient(),
                  enableSpeechServices: false,
                  audioRecordingService: _FakeAudioRecordingService(),
                  speechInputService: _FakeSpeechInputService(),
                  ttsService: _FakeTtsService(),
                  bridgeRealtimeAsrService: _FakeBridgeRealtimeAsrService(),
                ),
              ),
              _ShowcaseItem(
                title: 'Call',
                child: const _CallPreviewScreen(),
              ),
              const _ShowcaseItem(
                title: 'Settings',
                child: SettingsScreen(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));

      await expectLater(
        find.byType(_ShowcaseCanvas),
        matchesGoldenFile('preview/omni-code-showcase.png'),
      );
    },
    skip: !_enabled,
  );
}

Future<void> _loadPreviewFonts() async {
  await _loadFontFamily(AppTheme.bodyFontFamily, const [
    '/usr/share/fonts/OTF/NotoSansCJKsc-Regular.otf',
    '/usr/share/fonts/OTF/NotoSansCJKsc-Bold.otf',
  ]);
  await _loadFontFamily('monospace', const [
    '/usr/share/fonts/OTF/NotoSansMonoCJKsc-Regular.otf',
  ]);

  final iconFile = File(
    '/home/junjie/Flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (iconFile.existsSync()) {
    final bytes = await iconFile.readAsBytes();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var hasFont = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final bytes = await file.readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    hasFont = true;
  }
  if (hasFont) {
    await loader.load();
  }
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: notificationService.navigatorKey,
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: home,
    );
  }
}

class _ShowcaseCanvas extends StatelessWidget {
  const _ShowcaseCanvas({required this.items});

  final List<_ShowcaseItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f7fb),
      body: SizedBox.expand(
        child: Stack(
          children: [
            const Positioned.fill(child: _ShowcaseBackdrop()),
            Padding(
              padding: const EdgeInsets.fromLTRB(68, 56, 68, 54),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Omni Code',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xff111827),
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Local-first agent workspace with sessions, voice calls, approvals, and device settings.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                          color: const Color(0xff475569),
                        ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: items.map((item) {
                      return _PhoneMockup(item: item);
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseItem {
  const _ShowcaseItem({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;
}

class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup({required this.item});

  final _ShowcaseItem item;

  @override
  Widget build(BuildContext context) {
    const phoneWidth = 320.0;
    const phoneHeight = 694.0;
    const screenWidth = 296.0;
    const screenHeight = 670.0;
    const statusBarHeight = 28.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              left: -3,
              top: 116,
              child: _PhoneSideButton(height: 58),
            ),
            const Positioned(
              right: -3,
              top: 184,
              child: _PhoneSideButton(height: 86),
            ),
            Container(
              width: phoneWidth,
              height: phoneHeight,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xff334155),
                    Color(0xff0f172a),
                    Color(0xff020617),
                    Color(0xff475569),
                  ],
                  stops: [0, 0.34, 0.74, 1],
                ),
                borderRadius: BorderRadius.circular(48),
                border: Border.all(
                  color: const Color(0xffffffff).withValues(alpha: 0.16),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x3a0f172a),
                    blurRadius: 42,
                    offset: Offset(0, 28),
                  ),
                  BoxShadow(
                    color: Color(0x1a0f172a),
                    blurRadius: 8,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xff020617),
                  borderRadius: BorderRadius.circular(42),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(37),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const _PhoneStatusBar(),
                          Expanded(
                            child: MediaQuery(
                              data: const MediaQueryData(
                                size: Size(
                                  screenWidth,
                                  screenHeight - statusBarHeight,
                                ),
                                devicePixelRatio: 1,
                                textScaler: TextScaler.noScaling,
                                padding: EdgeInsets.zero,
                                viewPadding: EdgeInsets.zero,
                              ),
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: 390,
                                  height: 844,
                                  child: item.child,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned.fill(
                        top: statusBarHeight,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.18),
                                  Colors.white.withValues(alpha: 0.02),
                                  Colors.black.withValues(alpha: 0.05),
                                ],
                                stops: const [0, 0.32, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          item.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xff111827),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _PhoneStatusBar extends StatelessWidget {
  const _PhoneStatusBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xfff8fafc),
            Color(0xffeef2f7),
          ],
        ),
      ),
      child: Row(
        children: [
          const Text(
            '9:41',
            style: TextStyle(
              color: Color(0xff111827),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.signal_cellular_4_bar_rounded,
            size: 12,
            color: Color(0xff111827),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.wifi_rounded,
            size: 13,
            color: Color(0xff111827),
          ),
          const SizedBox(width: 5),
          Container(
            width: 18,
            height: 9,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xff111827), width: 1.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 13,
                margin: const EdgeInsets.all(1.4),
                decoration: BoxDecoration(
                  color: const Color(0xff111827),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Container(
            width: 2,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xff111827),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneSideButton extends StatelessWidget {
  const _PhoneSideButton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xff64748b),
            Color(0xff111827),
            Color(0xff475569),
          ],
        ),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ShowcaseBackdrop extends StatelessWidget {
  const _ShowcaseBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ShowcaseBackdropPainter());
  }
}

class _ShowcaseBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xffffffff),
          Color(0xffedf4ff),
          Color(0xfff8fafc),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xffcbd5e1).withValues(alpha: 0.42);
    for (var x = -160.0; x < size.width + 260; x += 72) {
      canvas.drawLine(Offset(x, 0), Offset(x + 360, size.height), linePaint);
    }

    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xff2563eb).withValues(alpha: 0.16);
    for (var index = 0; index < 4; index += 1) {
      final y = 210 + index * 118.0;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 24) {
        path.lineTo(x, y + math.sin((x / 96) + index) * 14);
      }
      canvas.drawPath(path, accentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CallPreviewScreen extends StatefulWidget {
  const _CallPreviewScreen();

  @override
  State<_CallPreviewScreen> createState() => _CallPreviewScreenState();
}

class _CallPreviewScreenState extends State<_CallPreviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
      value: 0.45,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionCallModeView(
      voiceChatTitle: 'Voice chat',
      statusText: 'Listening',
      bodyText:
          'I am ready to help you inspect the app, run commands, and continue the conversation hands-free.',
      realtimeHintLabel: 'Live transcript',
      realtimeHintDetail: 'Start speaking whenever you are ready.',
      bannerText: 'Live transcript appears here while you speak.',
      subtitlesVisible: true,
      subtitleToggleTooltip: 'Hide subtitles',
      closeTooltip: 'Close',
      orbAnimation: _controller,
      isListening: true,
      isLive: true,
      onBackPressed: () {},
      onSubtitleTogglePressed: () {},
      onPrimaryPressed: () {},
      onClosePressed: () {},
    );
  }
}

BridgeClient _dashboardClient() {
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'GET' && request.url.path == '/projects') {
        return _jsonResponse(_projects.map(_projectJson).toList());
      }
      if (request.method == 'GET' && request.url.path == '/sessions') {
        return _jsonResponse(_sessions.map(_sessionJson).toList());
      }
      return http.Response('not found', 404);
    }),
  );
}

BridgeClient _sessionClient() {
  return BridgeClient(
    httpClient: _FakeHttpClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/sessions/${_previewSession.id}/messages') {
        return _jsonResponse(_messages);
      }
      if (request.method == 'GET' &&
          request.url.path == '/sessions/${_previewSession.id}/events') {
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

http.Response _jsonResponse(Object data) {
  return http.Response(
    jsonEncode({'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

final _projects = <ProjectSummary>[
  ProjectSummary(
    id: 'omni-code-client',
    name: 'omni-code-client',
    rootPath: '/Users/junjie/code/omni-code-client',
    updatedAt: DateTime(2026, 5, 28, 13, 48),
    sessionCount: 12,
    lastSessionPreview:
        'Finished the immersive voice chat screen and regression tests.',
  ),
  ProjectSummary(
    id: 'release-tools',
    name: 'release-tools',
    rootPath: '/Users/junjie/code/release-tools',
    updatedAt: DateTime(2026, 5, 28, 11, 20),
    sessionCount: 5,
    lastSessionPreview:
        'Waiting on the Android APK and macOS zip release check.',
  ),
  ProjectSummary(
    id: 'bridge',
    name: 'omni-code-bridge',
    rootPath: '/Users/junjie/code/omni-code-bridge',
    updatedAt: DateTime(2026, 5, 27, 19, 5),
    sessionCount: 8,
    lastSessionPreview: 'SSE has recovered; checking the auth fallback next.',
  ),
];

final _previewSession = SessionSummary(
  id: 'session-voice-mode',
  projectId: _projects.first.id,
  title: 'Continuous voice conversations',
  agent: AgentKind.codex,
  briefReplyMode: false,
  status: SessionStatus.running,
  updatedAt: DateTime(2026, 5, 28, 13, 48),
  unreadCount: 2,
  lastMessagePreview: 'The call mode view is now stable.',
);

final _sessions = <SessionSummary>[
  _previewSession,
  SessionSummary(
    id: 'session-release-check',
    projectId: _projects[1].id,
    title: 'Release checklist',
    agent: AgentKind.codex,
    briefReplyMode: false,
    status: SessionStatus.waiting,
    updatedAt: DateTime(2026, 5, 28, 11, 20),
    unreadCount: 0,
    lastMessagePreview: 'Confirm version, changelog, and release notes.',
  ),
  SessionSummary(
    id: 'session-approval',
    projectId: _projects[2].id,
    title: 'Bridge approval flow',
    agent: AgentKind.claudecode,
    briefReplyMode: true,
    status: SessionStatus.awaitingApproval,
    updatedAt: DateTime(2026, 5, 27, 19, 5),
    unreadCount: 1,
    lastMessagePreview: 'Waiting for approval to run the local build command.',
  ),
];

final _messages = <Map<String, Object?>>[
  _messageJson(
    id: 'message-1',
    role: 'user',
    content: 'Can you make the session preview feel more polished?',
    createdAt: '2026-05-28T13:44:00.000Z',
  ),
  _messageJson(
    id: 'message-2',
    role: 'assistant',
    content:
        'I updated the layout, tightened the message spacing, and added focused tests for call mode.',
    createdAt: '2026-05-28T13:44:04.000Z',
  ),
  _messageJson(
    id: 'message-3',
    role: 'system',
    content:
        '[command:completed] flutter test test/session_detail_screen_test.dart',
    createdAt: '2026-05-28T13:44:18.000Z',
  ),
  _messageJson(
    id: 'message-4',
    role: 'assistant',
    content:
        'The UI now keeps the conversation readable while voice mode is active.',
    createdAt: '2026-05-28T13:44:22.000Z',
  ),
];

Map<String, Object?> _projectJson(ProjectSummary project) {
  return {
    'id': project.id,
    'name': project.name,
    'root_path': project.rootPath,
    'updated_at': project.updatedAt.toIso8601String(),
    'session_count': project.sessionCount,
    'last_session_preview': project.lastSessionPreview,
  };
}

Map<String, Object?> _sessionJson(SessionSummary session) {
  return {
    'id': session.id,
    'project_id': session.projectId,
    'title': session.title,
    'agent': session.agent.id,
    'brief_reply_mode': session.briefReplyMode,
    'status': switch (session.status) {
      SessionStatus.idle => 'idle',
      SessionStatus.running => 'running',
      SessionStatus.awaitingApproval => 'awaiting_approval',
      SessionStatus.waiting => 'waiting',
      SessionStatus.failed => 'failed',
    },
    'updated_at': session.updatedAt.toIso8601String(),
    'unread_count': session.unreadCount,
    'last_message_preview': session.lastMessagePreview,
    'pending_approval': null,
  };
}

Map<String, Object?> _messageJson({
  required String id,
  required String role,
  required String content,
  required String createdAt,
}) {
  return {
    'id': id,
    'session_id': _previewSession.id,
    'role': role,
    'content': content,
    'created_at': createdAt,
  };
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

class _FakeAudioRecordingService implements AudioRecordingService {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream() async {
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<String> start() async => '/tmp/preview.wav';

  @override
  Future<String?> stop() async => null;
}

class _FakeSpeechInputService implements SpeechInputService {
  @override
  bool get isListening => false;

  @override
  Future<List<LocaleName>> availableLocales() async => const <LocaleName>[];

  @override
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String error, bool permanent)? onError,
  }) async {
    return true;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> startListening({
    required void Function(String words, bool isFinal) onResult,
    String? localeId,
  }) async {}

  @override
  Future<void> stopListening() async {}
}

class _FakeTtsService implements TtsService {
  @override
  bool get isSystemTtsAvailable => true;

  @override
  Future<void> initialize({
    void Function()? onStart,
    void Function()? onComplete,
    void Function()? onCancel,
    void Function(String message)? onError,
  }) async {}

  @override
  Future<void> stop({bool notifyCancel = true}) async {}

  @override
  Future<void> speak(String text) async {}
}

class _FakeBridgeRealtimeAsrService implements BridgeRealtimeAsrService {
  @override
  bool get isRunning => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> finish() async {}

  @override
  Future<void> start({
    required Stream<Uint8List> audioStream,
    required void Function(BridgeRealtimeAsrUtterance utterance) onUtterance,
    void Function()? onSpeechStarted,
    void Function(String keyword)? onWakeWordDetected,
    void Function(String error)? onError,
    BridgeRealtimeAsrConfig? config,
  }) async {}
}

class _MemoryAppSettingsStore implements AppSettingsStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

class _FakeFlutterLocalNotificationsPlatform
    extends FlutterLocalNotificationsPlatform {
  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }
}
