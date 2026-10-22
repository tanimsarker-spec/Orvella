import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../widgets/creator_signature.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentRoomsProvider);
    final name = ref.watch(sessionProvider).displayName;
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
                      'Hi, $name',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push('/rooms/create'),
                    child: const Text('Create room'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => context.push('/rooms/join'),
                    child: const Text('Join room'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Recent rooms',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (recent.isEmpty) const Text('No recent rooms yet.'),
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
