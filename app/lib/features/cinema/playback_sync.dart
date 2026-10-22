import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../core/models.dart';
import '../../core/room_connection.dart';

/// Applies authoritative room state to the local player and reports local buffering.
class PlaybackSync {
  PlaybackSync({
    required this.player,
    required this.connection,
    required this.userId,
  });

  final Player player;
  final RoomConnection connection;
  final String userId;

  /// Seek only when we drift further than this from where the room says we should be.
  static const driftToleranceMs = 600;

  RoomState? _last;
  StreamSubscription<bool>? _bufSub;
  Timer? _driftTimer;
  bool _reportedBuffering = false;

  void start() {
    _bufSub = player.stream.buffering.listen((b) {
      if (b != _reportedBuffering) {
        _reportedBuffering = b;
        connection.setBuffering(b);
      }
    });
    _driftTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final s = _last;
      if (s != null) unawaited(apply(s));
    });
  }

  Future<void> apply(RoomState s) async {
    _last = s;
    if (s.source == null) return;
    final target = s.targetPositionMs(connection.serverNowMs);
    final othersBuffering = s.buffering.any((id) => id != userId);
    final shouldPlay = s.playing && !othersBuffering;
    final current = player.state.position.inMilliseconds;
    if ((current - target).abs() > driftToleranceMs) {
      await player.seek(Duration(milliseconds: target));
    }
    if (shouldPlay && !player.state.playing) {
      await player.play();
    } else if (!shouldPlay && player.state.playing) {
      await player.pause();
    }
  }

  Future<void> dispose() async {
    _driftTimer?.cancel();
    await _bufSub?.cancel();
  }
}
