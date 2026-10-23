import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

/// Step 1: enter email, we send a 6-digit code. Step 2: enter the code and a new password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendly(Object e) {
    if (e is ApiException) {
      switch (e.message) {
        case 'invalid_code':
          return 'That code is wrong or has expired.';
        case 'invalid_password':
          return 'Your new password needs at least 8 characters.';
        case 'email_unavailable':
          return 'Password reset by email is not set up on this server yet.';
        default:
          return 'Something went wrong (${e.message}). Please try again.';
      }
    }
    return "Can't connect right now. Check your internet and try again.";
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient(ref.read(sessionProvider).serverUrl)
          .forgot(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      final j = await ApiClient(ref.read(sessionProvider).serverUrl)
          .resetPassword(
            email: _email.text.trim(),
            code: _code.text.trim(),
            newPassword: _password.text,
          );
      await session.storeLogin(j);
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsetsDirectional.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  _sent
                      ? 'We sent a 6-digit code to your email. Type it below with a new password.'
                      : 'Type your email and we will send you a code.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  enabled: !_sent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_sent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password (8 or more characters)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
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
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _busy ? null : (_sent ? _reset : _sendCode),
                  child: Text(
                    _busy
                        ? 'One moment...'
                        : (_sent ? 'Set new password' : 'Send me a code'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
