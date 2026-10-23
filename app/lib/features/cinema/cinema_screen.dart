import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models.dart';
import '../../core/room_connection.dart';
import 'reaction_overlay.dart';
import 'room_session.dart';

class CinemaScreen extends ConsumerWidget {
  const CinemaScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider(roomId));
    return StreamBuilder<RoomState>(
      stream: session.connection.states,
      initialData: session.connection.lastState,
      builder: (context, snap) {
        final state = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(state?.source?.name ?? 'Your party'),
            actions: [
              _InviteButton(session: session),
              IconButton(
                tooltip: 'Choose what to watch',
                icon: const Icon(Icons.video_library_outlined),
                onPressed: () => context.push('/rooms/$roomId/source'),
              ),
              IconButton(
                tooltip: 'Playback quality',
                icon: const Icon(Icons.speed_outlined),
                onPressed: () => context.push('/rooms/$roomId/quality'),
              ),
            ],
          ),
          body: SafeArea(
            child: state == null
                ? _Connecting(session: session)
                : LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth >= 900;
                      final player = _PlayerColumn(
                        session: session,
                        state: state,
                      );
                      final panel = _SidePanel(session: session, state: state);
                      return wide
                          ? Row(
                              children: [
                                Expanded(child: player),
                                SizedBox(width: 340, child: panel),
                              ],
                            )
                          : Column(
                              children: [
                                player,
                                Expanded(child: panel),
                              ],
                            );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting({required this.session});
  final RoomSession session;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: session.connection.errors,
      builder: (context, err) => Center(
        child: err.hasData
            ? Text(
                err.data == 'room_not_found'
                    ? 'This room no longer exists.'
                    : 'You are not a member of this room.',
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Connecting to room...'),
                ],
              ),
      ),
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({required this.session, required this.state});
  final RoomSession session;
  final RoomState state;

  bool get _canControl => state.controlMode == 'everyone' || session.isHost;

  @override
  Widget build(BuildContext context) {
    final player = session.player;
    final video = AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: state.source == null
            ? const Center(
                child: Text(
                  'Nothing selected yet.\nTap the library icon to choose a video.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : Video(controller: session.video),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final controls = Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          child: Column(
            children: [
              StreamBuilder<Duration>(
                stream: player.stream.position,
                builder: (context, pos) => StreamBuilder<Duration>(
                  stream: player.stream.duration,
                  builder: (context, dur) {
                    final total = dur.data ?? player.state.duration;
                    final cur = pos.data ?? player.state.position;
                    final max = total.inMilliseconds.toDouble();
                    return Row(
                      children: [
                        Text(_fmt(cur)),
                        Expanded(
                          child: Slider(
                            value: max <= 0
                                ? 0
                                : cur.inMilliseconds
                                      .clamp(0, total.inMilliseconds)
                                      .toDouble(),
                            max: max <= 0 ? 1 : max,
                            onChanged: _canControl && max > 0 ? (v) {} : null,
                            onChangeEnd: _canControl && max > 0
                                ? (v) => session.connection.seek(v.round())
                                : null,
                          ),
                        ),
                        Text(_fmt(total)),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: state.playing
                        ? 'Pause for everyone'
                        : 'Play for everyone',
                    iconSize: 36,
                    icon: Icon(
                      state.playing
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                    ),
                    onPressed: _canControl && state.source != null
                        ? () {
                            final pos = player.state.position.inMilliseconds;
                            state.playing
                                ? session.connection.pause(pos)
                                : session.connection.play(pos);
                          }
                        : null,
                  ),
                  if (state.buffering.isNotEmpty)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 12),
                      child: Text('Waiting for someone to buffer...'),
                    ),
                ],
              ),
              StreamBuilder<ConnectionStatus>(
                stream: session.connection.statusStream,
                initialData: session.connection.status,
                builder: (context, s) => s.data == ConnectionStatus.connected
                    ? const SizedBox.shrink()
                    : const Text('Reconnecting...'),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: session.notice,
                builder: (context, n, child) =>
                    n == null ? const SizedBox.shrink() : Text(n),
              ),
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                video,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ReactionOverlay(
                      stream: session.connection.reactions,
                    ),
                  ),
                ),
              ],
            ),
            controls,
            _EmojiBar(session: session),
          ],
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.session, required this.state});
  final RoomSession session;
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Chat'),
              Tab(text: 'People'),
              Tab(text: 'Voice'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ChatTab(session: session),
                _PeopleTab(session: session, state: state),
                _VoiceTab(session: session, state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.session});
  final RoomSession session;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    widget.session.connection.sendChat(t);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<List<ChatMessage>>(
            valueListenable: widget.session.chatLog,
            builder: (context, log, child) => ListView.builder(
              padding: const EdgeInsetsDirectional.all(8),
              itemCount: log.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${log[i].fromName}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: log[i].text),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) => _send(),
                ),
              ),
              IconButton(
                tooltip: 'Send message',
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeopleTab extends StatelessWidget {
  const _PeopleTab({required this.session, required this.state});
  final RoomSession session;
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.tag),
          title: const Text('Share this room'),
          subtitle: const Text('Tap to copy the room code'),
          onTap: () async {
            final info = await session.api.joinRoomInfo(session.roomId);
            await Clipboard.setData(ClipboardData(text: info.code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Room code ${info.code} copied')),
              );
            }
          },
        ),
        if (session.isHost)
          SwitchListTile(
            title: const Text('Only host controls playback'),
            value: state.controlMode == 'host',
            onChanged: (v) =>
                session.connection.setControlMode(v ? 'host' : 'everyone'),
          ),
        if (session.isHost)
          SwitchListTile(
            title: const Text('Show in Public parties'),
            subtitle: const Text('Anyone on Orvella can find and join'),
            value: state.isPublic,
            onChanged: session.connection.setPublic,
          ),
        for (final p in state.participants)
          ListTile(
            leading: _Avatar(name: p.displayName),
            title: Text(
              p.displayName + (p.id == state.hostId ? ' (host)' : ''),
            ),
            subtitle: Text(
              state.buffering.contains(p.id)
                  ? 'buffering'
                  : (p.online ? 'online' : 'offline'),
            ),
          ),
      ],
    );
  }
}

