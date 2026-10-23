import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import 'google_button.dart';

/// Sign-up (isSignUp: true) or log-in form.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({required this.isSignUp, super.key});

  final bool isSignUp;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendly(Object e) {
    if (e is ApiException) {
      switch (e.message) {
        case 'email_taken':
          return 'That email already has an account. Try logging in instead.';
        case 'invalid_credentials':
          return 'Wrong email or password.';
        case 'invalid_email':
          return 'Please type a real email address.';
        case 'invalid_password':
          return 'Your password needs at least 8 characters.';
        case 'invalid_display_name':
          return 'Pick a name with 1 to 32 letters or numbers.';
        default:
          return 'Something went wrong (${e.message}). Please try again.';
      }
    }
    return "Can't connect right now. Check your internet and try again.";
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      if (widget.isSignUp) {
        await session.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
      } else {
        await session.logIn(email: _email.text, password: _password.text);
      }
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signUp = widget.isSignUp;
    return Scaffold(
      appBar: AppBar(title: Text(signUp ? 'Create account' : 'Log in')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsetsDirectional.all(24),
                shrinkWrap: true,
                children: [
                  const GoogleSignInButton(),
                  const SizedBox(height: 8),
                  const Center(child: Text('or use your email')),
                  const SizedBox(height: 16),
                  if (signUp) ...[
                    TextField(
                      controller: _name,
                      maxLength: 32,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.nickname],
                      decoration: const InputDecoration(
                        labelText: 'Your name (friends will see this)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      signUp
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: (value) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: signUp
                          ? 'Password (8 or more characters)'
                          : 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  if (!signUp)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => context.push('/forgot'),
                        child: const Text('Forgot password?'),
                      ),
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
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy
                          ? 'One moment...'
                          : (signUp ? 'Create my account' : 'Log in'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => context.pushReplacement(
                            signUp ? '/log-in' : '/sign-up',
                          ),
                    child: Text(
                      signUp
                          ? 'I already have an account'
                          : 'I need to create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
