import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../controllers/auth_controller.dart';
import '../../views/auth/onboarding_screen.dart';
import '../../views/barcode/barcode_screen.dart';
import '../../views/camera/camera_screen.dart';
import '../../views/challenges/challenge_detail_screen.dart';
import '../../views/challenges/challenges_screen.dart';
import '../../views/fasting/fasting_screen.dart';
import '../../views/meal_planner/meal_planner_screen.dart';
import '../../views/weekly_summary/weekly_summary_screen.dart';
import '../../views/coaching/coaching_screen.dart';
import '../../views/dashboard/dashboard_screen.dart';
import '../../views/history/history_screen.dart';
import '../../views/profile/profile_screen.dart';
import '../../views/shell/app_shell.dart';

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
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);

      // While auth is loading, don't redirect
      if (authAsync.isLoading) return null;

      final isAuthenticated = authAsync.valueOrNull?.session != null;
      final atOnboarding = state.matchedLocation == '/onboarding';

      if (!isAuthenticated && !atOnboarding) return '/onboarding';
      if (isAuthenticated && atOnboarding) return '/';
      return null;
    },
    routes: [
      // ── Unauthenticated ──────────────────────────────────────────────────
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _fadeTransition(
          state,
          const OnboardingScreen(),
        ),
      ),

      // ── Main app shell (persists bottom nav across tab switches) ─────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Tab 0 — Home / Dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) => _fadeTransition(
                  state,
                  const DashboardScreen(),
                ),
              ),
            ],
          ),

          // Tab 1 — Nutrition / History
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/nutrition',
                pageBuilder: (context, state) => _fadeTransition(
                  state,
                  const HistoryScreen(),
                ),
              ),
            ],
          ),

          // Tab 2 — Social Challenges
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/challenges',
                pageBuilder: (context, state) => _fadeTransition(
                  state,
                  const ChallengesScreen(),
                ),
              ),
            ],
          ),

          // Tab 3 — Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => _fadeTransition(
                  state,
                  const ProfileScreen(),
                ),
              ),
            ],
          ),
        ],
      ),

      // ── Full-screen modals (no bottom nav) ───────────────────────────────
      // Camera: accessed via the + FAB → "Take a Photo"
      GoRoute(
        path: '/camera',
        pageBuilder: (context, state) => _slideUpTransition(
          state,
          const CameraScreen(),
        ),
      ),

      // Barcode: accessed via the + FAB → "Scan Barcode"
      GoRoute(
        path: '/barcode',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const BarcodeScanScreen(),
        ),
      ),

      // Coaching insights (premium): push from Dashboard teaser card
      GoRoute(
        path: '/coaching',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const CoachingScreen(),
        ),
      ),

      // Meal Planner: accessed from Dashboard teaser or Profile
      GoRoute(
        path: '/meal-planner',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const MealPlannerScreen(),
        ),
      ),

      // Intermittent Fasting timer: accessed from Dashboard card or Profile
      GoRoute(
        path: '/fasting',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const FastingScreen(),
        ),
      ),

      // Weekly summary — accessed from dashboard streak card
      GoRoute(
        path: '/weekly-summary',
        pageBuilder: (context, state) => _slideTransition(
          state,
          const WeeklySummaryScreen(),
        ),
      ),

      // Challenge detail: accessed from list or Dashboard strip
      GoRoute(
        path: '/challenges/:id',
        pageBuilder: (context, state) => _slideTransition(
          state,
          ChallengeDetailScreen(
            challengeId: state.pathParameters['id']!,
          ),
        ),
      ),
    ],
  );
});

// ─── Transitions ──────────────────────────────────────────────────────────────

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

// Camera slides up from the bottom as a full-screen capture modal.
CustomTransitionPage<void> _slideUpTransition(
    GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1.0),
        end: Offset.zero,
      ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 320),
  );
}
