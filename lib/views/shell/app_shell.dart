import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../services/haptic_service.dart';
import '../capture/add_food_sheet.dart';

// ─── App Shell ────────────────────────────────────────────────────────────────
//
// Persistent scaffold wrapper used by StatefulShellRoute.
//
// Navigation bar: persistent_bottom_nav_bar Style15 — a frosted-glass floating
// pill bar with a circular + button elevated above the bar centre (no notch).
//
// Tab layout  (indices match StatefulShellBranch order in app_router.dart):
//   0 — Home (Dashboard)
//   1 — History / Nutrition
//   [Centre + button — not a tab]
//   2 — Challenges
//   3 — Profile
//
// Architecture notes:
//   • `extendBody: true` lets content flow behind the translucent nav bar so
//     the blur effect is visible. Screens add their own bottom padding via
//     `kNavBarTotalHeight` or rely on the `SliverPadding` at list end.
//   • The FAB is a raw GestureDetector inside the nav bar Stack — no
//     Scaffold.floatingActionButton / BottomAppBar notch needed.
//   • Tab switching is still owned entirely by GoRouter (goBranch).

// Exposed so screens can add matching bottom padding when needed.
const double kNavBarHeight = 62.0;
const double kFabSize = 58.0;
const double kFabLift = 24.0; // px the FAB rises above the bar top edge

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    HapticService.medium();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _onAddTapped(BuildContext context) {
    HapticService.heavy();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddFoodSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = navigationShell.currentIndex;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true, // body renders behind the translucent pill bar
      body: navigationShell,
      bottomNavigationBar: _Style15NavBar(
        selectedIndex: idx,
        bottomPad: bottomPad,
        onTabSelected: _onTap,
        onAddTapped: () => _onAddTapped(context),
      ),
    );
  }
}

// ─── Style 15 nav bar ─────────────────────────────────────────────────────────
//
// A frosted-glass floating pill with a circular + button elevated above the
// bar's centre, matching persistent_bottom_nav_bar NavBarStyle.style15.
//
// Layout (cross-section view):
//
//               ┌──────────────────────────────────────────┐
//               │              (kFabLift px)               │  ← transparent gap for FAB
//   ┌───────────┴──────────────────────────────────────────┴───────────┐
//   │  [Home]  [History]      [  +  ]      [Challenges]  [Profile]    │  ← pill bar
//   └─────────────────────────────────────────────────────────────────┘
//   └─────── safe-area bottom padding ───────────────────────────────┘

class _Style15NavBar extends StatelessWidget {
  final int selectedIndex;
  final double bottomPad;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onAddTapped;

  const _Style15NavBar({
    required this.selectedIndex,
    required this.bottomPad,
    required this.onTabSelected,
    required this.onAddTapped,
  });

  @override
  Widget build(BuildContext context) {
    // Total height the Scaffold reserves (so screens scroll above it).
    final totalHeight =
        kFabLift + kNavBarHeight + bottomPad;

    return SizedBox(
      height: totalHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // ── Frosted pill bar ───────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 14,
            right: 14,
            child: _PillBar(
              selectedIndex: selectedIndex,
              bottomPad: bottomPad,
              onTabSelected: onTabSelected,
            ),
          ),

          // ── Floating + button ──────────────────────────────────────────
          // Sits at the top of the pill, half-above half-inside.
          Positioned(
            bottom: bottomPad + kNavBarHeight / 2 - kFabSize / 2 + kFabLift / 2,
            child: _Style15Fab(onTap: onAddTapped),
          ),
        ],
      ),
    );
  }
}

// ─── Pill bar (frosted glass container) ───────────────────────────────────────

class _PillBar extends StatelessWidget {
  final int selectedIndex;
  final double bottomPad;
  final ValueChanged<int> onTabSelected;

  const _PillBar({
    required this.selectedIndex,
    required this.bottomPad,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            color: AppColors.surface.withValues(alpha: 0.93),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top hairline separator
                Container(
                  height: 1,
                  color: AppColors.border.withValues(alpha: 0.6),
                ),
                // Nav items row
                SizedBox(
                  height: kNavBarHeight,
                  child: Row(
                    children: [
                      // ── Left items ─────────────────────────────────────
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _NavItem(
                              icon: Icons.home_rounded,
                              label: 'Home',
                              active: selectedIndex == 0,
                              onTap: () => onTabSelected(0),
                            ),
                            _NavItem(
                              icon: Icons.bar_chart_rounded,
                              label: 'History',
                              active: selectedIndex == 1,
                              onTap: () => onTabSelected(1),
                            ),
                          ],
                        ),
                      ),
                      // ── Centre gap (FAB sits here visually) ────────────
                      const SizedBox(width: kFabSize + 8),
                      // ── Right items ────────────────────────────────────
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _NavItem(
                              icon: Icons.emoji_events_rounded,
                              label: 'Challenges',
                              active: selectedIndex == 2,
                              onTap: () => onTabSelected(2),
                            ),
                            _NavItem(
                              icon: Icons.person_rounded,
                              label: 'Profile',
                              active: selectedIndex == 3,
                              onTap: () => onTabSelected(3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Safe-area spacer (home indicator on iOS, gesture bar on Android)
                SizedBox(height: bottomPad),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Nav item ─────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Style 15 floating + button ───────────────────────────────────────────────
//
// Circular accent-coloured button elevated above the pill bar. No Scaffold
// notch needed — it is a plain Widget positioned in the nav bar Stack.

class _Style15Fab extends StatelessWidget {
  final VoidCallback onTap;
  const _Style15Fab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: kFabSize,
        height: kFabSize,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.background.withValues(alpha: 0.8),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.20),
              blurRadius: 8,
              spreadRadius: 2,
              offset: Offset.zero,
            ),
          ],
        ),
        child: const Icon(
          Icons.add_rounded,
          color: AppColors.background,
          size: 28,
        ),
      ),
    );
  }
}
