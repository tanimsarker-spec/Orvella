import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account, privacy and settings')),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(s.displayName ?? 'Not signed in'),
              subtitle: const Text('Guest profile'),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Server'),
              subtitle: Text(s.serverUrl),
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Privacy'),
              subtitle: Text(
                'Orvella stores only your display name and room membership on the server, in memory. '
                'Chat is relayed and not stored. Videos are relayed live and never saved on the server. '
                'Google Drive access (if you connect it) is read-only, used only for the file you pick, '
                'and removed when you disconnect. Voice and screen sharing are not implemented yet; '
                'when added, the app will ask for microphone/screen permission each time.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                await ref.read(sessionProvider.notifier).signOut();
                if (context.mounted) context.go('/sign-in');
              },
            ),
          ],
        ),
      ),
    );
  }
}
