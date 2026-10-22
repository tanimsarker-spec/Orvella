import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/session.dart';
import 'routing/router.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const OrvellaApp(),
    ),
  );
}

class OrvellaApp extends ConsumerWidget {
  const OrvellaApp({super.key});

  ThemeData _theme(Brightness brightness, OrvellaTokens tokens) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF6D5BD0),
    brightness: brightness,
    extensions: [tokens],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Orvella',
      routerConfig: ref.watch(routerProvider),
      theme: _theme(Brightness.light, OrvellaTokens.light),
      darkTheme: _theme(Brightness.dark, OrvellaTokens.dark),
    );
  }
}
