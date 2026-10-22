import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUrl, {this.tokenProvider, http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final Future<String> Function()? tokenProvider;
  final http.Client _http;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri);
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    if (auth) {
      final t = token ?? await tokenProvider!();
      req.headers['authorization'] = 'Bearer $t';
    }
    final res = await http.Response.fromStream(
      await _http.send(req).timeout(const Duration(seconds: 15)),
    );
    Map<String, dynamic> decoded = {};
    try {
      decoded = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (decoded['error'] as String?) ?? 'HTTP ${res.statusCode}',
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> guest(String displayName) => _send(
    'POST',
    '/auth/guest',
    body: {'displayName': displayName},
    auth: false,
  );

  Future<String> refresh(String oldToken) async =>
      (await _send('POST', '/auth/refresh', token: oldToken))['token']
          as String;

  Future<RoomInfo> createRoom(String name) async =>
      RoomInfo.fromJson(await _send('POST', '/rooms', body: {'name': name}));

  Future<RoomInfo> joinRoom(String code) async => RoomInfo.fromJson(
    await _send('POST', '/rooms/join', body: {'code': code}),
  );

  Future<RoomInfo> joinRoomInfo(String roomId) async =>
      RoomInfo.fromJson(await _send('GET', '/rooms/$roomId'));

  Future<String> mediaToken(String roomId) async =>
      (await _send('POST', '/rooms/$roomId/media-token'))['token'] as String;

  Future<({bool enabled, bool connected})> driveStatus() async {
    final j = await _send('GET', '/drive/status');
    return (enabled: j['enabled'] as bool, connected: j['connected'] as bool);
  }

  Future<String> driveAuthUrl() async =>
      (await _send('POST', '/drive/oauth/start'))['url'] as String;

  Future<({List<DriveFile> files, String? next})> driveFiles(
    String parent, {
    String? pageToken,
  }) async {
    final j = await _send(
      'GET',
      '/drive/files',
      query: {'parent': parent, if (pageToken != null) 'pageToken': pageToken},
    );
    final files = (j['files'] as List<dynamic>)
        .map((f) => DriveFile.fromJson(f as Map<String, dynamic>))
        .toList();
    return (files: files, next: j['nextPageToken'] as String?);
  }

  Future<void> driveDisconnect() async => _send('POST', '/drive/disconnect');
}
