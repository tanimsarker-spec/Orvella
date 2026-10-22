import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      'Watch together',
      'Create a room and share its six-character code with friends.',
      Icons.groups_outlined,
    ),
    (
      'Your files, their screens',
      'Stream a video from your PC or from Google Drive. Friends need no VPN or router setup.',
      Icons.cast_connected_outlined,
    ),
    (
      'Always in sync',
      'Play, pause and seek together, even if someone joins late or reconnects.',
      Icons.sync_outlined,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(prefsProvider).setBool('onboarded', true);
    if (mounted) context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final p in _pages)
                    Padding(
                      padding: const EdgeInsetsDirectional.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(p.$3, size: 72),
                          const SizedBox(height: 24),
                          Text(
                            p.$1,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(p.$2, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(16),
              child: FilledButton(
                onPressed: last
                    ? _finish
                    : () => _controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                child: Text(last ? 'Get started' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
