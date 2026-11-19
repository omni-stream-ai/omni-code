import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_code/src/bridge_client.dart';
import 'package:omni_code/src/models.dart';
import 'package:omni_code/src/widgets/model_selection_panel.dart';

void main() {
  testWidgets(
      'switching providers discards a late catalog from the previous provider',
      (tester) async {
    final pending = Completer<http.Response>();
    final client = BridgeClient(httpClient: MockClient((r) async {
      if (r.url.host == 'first.test') return pending.future;
      return http.Response(
          jsonEncode({
            'data': [
              {'id': 'second-model'}
            ]
          }),
          200);
    }));
    final input = TextEditingController();
    String? selected;
    Widget panel(String host) => MaterialApp(
        home: Scaffold(
            body: ModelSelectionPanel(
                client: client,
                customController: input,
                onSelected: (model) => selected = model,
                customHint: 'Custom model',
                keyPrefix: 'model',
                provider: ModelProviderConfig(
                    id: host, name: host, baseUrl: 'https://$host/v1'))));
    await tester.pumpWidget(panel('first.test'));
    await tester.pump();
    await tester.pumpWidget(panel('second.test'));
    await tester.pumpAndSettle();
    expect(find.text('second-model'), findsOneWidget);
    pending.complete(http.Response(
        jsonEncode({
          'data': [
            {'id': 'first-model'}
          ]
        }),
        200));
    await tester.pumpAndSettle();
    expect(find.text('first-model'), findsNothing);
    await tester.tap(find.byKey(const Key('model-option-second-model')));
    expect(selected, 'second-model');
    await tester.pumpWidget(const SizedBox());
    input.dispose();
    client.dispose();
  });

  testWidgets(
      'a failed catalog keeps configured models, custom input and default available',
      (tester) async {
    final client = BridgeClient(
        httpClient: MockClient((_) async => http.Response('Unavailable', 503)));
    final input = TextEditingController();
    final choices = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ModelSelectionPanel(
                client: client,
                customController: input,
                onSelected: choices.add,
                customHint: 'Custom model',
                defaultLabel: 'Default',
                keyPrefix: 'model',
                loadErrorText: 'Enter a model manually.',
                provider: const ModelProviderConfig(
                    id: 'service',
                    name: 'Service',
                    baseUrl: 'https://service.test/v1',
                    model: 'configured-model')))));
    await tester.pumpAndSettle();
    expect(find.text('Enter a model manually.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('model-option-configured-model')));
    await tester.enterText(
        find.byKey(const Key('model-custom-input')), 'manual-model');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const Key('model-option-default')));
    expect(choices, ['configured-model', 'manual-model', null]);
    await tester.pumpWidget(const SizedBox());
    input.dispose();
    client.dispose();
  });
}
