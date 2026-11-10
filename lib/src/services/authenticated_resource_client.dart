import 'package:http/http.dart' as http;

/// A media loader may use a caller-provided client. Keep credentials scoped to
/// the exact resource and never follow redirects with them.
class AuthenticatedResourceClient extends http.BaseClient {
  AuthenticatedResourceClient(this.resource, this.headers,
      {http.Client? client})
      : _client = client ?? http.Client();
  final Uri resource;
  final Map<String, String> headers;
  final http.Client _client;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url != resource) {
      throw StateError('Media request target changed');
    }
    request.followRedirects = false;
    request.headers.addAll(headers);
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}
