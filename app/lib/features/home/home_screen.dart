import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../widgets/creator_signature.dart';

final publicRoomsProvider = FutureProvider.autoDispose<List<PublicRoom>>(
  (ref) => ref.watch(apiProvider).publicRooms(),
);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _open(Future<RoomInfo> Function() action, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final RoomInfo room = await action();
      await ref.read(recentRoomsProvider.notifier).add(room);
      if (mounted) context.push('/rooms/${room.id}');
    } catch (e) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startParty() => _open(
    () => ref.read(apiProvider).createRoom(''),
    "Can't start a party right now. Check your internet.",
  );

  Future<void> _joinPublic(PublicRoom r) => _open(
    () => ref.read(apiProvider).joinPublic(r.id),
    'That party is not available any more.',
  );

  String _subtitle(PublicRoom r) {
    final watching = '${r.hostName} - ${r.online} here';
    return r.sourceName.isEmpty ? watching : '$watching - ${r.sourceName}';
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentRoomsProvider);
    final name = ref.watch(sessionProvider).displayName;
    final publicRooms = ref.watch(publicRoomsProvider);
    const bigText = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orvella'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.all(16),
                children: [
                  if (name != null)
                    Text(
                      'Hi, $name!',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(96),
                      textStyle: bigText,
                    ),
                    onPressed: _busy ? null : _startParty,
                    icon: const Icon(Icons.celebration_outlined, size: 32),
                    label: Text(_busy ? 'One moment...' : 'Start a party'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(96),
                      textStyle: bigText,
                    ),
                    onPressed: () => context.push('/rooms/join'),
                    icon: const Icon(Icons.login, size: 32),
                    label: const Text('Join a party'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ...publicRooms.maybeWhen(
                    data: (rooms) => rooms.isEmpty
                        ? <Widget>[]
                        : <Widget>[
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Public parties',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Refresh',
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () =>
                                      ref.invalidate(publicRoomsProvider),
                                ),
                              ],
                            ),
                            for (final r in rooms)
                              ListTile(
                                leading: const Icon(Icons.public),
                                title: Text(r.name),
                                subtitle: Text(_subtitle(r)),
                                onTap: _busy ? null : () => _joinPublic(r),
                              ),
                            const SizedBox(height: 16),
                          ],
                    orElse: () => <Widget>[],
                  ),
                  if (recent.isNotEmpty)
                    Text(
                      'Your recent parties',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  for (final r in recent)
                    ListTile(
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text(r.name),
                      subtitle: Text('Code ${r.code}'),
                      onTap: () => context.push('/rooms/${r.id}'),
                    ),
                ],
              ),
            ),
            const CreatorSignature(),
          ],
        ),
      ),
    );
  }
}
