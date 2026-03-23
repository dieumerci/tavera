import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controllers/auth_controller.dart';
import '../../views/auth/onboarding_screen.dart';
import '../../views/camera/camera_screen.dart';
import '../../views/history/history_screen.dart';
import '../../views/profile/profile_screen.dart';

// A ChangeNotifier that fires whenever auth state changes,
// used to trigger GoRouter redirect re-evaluation.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);

  return GoRouter(
    initialLocation: '/camera',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);

      // While auth is loading, don't redirect
      if (authAsync.isLoading) return null;

      final isAuthenticated = authAsync.valueOrNull?.session != null;
      final atOnboarding = state.matchedLocation == '/onboarding';

      if (!isAuthenticated && !atOnboarding) return '/onboarding';
      if (isAuthenticated && atOnboarding) return '/camera';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _fadeTransition(
          state,
          const OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: '/camera',
        pageBuilder: (context, state) => _fadeTransition(
          state,
          const CameraScreen(),
        ),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const HistoryScreen(),
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const ProfileScreen(),
        ),
      ),
    ],
  );
});

CustomTransitionPage<void> _fadeTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 200),
  );
}

CustomTransitionPage<void> _slideTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: animation, child: child),
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );
}
