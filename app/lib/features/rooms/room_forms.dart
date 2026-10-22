import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/session.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final RoomInfo room = await ref
          .read(apiProvider)
          .createRoom(_name.text.trim());
      await ref.read(recentRoomsProvider.notifier).add(room);
      if (mounted) context.go('/rooms/${room.id}');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the room: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create room')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            TextField(
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Room name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? 'Creating...' : 'Create room'),
            ),
          ],
        ),
      ),
    );
  }
}

class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final RoomInfo room = await ref
          .read(apiProvider)
          .joinRoom(_code.text.trim());
      await ref.read(recentRoomsProvider.notifier).add(room);
      if (mounted) context.go('/rooms/${room.id}');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().contains('room_not_found')
              ? 'No room with that code.'
              : 'Could not join: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join room')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(24),
          children: [
            TextField(
              controller: _code,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Room code',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => _busy ? null : _join(),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: Text(_busy ? 'Joining...' : 'Join'),
            ),
          ],
        ),
      ),
    );
  }
}
