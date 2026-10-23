import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../cinema/room_session.dart';

class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({required this.roomId, super.key});
  final String roomId;

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen>
    with WidgetsBindingObserver {
  bool _enabled = true;
  bool _connected = false;
  bool _loading = true;
  bool _waiting = false;
  String? _error;
  final List<(String id, String name)> _path = [('root', 'My Drive')];
  List<DriveFile> _files = const [];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waiting) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final st = await ref.read(apiProvider).driveStatus();
      if (!mounted) return;
      setState(() {
        _enabled = st.enabled;
        _connected = st.connected;
        _loading = false;
        _error = null;
      });
      if (st.connected) {
        _waiting = false;
        _poll?.cancel();
        await _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not reach the server: $e';
        });
      }
    }
  }

  Future<void> _connect() async {
    try {
      final url = await ref.read(apiProvider).driveAuthUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      setState(() => _waiting = true);
      _poll?.cancel();
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (timer) => _refreshStatus(),
      );
    } catch (e) {
      setState(() => _error = 'Could not start Google sign-in: $e');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ref.read(apiProvider).driveFiles(_path.last.$1);
      if (mounted) setState(() => _files = r.files);
    } catch (e) {
      if (mounted) {
        final expired = e.toString().contains('drive_not_connected');
        setState(() {
          _error = expired
              ? 'Google Drive authorization expired. Connect again.'
              : 'Could not load files: $e';
          if (expired) _connected = false;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(DriveFile f) {
    if (f.isFolder) {
      _path.add((f.id, f.name));
      _load();
      return;
    }
    ref.read(roomSessionProvider(widget.roomId)).connection.setSource({
      'kind': 'drive',
      'name': f.name,
      'fileId': f.id,
    });
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _path.length == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _path.length > 1) {
          _path.removeLast();
          _load();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_connected ? _path.last.$2 : 'Google Drive'),
        ),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _files.isEmpty && !_waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_enabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsetsDirectional.all(24),
          child: Text(
            'Google Drive is not set up on this server yet. See docs/DEPLOYMENT.md.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Orvella needs read-only access to your Drive to stream the video you pick to friends in this room. '
                'Your Google login happens in your browser; Orvella never sees your password.',
                textAlign: TextAlign.center,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8),
                  child: Text(_error!),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _waiting ? null : _connect,
                child: Text(
                  _waiting
                      ? 'Waiting for Google sign-in...'
                      : 'Connect Google Drive',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsetsDirectional.all(8),
            child: Text(_error!),
          ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _files.isEmpty && !_loading
              ? const Center(child: Text('No folders or videos here.'))
              : ListView(
                  children: [
                    for (final f in _files)
                      ListTile(
                        leading: Icon(
                          f.isFolder
                              ? Icons.folder_outlined
                              : Icons.movie_outlined,
                        ),
                        title: Text(f.name),
                        subtitle: f.size == null
                            ? null
                            : Text(
                                '${(f.size! / 1048576).toStringAsFixed(0)} MB',
                              ),
                        onTap: () => _open(f),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
