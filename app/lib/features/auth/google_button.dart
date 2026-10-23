import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

/// "Continue with Google": opens the browser, then waits for the server to report the result.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key});

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    final api = ApiClient(ref.read(sessionProvider).serverUrl);
    try {
      final start = await api.googleStart();
      final launched = await launchUrl(
        Uri.parse(start['url'] as String),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw ApiException(0, 'cannot_open_browser');
      for (var i = 0; i < 100 && mounted; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        final r = await api.googlePoll(start['state'] as String);
        if (r['status'] == 'done') {
          await session.storeLogin(r);
          if (mounted) context.go('/');
          return;
        }
      }
      if (mounted) {
        setState(
          () => _error = 'Google sign-in took too long. Please try again.',
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message == 'google_not_configured'
              ? 'Google sign-in is not set up on this server yet.'
              : 'Google sign-in did not finish. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = "Can't connect right now. Check your internet.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 18),
          ),
          onPressed: _busy ? null : _go,
          icon: const Icon(Icons.g_mobiledata, size: 32),
          label: Text(_busy ? 'Waiting for Google...' : 'Continue with Google'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