class _VoiceTab extends StatelessWidget {
  const _VoiceTab({required this.session, required this.state});
  final RoomSession session;
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final voice = session.voice;
    return ValueListenableBuilder<bool>(
      valueListenable: voice.joined,
      builder: (context, joined, child) {
        if (!joined) {
          return Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic_none, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'Talk with everyone in the party.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => voice.join(
                      state.participants
                          .where((p) => p.online)
                          .map((p) => p.id),
                    ),
                    icon: const Icon(Icons.mic),
                    label: const Text('Join voice chat'),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: voice.error,
                    builder: (context, e, child) => e == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(top: 12),
                            child: Text(e, textAlign: TextAlign.center),
                          ),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: voice.muted,
                      builder: (context, muted, child) =>
                          FilledButton.tonalIcon(
                            onPressed: voice.toggleMute,
                            icon: Icon(muted ? Icons.mic_off : Icons.mic),
                            label: Text(muted ? 'Unmute' : 'Mute'),
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () =>
                        voice.leave(state.participants.map((p) => p.id)),
                    child: const Text('Leave'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<Set<String>>(
                valueListenable: voice.peers,
                builder: (context, peers, child) => ListView(
                  children: [
                    for (final p in state.participants.where((p) => p.online))
                      ListTile(
                        leading: _Avatar(name: p.displayName),
                        title: Text(p.displayName),
                        trailing: Icon(
                          p.id == session.userId || peers.contains(p.id)
                              ? Icons.graphic_eq
                              : Icons.mic_off_outlined,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmojiBar extends StatelessWidget {
  const _EmojiBar({required this.session});
  final RoomSession session;

  static const _emojis = ['❤️', '😂', '😮', '😢', '👏', '🔥', '👍'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final e in _emojis)
          TextButton(
            onPressed: () => session.connection.react(e),
            child: Text(e, style: const TextStyle(fontSize: 26)),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final hue = name.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) % 360);
    return CircleAvatar(
      backgroundColor: HSLColor.fromAHSL(
        1,
        hue.toDouble(),
        0.5,
        0.42,
      ).toColor(),
      child: Text(
        name.isEmpty
            ? '?'
            : String.fromCharCode(name.runes.first).toUpperCase(),
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  const _InviteButton({required this.session});
  final RoomSession session;

  Future<void> _copy(BuildContext context, RoomInfo info) async {
    await Clipboard.setData(
      ClipboardData(
        text:
            'Join my Orvella party! Open Orvella, tap "Join a party" and type: ${info.code}',
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code ${info.code} copied. Send it to your friends!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RoomInfo?>(
      valueListenable: session.info,
      builder: (context, info, child) {
        if (info == null) return const SizedBox.shrink();
        return TextButton.icon(
          onPressed: () => _copy(context, info),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(info.code),
        );
      },
    );
  }
}
