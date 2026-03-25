import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../services/haptic_service.dart';
import '../capture/add_food_sheet.dart';

// ─── App Shell ────────────────────────────────────────────────────────────────
//
// Persistent scaffold wrapper used by StatefulShellRoute. Renders the active
// tab's child and a bottom navigation bar with a centre FAB that opens the
// food-capture picker. All navigation state is owned by GoRouter — this widget
// only translates tap events into branch switches.

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    HapticService.selection();
    navigationShell.goBranch(
      index,
      // When tapping the already-active tab, scroll to top by re-creating
      // the initial location, which GoRouter handles via key re-use.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  void _onAddTapped(BuildContext context) {
    HapticService.medium();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddFoodSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = navigationShell.currentIndex;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      bottomNavigationBar: Container(
        // Nav bar background with top border
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          height: 60 + bottomPad,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Home tab
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  active: currentIndex == 0,
                  onTap: () => _onTap(0),
                ),

                // History / Nutrition tab
                _NavItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'History',
                  active: currentIndex == 1,
                  onTap: () => _onTap(1),
                ),

                // Centre FAB
                _CenterFab(onTap: () => _onAddTapped(context)),

                // (placeholder slot so FAB stays visually centred)
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  active: currentIndex == 2,
                  onTap: () => _onTap(2),
                ),

                // Extra invisible spacer to balance 4-slot layout
                const SizedBox(width: 64),
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
              color: AppColors.accent.withValues(alpha: 0.35),
              blurRadius: 14,
              spreadRadius: 0,
              offset: const Offset(0, 4),
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
