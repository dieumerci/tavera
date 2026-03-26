import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../services/haptic_service.dart';
import '../capture/add_food_sheet.dart';

// ─── App Shell ────────────────────────────────────────────────────────────────
//
// Persistent scaffold wrapper used by StatefulShellRoute. Renders the active
// tab's child and a bottom navigation bar with a floating centre FAB that
// opens the food-capture picker.
//
// Tab layout  (indices match StatefulShellBranch order in app_router.dart):
//   0 — Home (Dashboard)
//   1 — History / Nutrition
//   [FAB notch — not a tab]
//   2 — Challenges
//   3 — Profile
//
// The FAB is the Scaffold's floatingActionButton placed at centerDocked so
// Flutter's BottomAppBar automatically carves a matching notch in the bar.
// All navigation state is owned by GoRouter — this widget only translates
// tap events into branch switches.

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    // Medium impact on every tab switch — noticeably strong per UX spec.
    HapticService.medium();
    navigationShell.goBranch(
      index,
      // When tapping the already-active tab, return to the branch root
      // (restores scroll position / initial location via GoRouter key reuse).
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _onAddTapped(BuildContext context) {
    // Heavy impact for the primary action FAB — most emphatic haptic tier.
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
      body: navigationShell,

      // Floating FAB centred on the BottomAppBar notch.
      floatingActionButton: _CenterFab(onTap: () => _onAddTapped(context)),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // BottomAppBar must be the direct bottomNavigationBar (not wrapped in
      // a Column) so the Scaffold can read its notch geometry for the FAB.
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        elevation: 0,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subtle 1px separator between content and nav bar.
            Container(height: 1, color: AppColors.border),
            SizedBox(
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Left side — Home & History
                  _NavItem(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    active: idx == 0,
                    onTap: () => _onTap(0),
                  ),
                  _NavItem(
                    icon: Icons.bar_chart_rounded,
                    label: 'History',
                    active: idx == 1,
                    onTap: () => _onTap(1),
                  ),

                  // Centre gap — reserved for the floating FAB.
                  const SizedBox(width: 72),

                  // Right side — Challenges & Profile
                  _NavItem(
                    icon: Icons.emoji_events_rounded,
                    label: 'Challenges',
                    active: idx == 2,
                    onTap: () => _onTap(2),
                  ),
                  _NavItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    active: idx == 3,
                    onTap: () => _onTap(3),
                  ),
                ],
              ),
            ),
            // Bottom safe-area spacer (home indicator on iOS, gesture bar on Android).
            SizedBox(height: bottomPad),
          ],
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
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
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

// ─── Centre FAB ───────────────────────────────────────────────────────────────
//
// Custom floating action button. Rendered as the Scaffold.floatingActionButton
// at FloatingActionButtonLocation.centerDocked so Flutter automatically creates
// a matching curved notch in the BottomAppBar. The 56px diameter is the
// Material Design standard FAB size; BottomAppBar measures it to set the notch.

class _CenterFab extends StatelessWidget {
  final VoidCallback onTap;
  const _CenterFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.40),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.15),
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
