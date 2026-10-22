const String _fromBuild = String.fromEnvironment('ORVELLA_SERVER');

/// Default server URL: baked in at build time via --dart-define=ORVELLA_SERVER=...
String get defaultServerUrl =>
    _fromBuild.isEmpty ? 'http://localhost:8080' : _fromBuild;

String wsUrl(String base, String path, [Map<String, String>? query]) {
  final u = Uri.parse(base);
  return u
      .replace(
        scheme: u.scheme == 'https' ? 'wss' : 'ws',
        path: path,
        queryParameters: query,
      )
      .toString();
}
