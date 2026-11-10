class RelaySettings {
  const RelaySettings(
      {this.origin = 'https://relay.omnistreamai.com',
      this.token = '',
      this.clientKey = '',
      this.clientId = '',
      this.expiresAt = 0,
      this.serviceId = '',
      this.enabled = false});
  final String origin;
  final String token;
  final String clientKey;
  final String clientId;
  final int expiresAt;
  final String serviceId;
  final bool enabled;
  bool get signedIn =>
      token.isNotEmpty &&
      expiresAt > DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String get serviceUrl {
    final relay = normalizeRelayOrigin(origin);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(serviceId)) {
      throw const FormatException('Invalid Relay service');
    }
    return '$relay/s/$serviceId';
  }

  Map<String, String> get headers {
    if (!signedIn || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const RelayException('login_required');
    }
    return {'Authorization': 'Bearer $token'};
  }

  RelaySettings copyWith(
          {String? origin,
          String? token,
          String? clientKey,
          String? clientId,
          int? expiresAt,
          String? serviceId,
          bool? enabled}) =>
      RelaySettings(
          origin: origin ?? this.origin,
          token: token ?? this.token,
          clientKey: clientKey ?? this.clientKey,
          clientId: clientId ?? this.clientId,
          expiresAt: expiresAt ?? this.expiresAt,
          serviceId: serviceId ?? this.serviceId,
          enabled: enabled ?? this.enabled);
  Map<String, dynamic> toJson() => {
        'origin': origin,
        'token': token,
        'client_key': clientKey,
        'client_id': clientId,
        'expires_at': expiresAt,
        'service_id': serviceId,
        'enabled': enabled
      };
  factory RelaySettings.fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return const RelaySettings();
    final settings = RelaySettings(
        origin: value['origin'] as String? ?? 'https://relay.omnistreamai.com',
        token: value['token'] as String? ?? '',
        clientKey: value['client_key'] as String? ?? '',
        clientId: value['client_id'] as String? ?? '',
        expiresAt: value['expires_at'] as int? ?? 0,
        serviceId: value['service_id'] as String? ?? '',
        enabled: value['enabled'] == true);
    normalizeRelayOrigin(settings.origin);
    if (settings.enabled) {
      settings.serviceUrl;
    }
    return settings;
  }
}

String normalizeRelayOrigin(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) {
    throw const FormatException(
        'Use an HTTPS Relay origin without paths or credentials');
  }
  final local = ['localhost', '127.0.0.1', '::1'].contains(uri.host);
  if ((uri.scheme != 'https' && !(uri.scheme == 'http' && local)) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException(
        'Use an HTTPS Relay origin without paths or credentials');
  }
  return uri.origin;
}

class RelayException implements Exception {
  const RelayException(this.code);
  final String code;
  bool get blocksReconnect => const [
        'login_required',
        'service_access_denied',
        'daily_budget_exhausted',
        'rate_limited'
      ].contains(code);
  @override
  String toString() => 'Relay: $code';
}
