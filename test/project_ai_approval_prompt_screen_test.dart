import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_code/l10n/generated/app_localizations.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/screens/project_ai_approval_prompt_screen.dart';
import 'package:omni_code/src/theme/app_theme.dart';

void main() {
  testWidgets('project prompt can be edited and saved', (tester) async {
    final client = _ProjectApprovalClient();
    await tester.pumpWidget(
      _TestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showProjectAiApprovalPromptDialog(
                  context,
                  client: client,
                  projectId: 'project-1',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = find.byKey(
      const Key('project-ai-approval-prompt-field'),
    );
    expect(field, findsOneWidget);
    expect(find.text('Follow the project policy.'), findsOneWidget);

    await tester.enterText(field, 'Only allow read-only repository checks.');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(client.saved?.prompt, 'Only allow read-only repository checks.');
  });
}

class _ProjectApprovalClient extends BridgeClient {
  ProjectAiApprovalSettings? saved;

  @override
  Future<ProjectAiApprovalSettings> getProjectAiApprovalSettings(
    String projectId,
  ) async {
    return const ProjectAiApprovalSettings(
      prompt: 'Follow the project policy.',
    );
  }

  @override
  Future<ProjectAiApprovalSettings> updateProjectAiApprovalSettings(
    String projectId,
    ProjectAiApprovalSettings settings,
  ) async {
    saved = settings;
    return settings;
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
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
