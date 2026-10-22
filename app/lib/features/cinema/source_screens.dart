import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'room_session.dart';

/// Test videos from the Blender Foundation (Creative Commons), useful for sync testing.
const _testVideos = [
  (
    'Big Buck Bunny (test)',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  ),
  (
    'Sintel (test)',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
  ),
];

class SourceScreen extends ConsumerWidget {
  const SourceScreen({required this.roomId, super.key});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(roomSessionProvider(roomId));
    final isHost = session.isHost;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose what to watch')),
      body: SafeArea(
        child: ListView(
          children: [
            if (!isHost)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Only the host can change the video.'),
              ),
            ListTile(
              enabled: isHost,
              leading: const Icon(Icons.computer_outlined),
              title: const Text('Video file from this device'),
              subtitle: const Text(
                'Streamed to friends through the server while Orvella stays open',
              ),
              onTap: () => context.push('/rooms/$roomId/local'),
            ),
            ListTile(
              enabled: isHost,
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Google Drive'),
              onTap: () => context.push('/rooms/$roomId/drive'),
            ),
            const Divider(),
            const ListTile(
              title: Text('Test videos (public, for checking sync)'),
            ),
            for (final v in _testVideos)
              ListTile(
                enabled: isHost,
                leading: const Icon(Icons.link),
                title: Text(v.$1),
                onTap: () {
                  session.connection.setSource({
                    'kind': 'url',
                    'name': v.$1,
                    'url': v.$2,
                  });
                  context.pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class LocalFileScreen extends ConsumerStatefulWidget {
  const LocalFileScreen({required this.roomId, super.key});
  final String roomId;

  @override
  ConsumerState<LocalFileScreen> createState() => _LocalFileScreenState();
}

class _LocalFileScreenState extends ConsumerState<LocalFileScreen> {
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final session = ref.read(roomSessionProvider(widget.roomId));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await session.hostLocalFile(path);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not use that file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video from this device')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            const Text(
              'Only the single file you pick is shared, and only while this room is open in Orvella. '
              'Friends stream it through the Orvella server; they never get access to your computer or other files. '
              'Keep this app open and your PC awake during the movie.',
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: Text(_busy ? 'Preparing...' : 'Choose video file'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload speed matters: your internet upload must exceed the video bitrate.',
            ),
          ],
        ),
      ),
    );
  }
}
