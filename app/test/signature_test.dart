import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orvella/core/session.dart';
import 'package:orvella/features/home/home_screen.dart';
import 'package:orvella/theme/tokens.dart';
import 'package:orvella/widgets/creator_signature.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('signature renders exact text at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [OrvellaTokens.dark]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: Center(child: CreatorSignature())),
      ),
    );
    expect(find.text('TanimSarker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen shows signature once and main actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: ThemeData(extensions: const [OrvellaTokens.dark]),
          home: const HomeScreen(),
        ),
      ),
    );
    expect(find.text('TanimSarker'), findsOneWidget);
    expect(find.text('Create room'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
    expect(find.text('No recent rooms yet.'), findsOneWidget);
  });
}
