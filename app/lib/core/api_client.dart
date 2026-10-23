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

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _send(
    'POST',
    '/auth/signup',
    body: {'email': email, 'password': password, 'displayName': displayName},
    auth: false,
  );

  Future<Map<String, dynamic>> logIn({
    required String email,
    required String password,
  }) => _send(
    'POST',
    '/auth/login',
    body: {'email': email, 'password': password},
    auth: false,
  );

  Future<void> forgot(String email) async {
    await _send('POST', '/auth/forgot', body: {'email': email}, auth: false);
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) => _send(
    'POST',
    '/auth/reset',
    body: {'email': email, 'code': code, 'newPassword': newPassword},
    auth: false,
  );

  Future<Map<String, dynamic>> googleStart() =>
      _send('POST', '/auth/google/start', auth: false);

  Future<Map<String, dynamic>> googlePoll(String state) =>
      _send('GET', '/auth/google/poll', query: {'state': state}, auth: false);

  Future<List<Map<String, dynamic>>> rtcConfig() async {
    final j = await _send('GET', '/rtc/config');
    return (j['iceServers'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<PublicRoom>> publicRooms() async {
    final j = await _send('GET', '/rooms/public');
    return (j['rooms'] as List<dynamic>)
        .map((e) => PublicRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RoomInfo> joinPublic(String roomId) async =>
      RoomInfo.fromJson(await _send('POST', '/rooms/$roomId/join-public'));

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
