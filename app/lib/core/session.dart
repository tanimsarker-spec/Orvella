import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'config.dart';
import 'models.dart';

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main'),
);

class SessionState {
  const SessionState({
    required this.serverUrl,
    this.token,
    this.userId,
    this.displayName,
  });
  final String serverUrl;
  final String? token;
  final String? userId;
  final String? displayName;
  bool get signedIn => token != null && userId != null;
}

/// Decodes the `exp` claim (seconds) of a JWT without verifying it. Null if unreadable.
int? jwtExpSeconds(String token) {
  try {
    final parts = token.split('.');
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    return (jsonDecode(payload) as Map<String, dynamic>)['exp'] as int?;
  } catch (_) {
    return null;
  }
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final p = ref.read(prefsProvider);
    return SessionState(
      serverUrl: p.getString('serverUrl') ?? defaultServerUrl,
      token: p.getString('token'),
      userId: p.getString('userId'),
      displayName: p.getString('displayName'),
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final j = await ApiClient(state.serverUrl).signUp(
      email: email.trim(),
      password: password,
      displayName: displayName.trim(),
    );
    await storeLogin(j);
  }

  Future<void> logIn({required String email, required String password}) async {
    final j = await ApiClient(state.serverUrl)
        .logIn(email: email.trim(), password: password);
    await storeLogin(j);
  }

  Future<void> storeLogin(Map<String, dynamic> j) async {
    final user = j['user'] as Map<String, dynamic>;
    final token = j['token'] as String;
    final p = ref.read(prefsProvider);
    await p.setString('token', token);
    await p.setString('userId', user['id'] as String);
    await p.setString('displayName', user['displayName'] as String);
    state = SessionState(
      serverUrl: state.serverUrl,
      token: token,
      userId: user['id'] as String,
      displayName: user['displayName'] as String,
    );
  }

  /// Advanced/testing only: point the app at a different server.
  Future<void> setServerUrl(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return;
    await ref.read(prefsProvider).setString('serverUrl', clean);
    state = SessionState(
      serverUrl: clean,
      token: state.token,
      userId: state.userId,
      displayName: state.displayName,
    );
  }

  /// Returns a valid access token, refreshing it when it is about to expire.
  Future<String> freshToken() async {
    final current = state.token;
    if (current == null) throw ApiException(401, 'not_signed_in');
    final exp = jwtExpSeconds(current);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && exp - nowSec > 300) return current;
    try {
      final fresh = await ApiClient(state.serverUrl).refresh(current);
      await ref.read(prefsProvider).setString('token', fresh);
      state = SessionState(
        serverUrl: state.serverUrl,
        token: fresh,
        userId: state.userId,
        displayName: state.displayName,
      );
      return fresh;
    } on ApiException catch (e) {
      if (e.status == 401) await signOut();
      rethrow;
    }
  }

  Future<void> signOut() async {
    final p = ref.read(prefsProvider);
    for (final k in ['token', 'userId', 'displayName']) {
      await p.remove(k);
    }
    state = SessionState(serverUrl: state.serverUrl);
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

final apiProvider = Provider<ApiClient>((ref) {
  final s = ref.watch(sessionProvider);
  return ApiClient(
    s.serverUrl,
    tokenProvider: () => ref.read(sessionProvider.notifier).freshToken(),
  );
});

class RecentRoomsController extends Notifier<List<RoomInfo>> {
  static const _key = 'recentRooms';

  @override
  List<RoomInfo> build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => RoomInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(RoomInfo room) async {
    final next = [
      room,
      ...state.where((r) => r.id != room.id),
    ].take(10).toList();
    state = next;
    await ref
        .read(prefsProvider)
        .setString(_key, jsonEncode(next.map((r) => r.toJson()).toList()));
  }
}

final recentRoomsProvider =
    NotifierProvider<RecentRoomsController, List<RoomInfo>>(
      RecentRoomsController.new,
    );
