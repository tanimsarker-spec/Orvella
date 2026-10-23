import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/api_client.dart';
import '../../core/mime.dart';
import '../../core/models.dart';
import '../../core/room_connection.dart';
import '../../core/session.dart';
import 'host_media_service.dart';
import 'playback_sync.dart';
import 'voice_chat.dart';

/// Everything that lives while a room is open: control socket, player, sync, host file service.
class RoomSession {
  RoomSession({
    required this.roomId,
    required this.serverUrl,
    required this.userId,
    required this.tokenProvider,
    required this.api,
  }) {
    connection = RoomConnection(
      serverUrl: serverUrl,
      roomId: roomId,
      tokenProvider: tokenProvider,
    );
    player = Player();
    video = VideoController(player);
    sync = PlaybackSync(player: player, connection: connection, userId: userId)
      ..start();
    voice = VoiceChat(
      connection: connection,
      userId: userId,
      iceServers: api.rtcConfig,
    );
    _stateSub = connection.states.listen(
      (s) => _queue = _queue.then((_) => _handle(s)),
    );
    unawaited(_loadInfo());
    _chatSub = connection.chat.listen((m) {
      chatLog.value = [...chatLog.value, m].takeLast(200);
    });
  }

  final String roomId;
  final String serverUrl;
  final String userId;
  final Future<String> Function() tokenProvider;
  final ApiClient api;

  late final RoomConnection connection;
  late final Player player;
  late final VideoController video;
  late final PlaybackSync sync;
  late final VoiceChat voice;
  final ValueNotifier<List<ChatMessage>> chatLog = ValueNotifier(const []);
  final ValueNotifier<String?> notice = ValueNotifier(null);
  final ValueNotifier<RoomInfo?> info = ValueNotifier(null);
  bool _disposed = false;

  StreamSubscription<RoomState>? _stateSub;
  StreamSubscription<ChatMessage>? _chatSub;
  Future<void> _queue = Future<void>.value();
  MediaSourceInfo? _openSource;
  String? _localPath;
  HostMediaService? _hostMedia;

  bool get isHost => connection.lastState?.hostId == userId;
  int get hostedBytesSent => _hostMedia?.bytesSent ?? 0;

  Future<void> _loadInfo() async {
    try {
      final r = await api.joinRoomInfo(roomId);
      if (!_disposed) info.value = r;
    } catch (_) {}
  }

  Future<void> _handle(RoomState s) async {
    try {
      if (!(s.source?.sameAs(_openSource) ?? _openSource == null)) {
        _openSource = s.source;
        await _openMedia(s.source, s.hostId);
      }
      await sync.apply(s);
    } catch (e) {
      notice.value = 'Playback error: $e';
    }
  }

  Future<void> _openMedia(MediaSourceInfo? src, String hostId) async {
    if (src == null) {
      await player.stop();
      return;
    }
    switch (src.kind) {
      case 'url':
        await player.open(Media(src.url!), play: false);
      case 'local':
        if (hostId == userId && _localPath != null) {
          await player.open(Media(_localPath!), play: false);
        } else {
          await _openRemote('media');
        }
      case 'drive':
        await _openRemote('drive');
    }
  }

  Future<void> _openRemote(String route) async {
    final token = await api.mediaToken(roomId);
    await player.open(
      Media(
        '$serverUrl/rooms/$roomId/$route',
        httpHeaders: {'Authorization': 'Bearer $token'},
      ),
      play: false,
    );
  }

  /// Host: start relaying [path] and announce it as the room's source.
  Future<void> hostLocalFile(String path) async {
    final file = File(path);
    final size = await file.length();
    if (size < 1) throw ApiException(400, 'empty_file');
    final name = path.split(RegExp(r'[\\/]')).last;
    await _hostMedia?.stop();
    _localPath = path;
    _hostMedia = HostMediaService(
      serverUrl: serverUrl,
      roomId: roomId,
      tokenProvider: tokenProvider,
      path: path,
    );
    await _hostMedia!.start();
    connection.setSource({
      'kind': 'local',
      'name': name,
      'size': size,
      'mime': videoMimeForFileName(name),
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    await _stateSub?.cancel();
    await _chatSub?.cancel();
    await voice.dispose();
    await sync.dispose();
    await _hostMedia?.stop();
    await connection.dispose();
    await player.dispose();
    chatLog.dispose();
    notice.dispose();
    info.dispose();
  }
}

extension on List<ChatMessage> {
  List<ChatMessage> takeLast(int n) => length <= n ? this : sublist(length - n);
}

final roomSessionProvider = Provider.autoDispose.family<RoomSession, String>((
  ref,
  roomId,
) {
  final s = ref.read(sessionProvider);
  final session = RoomSession(
    roomId: roomId,
    serverUrl: s.serverUrl,
    userId: s.userId!,
    tokenProvider: ref.read(sessionProvider.notifier).freshToken,
    api: ref.read(apiProvider),
  );
  unawaited(session.connection.connect());
  ref.onDispose(() => unawaited(session.dispose()));
  return session;
});
