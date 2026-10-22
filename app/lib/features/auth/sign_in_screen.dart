import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _server;
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: ref.read(sessionProvider).serverUrl);
  }

  @override
  void dispose() {
    _server.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).signIn(_server.text, _name.text);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().contains('invalid_display_name')
              ? 'Use 1-32 letters, numbers, spaces or . _ -'
              : 'Could not reach the server. Check the address and your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsetsDirectional.all(24),
              shrinkWrap: true,
              children: [
                const Text(
                  'Pick a display name. This creates a guest profile on the Orvella server; '
                  'no email or password is collected.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) => _busy ? null : _submit(),
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Connecting...' : 'Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
