import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../settings/app_settings.dart';
import 'relay_settings.dart';

String bridgeConnectionScope() {
  final settings = appSettingsController.settings;
  return '${settings.connectionUrl}\n${settings.relay.enabled ? settings.relay.token : settings.bridgeToken}\n${settings.clientId}';
}

class RelayHttpClient extends http.BaseClient {
  RelayHttpClient(this.client);
  final http.Client client;
  static final _scopes = Expando<String>();
  static void ensureCurrent(http.BaseResponse response) {
    final request = response.request;
    if (request != null &&
        _scopes[request] != null &&
        _scopes[request] != bridgeConnectionScope()) {
      throw const RelayException('connection_changed');
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final scope = bridgeConnectionScope();
    _scopes[request] = scope;
    final relay = appSettingsController.settings.relay;
    var own = false;
    if (relay.enabled) {
      final base = Uri.parse(relay.serviceUrl);
      own = request.url.origin == base.origin &&
          request.url.path.startsWith('${base.path}/');
      if (own) {
        request.followRedirects = false;
      } else if (request.headers['authorization'] == 'Bearer ${relay.token}') {
        throw const RelayException('credential_target_denied');
      }
    }
    final response = await client.send(request);
    if (scope != bridgeConnectionScope()) {
      await response.stream.listen(null).cancel();
      throw const RelayException('connection_changed');
    }
    if (own && [401, 403, 429].contains(response.statusCode)) {
      final bytes = await response.stream.toBytes();
      if (scope != bridgeConnectionScope()) {
        throw const RelayException('connection_changed');
      }
      dynamic value;
      try {
        value = jsonDecode(utf8.decode(bytes));
      } catch (_) {}
      if (value is Map &&
          value.length == 1 &&
          const [
            'login_required',
            'service_access_denied',
            'daily_budget_exhausted',
            'rate_limited'
          ].contains(value['error'])) {
        throw RelayException(value['error'] as String);
      }
      return _guard(response, Stream.value(bytes), scope, request);
    }
    return _guard(response, response.stream, scope, request);
  }

  http.StreamedResponse _guard(http.StreamedResponse response,
      Stream<List<int>> body, String scope, http.BaseRequest request) {
    StreamSubscription<List<int>>? subscription;
    late StreamController<List<int>> controller;
    late void Function() changed;
    var finished = false;
    void cleanup() {
      appSettingsController.removeListener(changed);
    }

    void finish([Object? error]) {
      if (finished) return;
      finished = true;
      cleanup();
      if (error != null) {
        controller.addError(error);
        unawaited(subscription?.cancel());
      }
      unawaited(controller.close());
    }

    changed = () {
      if (scope != bridgeConnectionScope()) {
        finish(const RelayException('connection_changed'));
      }
    };
    controller = StreamController<List<int>>(
        onListen: () {
          if (scope != bridgeConnectionScope()) {
            finish(const RelayException('connection_changed'));
            unawaited(body.listen(null).cancel());
            return;
          }
          appSettingsController.addListener(changed);
          subscription = body.listen((bytes) {
            if (finished) return;
            if (scope == bridgeConnectionScope()) {
              controller.add(bytes);
            } else {
              changed();
            }
          }, onError: (Object error) => finish(error), onDone: finish);
        },
        onPause: () => subscription?.pause(),
        onResume: () => subscription?.resume(),
        onCancel: () {
          if (finished) {
            cleanup();
            return null;
          }
          finished = true;
          cleanup();
          return subscription?.cancel();
        });
    return http.StreamedResponse(controller.stream, response.statusCode,
        contentLength: response.contentLength,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase);
  }

  @override
  void close() => client.close();
}
