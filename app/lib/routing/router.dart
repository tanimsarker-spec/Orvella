import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/session.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/cinema/cinema_screen.dart';
import '../features/cinema/quality_screen.dart';
import '../features/cinema/source_screens.dart';
import '../features/drive/drive_screen.dart';
import '../features/home/home_screen.dart';
import '../features/rooms/room_forms.dart';
import '../features/settings/settings_screen.dart';
import '../features/shared/placeholder_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<SessionState>(
    sessionProvider,
    (previous, next) => refresh.value++,
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    errorBuilder: (context, state) => const PlaceholderScreen('Page not found'),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == '/splash') return null;
      final signedIn = ref.read(sessionProvider).signedIn;
      final onboarded = ref.read(prefsProvider).getBool('onboarded') ?? false;
      const signedOutPages = {'/sign-in', '/sign-up', '/log-in', '/forgot'};
      if (!signedIn) {
        if (!onboarded) return loc == '/onboarding' ? null : '/onboarding';
        return signedOutPages.contains(loc) ? null : '/sign-in';
      }
      if (signedOutPages.contains(loc) || loc == '/onboarding') return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const AuthScreen(isSignUp: true),
      ),
      GoRoute(
        path: '/forgot',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/log-in',
        builder: (context, state) => const AuthScreen(isSignUp: false),
      ),
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/rooms/join',
        builder: (context, state) => const JoinRoomScreen(),
      ),
      GoRoute(
        path: '/rooms/:id',
        builder: (context, state) =>
            CinemaScreen(roomId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'source',
            builder: (context, state) =>
                SourceScreen(roomId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'local',
            builder: (context, state) =>
                LocalFileScreen(roomId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'drive',
            builder: (context, state) =>
                DriveScreen(roomId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'quality',
            builder: (context, state) =>
                QualityScreen(roomId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});
