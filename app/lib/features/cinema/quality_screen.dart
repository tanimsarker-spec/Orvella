import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'room_session.dart';

/// Shows values measured from the live player. Nothing here is estimated or fabricated.
class QualityScreen extends ConsumerWidget {
  const QualityScreen({required this.roomId, super.key});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider(roomId));
    final player = session.player;
    return Scaffold(
      appBar: AppBar(title: const Text('Playback quality')),
      body: SafeArea(
        child: StreamBuilder<Duration>(
          stream: player.stream.position,
          builder: (context, snap) {
            final s = player.state;
            final res = (s.width != null && s.height != null)
                ? '${s.width} x ${s.height}'
                : 'unknown';
            final sent = session.hostedBytesSent;
            return ListView(
              padding: const EdgeInsetsDirectional.all(16),
              children: [
                const Text(
                  'These are live measurements. Orvella plays the original file; it does not re-encode, '
                  'so quality is whatever your file is, as long as bandwidth keeps up.',
                ),
                const SizedBox(height: 16),
                _row('Video resolution', res),
                _row(
                  'Buffered ahead',
                  '${(s.buffer - s.position).inSeconds.clamp(0, 86400)} s',
                ),
                _row('Currently buffering', s.buffering ? 'yes' : 'no'),
                _row('Position', '${s.position.inSeconds} s'),
                _row('Duration', '${s.duration.inSeconds} s'),
                _row('Connection', session.connection.status.name),
                _row(
                  'Clock offset to server',
                  '${session.connection.clockOffsetMs} ms',
                ),
                if (session.isHost)
                  _row(
                    'Uploaded to server (this session)',
                    '${(sent / 1048576).toStringAsFixed(1)} MB',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String k, String v) =>
      ListTile(dense: true, title: Text(k), trailing: Text(v));
}
