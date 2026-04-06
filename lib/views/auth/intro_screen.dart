import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/haptic_service.dart';
import '../../widgets/tavera_logo.dart';

// ─── IntroScreen ──────────────────────────────────────────────────────────────
//
// Shown exactly once — on first launch before the auth screen.
// Uses the `introduction_screen` package for swipeable pages with animated
// dot indicators and Skip / Get Started buttons.
//
// The flag `intro_seen` is written to SharedPreferences on completion or skip
// so the flow is never repeated.

const _kIntroSeenKey = 'intro_seen';

/// Returns true if the user has already seen the intro.
Future<bool> hasSeenIntro() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kIntroSeenKey) ?? false;
}

Future<void> _markIntroSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kIntroSeenKey, true);
}

class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key});

  void _done(BuildContext context) {
    HapticService.heavy();
    _markIntroSeen();
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final bodyDecoration = PageDecoration(
      pageColor: AppColors.background,
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      bodyTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textSecondary,
        height: 1.55,
      ),
      bodyPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      titlePadding: const EdgeInsets.only(top: 0, bottom: 12),
      imagePadding: const EdgeInsets.only(top: 60, bottom: 24),
      footerFlex: 2,
    );

    return IntroductionScreen(
      globalBackgroundColor: AppColors.background,
      pages: [
        // ── Page 1 — Snap & track ──────────────────────────────────────────
        PageViewModel(
          title: 'Snap, track, done.',
          body: 'Point your camera at any meal and Tavera\'s AI reads the calories and macros in seconds. No typing, no searching.',
          image: _IntroIllustration(
            icon: Icons.camera_alt_rounded,
            badge: 'AI',
          ),
          decoration: bodyDecoration,
        ),

        // ── Page 2 — Smart insights ────────────────────────────────────────
        PageViewModel(
          title: 'Your personal\nnutrition coach.',
          body: 'Get weekly AI coaching tailored to your eating patterns — not generic advice. Understand trends, not just numbers.',
          image: _IntroIllustration(
            icon: Icons.auto_awesome_rounded,
            badge: 'Pro',
          ),
          decoration: bodyDecoration,
        ),

        // ── Page 3 — Goals ─────────────────────────────────────────────────
        PageViewModel(
          title: 'Reach your goals,\nyour way.',
          body: 'Set a calorie target, track macros, log water, and use GLP-1 mode or intermittent fasting timers — all in one place.',
          image: _IntroIllustration(
            icon: Icons.track_changes_rounded,
            badge: null,
          ),
          decoration: bodyDecoration,
        ),
      ],

      // ── Controls ───────────────────────────────────────────────────────────
      onDone: () => _done(context),
      onSkip: () => _done(context),
      showSkipButton: true,
      showDoneButton: true,
      showNextButton: true,

      skip: Text(
        'Skip',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      next: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_forward_ios_rounded,
            color: AppColors.background, size: 16),
      ),
      done: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          'Get started',
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.background,
          ),
        ),
      ),

      // ── Dot indicator ──────────────────────────────────────────────────────
      dotsDecorator: DotsDecorator(
        size: const Size(8, 8),
        activeSize: const Size(22, 8),
        color: AppColors.border,
        activeColor: AppColors.accent,
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      // ── Layout ─────────────────────────────────────────────────────────────
      isProgressTap: true,
      animationDuration: 350,
      curve: Curves.easeOutCubic,
    );
  }
}

// ─── Illustration widget ──────────────────────────────────────────────────────
//
// Each intro page shows a large centred icon inside a glowing accent ring
// with a small floating badge (e.g. "AI", "Pro").

class _IntroIllustration extends StatelessWidget {
  final IconData icon;
  final String? badge;

  const _IntroIllustration({required this.icon, this.badge});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Outer glow ring
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.18),
                width: 1.5,
              ),
            ),
          ),
          // Inner icon container
          Positioned.fill(
            child: Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface,
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(icon, color: AppColors.accent, size: 48),
              ),
            ),
          ),
          // Tavera logo watermark bottom
          Positioned(
            bottom: -6,
            left: 0,
            right: 0,
            child: Center(
              child: TaveraLogo(size: 28),
            ),
          ),
          // Optional floating badge
          if (badge != null)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.background,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
