import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/screens/acceptance_environment_screen.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  const enabled = bool.fromEnvironment('ACCEPTANCE_PREVIEWS');
  for (final mobile in [true, false]) {
    for (final dark in [true, false]) {
      testWidgets(
          'build review preview ${mobile ? 'mobile' : 'desktop'} ${dark ? 'dark' : 'light'}',
          (tester) async {
        await tester.runAsync(() async {
          final fontPath = Platform.environment['ACCEPTANCE_CJK_FONT'];
          for (final family in ['Ahem', 'Roboto']) {
            final loader = FontLoader(family);
            for (final path in [
              fontPath ?? 'designs/assets/fonts/Roboto-Regular.ttf'
            ]) {
              loader.addFont(Future.value(
                  ByteData.sublistView(await File(path).readAsBytes())));
            }
            await loader.load();
          }
          final icons = Platform.environment['ACCEPTANCE_ICON_FONT'];
          if (icons != null) {
            await (FontLoader('MaterialIcons')
                  ..addFont(Future.value(
                      ByteData.sublistView(await File(icons).readAsBytes()))))
                .load();
          }
        });
        tester.view.physicalSize =
            mobile ? const Size(390, 844) : const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = BridgeClient(
            httpClient: MockClient((_) async => http.Response(
                jsonEncode({
                  'data': {
                    'config': {},
                    'detection': {
                      'configuration': {
                        'language': 'typescript',
                        'package_manager': 'pnpm',
                        'install_command': 'pnpm install',
                        'build_command': 'pnpm run build',
                        'start_command': 'pnpm run dev',
                      },
                      'evidence': [
                        'package.json',
                        'pnpm-lock.yaml',
                        'tsconfig.json'
                      ]
                    }
                  }
                }),
                200,
                headers: {'content-type': 'application/json'})));
        final baseTheme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
        // Theme-level styles with a null family bypass the test's Roboto alias.
        // Give those styles the same loaded system font used by the text theme.
        final label = WidgetStatePropertyAll(
            baseTheme.textTheme.labelLarge!.copyWith(fontFamily: 'Roboto'));
        final previewTheme = baseTheme.copyWith(
          appBarTheme: baseTheme.appBarTheme.copyWith(
              titleTextStyle: baseTheme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto')),
          filledButtonTheme: FilledButtonThemeData(
              style: baseTheme.filledButtonTheme.style
                  ?.copyWith(textStyle: label)),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: baseTheme.outlinedButtonTheme.style
                  ?.copyWith(textStyle: label)),
          textButtonTheme: TextButtonThemeData(
              style:
                  baseTheme.textButtonTheme.style?.copyWith(textStyle: label)),
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: previewTheme,
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AcceptanceEnvironmentScreen(
                  client: client,
                  projectId: 'fixture',
                  reviewBeforeStart: true),
            )));
        await tester.pumpAndSettle();
        Future<void> capture(String suffix) async {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            {
              final directory = Directory('../.cache/acceptance-flow-review');
              await directory.create(recursive: true);
              await File(
                      '${directory.path}/${mobile ? 'mobile' : 'desktop'}-${dark ? 'dark' : 'light'}-$suffix.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            }
            image.dispose();
          });
        }

        await capture('form');
        await tester.scrollUntilVisible(
            find.byKey(const Key('acceptance-build-agent')), 250,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await capture('actions');
        expect(tester.takeException(), isNull);
      }, skip: !enabled);
    }
  }
}
