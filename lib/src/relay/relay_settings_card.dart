import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bridge_client.dart';
import '../l10n/app_locale.dart';
import '../settings/app_settings.dart';
import 'relay_api.dart';
import 'relay_settings.dart';

class RelaySettingsCard extends StatefulWidget {
  const RelaySettingsCard(
      {super.key, required this.client, required this.onConnectionChanged});
  final BridgeClient client;
  final VoidCallback onConnectionChanged;
  @override
  State<RelaySettingsCard> createState() => _RelaySettingsCardState();
}

class _RelaySettingsCardState extends State<RelaySettingsCard> {
  final _api = RelayApi();
  late final _origin =
      TextEditingController(text: appSettingsController.settings.relay.origin);
  final _name = TextEditingController(text: 'Omni Code');
  final _hostOrigin =
      TextEditingController(text: 'https://relay.omnistreamai.com');
  final _hostName = TextEditingController(text: 'Omni Code Bridge');
  RelayLogin? _login;
  List<RelayService>? _services;
  Map<String, dynamic>? _host, _devices;
  Timer? _loginTimer, _hostTimer;
  bool _busy = false;
  String? _error;
  Future<void> Function()? _retry;
  RelaySettings get _session => appSettingsController.settings.relay;
  @override
  void dispose() {
    _loginTimer?.cancel();
    _hostTimer?.cancel();
    _origin.dispose();
    _name.dispose();
    _hostOrigin.dispose();
    _hostName.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = action;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            error is RelayException && error.code == 'login_required'
                ? context.l10n.relayLoginRequired
                : context.l10n.relayFailure('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(RelaySettings value) async {
    await appSettingsController
        .save(appSettingsController.settings.copyWith(relay: value));
    if (mounted) {
      setState(() {});
      widget.onConnectionChanged();
    }
  }

  Future<void> _refresh() async {
    final services = await _api.services(_session);
    if (mounted) setState(() => _services = services);
  }

  Future<void> _startLogin() async {
    _loginTimer?.cancel();
    final flow =
        await _api.beginLogin(_origin.text, _name.text, previous: _session);
    if (!mounted) return;
    setState(() => _login = flow);
    _scheduleLogin(flow);
  }

  void _scheduleLogin(RelayLogin flow) {
    _loginTimer = Timer(Duration(seconds: flow.interval), () {
      if (_busy) {
        _scheduleLogin(flow);
        return;
      }
      unawaited(_run(() async {
        final session = await _api.pollLogin(flow);
        if (!mounted || !identical(_login, flow)) return;
        if (session == null) {
          _scheduleLogin(flow);
          return;
        }
        setState(() => _login = null);
        await _save(session);
        await _refresh();
      }));
    });
  }

  Future<void> _hostOperation(String path, {Map<String, dynamic>? body}) async {
    final value =
        await widget.client.relayHostRequest('/relay/$path', body: body);
    if (!mounted) return;
    setState(() => _host = value);
    _hostTimer?.cancel();
    final login = value['login'];
    if (login is Map) {
      _scheduleHost(
          Duration(seconds: (login['interval'] as int? ?? 5).clamp(5, 30)),
          () async {
        await _hostOperation('login/poll', body: {});
        if (_host?['login'] == null && _host?['signed_in'] == true) {
          await _hostOperation('enable', body: {});
        }
      });
    } else if (value['enabled'] == true) {
      _scheduleHost(const Duration(seconds: 5), () => _hostOperation('status'));
    }
  }

  void _scheduleHost(Duration interval, Future<void> Function() action) {
    _hostTimer?.cancel();
    _hostTimer = Timer(interval, () {
      if (!mounted) return;
      if (_busy) {
        _scheduleHost(interval, action);
        return;
      }
      unawaited(_run(action));
    });
  }

  Future<void> _loadHost() async {
    await _hostOperation('status');
    _hostOrigin.text = _host?['relay'] as String? ?? _hostOrigin.text;
    _hostName.text = _host?['name'] as String? ?? _hostName.text;
  }

  Future<void> _loadDevices() async {
    final value = await widget.client.relayHostRequest('/relay/clients');
    if (mounted) setState(() => _devices = value);
  }

  Future<void> _manage(String action, {String? client, String? policy}) async {
    await widget.client.relayHostRequest('/relay/manage', body: {
      'action': action,
      if (client != null) 'client': client,
      if (policy != null) 'policy': policy
    });
    await _loadDevices();
  }

  String _accessLabel(String value) {
    final l10n = context.l10n;
    return switch (value) {
      'allowed' || 'approved' => l10n.relayAccessAllowed,
      'pending' => l10n.relayAccessPending,
      'revoked' => l10n.relayAccessRevoked,
      'banned' => l10n.relayAccessBanned,
      'login_required' => l10n.relayAccessLoginRequired,
      'approval_required' => l10n.relayAccessApprovalRequired,
      _ => l10n.relayCheckConnection
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hostLogin = _host?['login'];
    return ExpansionTile(
        key: const Key('relay-settings'),
        title: Text(l10n.relayTitle),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.relayUse),
              value: _session.enabled,
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                        if (value) {
                          _session.headers;
                          await _refresh();
                        }
                        await _save(_session.copyWith(enabled: value));
                      })),
          TextField(
              key: const Key('relay-origin'),
              controller: _origin,
              enabled: !_busy && _login == null && !_session.enabled,
              decoration: InputDecoration(labelText: l10n.relayUrl)),
          TextField(
              controller: _name,
              maxLength: 100,
              enabled: !_busy && _login == null,
              decoration: InputDecoration(labelText: l10n.relayDeviceName)),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed:
                    _busy || _login != null ? null : () => _run(_startLogin),
                child: Text(l10n.relayLogin)),
            TextButton(
                onPressed: _busy ? null : () => _run(_refresh),
                child: Text(l10n.relayRefresh)),
            if (_session.token.isNotEmpty)
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await _api.logout(_session);
                            await _save(_session.copyWith(
                                enabled: false, token: '', expiresAt: 0));
                            if (mounted) setState(() => _services = null);
                          }),
                  child: Text(l10n.relayLogout)),
          ]),
          if (_login != null) ...[
            Text(l10n.relayVerify),
            SelectableText(_login!.userCode),
            TextButton(
                onPressed: () => launchUrl(Uri.parse(_login!.verificationUri),
                    mode: LaunchMode.externalApplication),
                child: Text(l10n.relayOpenLogin)),
            TextButton(
                onPressed: () {
                  _loginTimer?.cancel();
                  setState(() => _login = null);
                },
                child: Text(l10n.cancel)),
          ],
          if (_services?.isEmpty == true) Text(l10n.relayNoServices),
          for (final service in _services ?? <RelayService>[])
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(service.name),
                subtitle: Text(
                    '${service.online ? l10n.relayOnline : l10n.relayOffline} · ${_accessLabel(service.access)}'),
                trailing: service.access == 'allowed'
                    ? TextButton(
                        onPressed: !service.online || _busy
                            ? null
                            : () => _run(() => _save(_session.copyWith(
                                serviceId: service.id, enabled: true))),
                        child: Text(l10n.relayConnect))
                    : ['approval_required', 'revoked'].contains(service.access)
                        ? TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                      await _api.requestAccess(
                                          _session, service.id);
                                      await _refresh();
                                    }),
                            child: Text(l10n.relayRequestAccess))
                        : null),
          if (!_session.enabled)
            ExpansionTile(
                title: Text(l10n.relayHost),
                onExpansionChanged: (open) {
                  if (open) {
                    unawaited(_run(_loadHost));
                  } else {
                    _hostTimer?.cancel();
                  }
                },
                children: [
                  Text(l10n.relayHostHint),
                  if (_host != null) ...[
                    TextField(
                        controller: _hostOrigin,
                        enabled: !_busy &&
                            _host?['enabled'] != true &&
                            hostLogin == null,
                        decoration: InputDecoration(labelText: l10n.relayUrl)),
                    TextField(
                        controller: _hostName,
                        maxLength: 100,
                        enabled: !_busy &&
                            _host?['enabled'] != true &&
                            hostLogin == null,
                        decoration:
                            InputDecoration(labelText: l10n.relayServiceName)),
                    Text(_host?['enabled'] == true
                        ? ((_host?['connection'] as Map?)?['state']
                                as String? ??
                            l10n.relayConnecting)
                        : l10n.relayDisabled),
                    Wrap(spacing: 8, children: [
                      if (_host?['enabled'] != true && hostLogin == null)
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() => _hostOperation('login/start',
                                        body: {
                                          'relay': _hostOrigin.text,
                                          'name': _hostName.text
                                        })),
                            child: Text(l10n.relayLoginEnable)),
                      if (_host?['enabled'] != true &&
                          _host?['service_id'] != null)
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _hostOperation('enable', body: {})),
                            child: Text(l10n.relayEnable)),
                      if (_host?['enabled'] == true || hostLogin != null)
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _hostOperation('disable', body: {})),
                            child: Text(l10n.relayDisable)),
                      if (_host?['service_id'] != null)
                        TextButton(
                            onPressed: _busy ? null : () => _run(_loadDevices),
                            child: Text(l10n.relayDevices)),
                    ]),
                    if (hostLogin is Map) ...[
                      Text(l10n.relayVerify),
                      SelectableText(hostLogin['user_code'] as String),
                      TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(
                                  hostLogin['verification_uri'] as String),
                              mode: LaunchMode.externalApplication),
                          child: Text(l10n.relayOpenLogin))
                    ],
                    if (_devices != null) ...[
                      DropdownButtonFormField<String>(
                          initialValue: _devices!['policy'] as String,
                          decoration:
                              InputDecoration(labelText: l10n.relayPolicy),
                          items: [
                            DropdownMenuItem(
                                value: 'auto',
                                child: Text(l10n.relayPolicyAuto)),
                            DropdownMenuItem(
                                value: 'approval',
                                child: Text(l10n.relayPolicyApproval))
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    unawaited(_run(() =>
                                        _manage('policy', policy: value)));
                                  }
                                }),
                      for (final device
                          in _devices!['clients'] as List<dynamic>)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(device['name'] as String),
                            subtitle: Text(_accessLabel(device['banned'] == 1 ||
                                    device['service_banned'] == 1
                                ? 'banned'
                                : device['grant_state'] as String? ??
                                    (_devices!['policy'] == 'auto'
                                        ? 'allowed'
                                        : 'approval_required'))),
                            trailing: PopupMenuButton<String>(
                                enabled: !_busy && device['banned'] != 1,
                                onSelected: (action) => _run(() => _manage(
                                    action,
                                    client: device['id'] as String)),
                                itemBuilder: (_) => [
                                      PopupMenuItem(
                                          value: 'approve',
                                          child: Text(l10n.relayApprove)),
                                      PopupMenuItem(
                                          value: 'revoke',
                                          child: Text(l10n.relayRevoke)),
                                      PopupMenuItem(
                                          value: 'kick',
                                          child: Text(l10n.relayKick)),
                                      PopupMenuItem(
                                          value: device['service_banned'] == 1
                                              ? 'unban'
                                              : 'ban',
                                          child: Text(
                                              device['service_banned'] == 1
                                                  ? l10n.relayUnban
                                                  : l10n.relayBan))
                                    ])),
                    ],
                  ],
                ]),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Column(children: [
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                  onPressed:
                      _busy || _retry == null ? null : () => _run(_retry!),
                  child: Text(l10n.retry))
            ]),
        ]);
  }
}
