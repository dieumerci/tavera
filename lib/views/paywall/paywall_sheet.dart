import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/haptic_service.dart';

/// Convenience helper — shows [PaywallSheet] as a bottom sheet from any
/// [BuildContext]. Centralises the identical `showModalBottomSheet` call that
/// was previously duplicated across four screens.
void showPaywallSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const PaywallSheet(),
  );
}

class PaywallSheet extends StatelessWidget {
  const PaywallSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 28),

          // Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.accentMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.accent,
              size: 34,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            "You've hit today's limit",
            style: AppTextStyles.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Free plan allows 3 logs per day.\nUpgrade for unlimited tracking.',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 28),

          // Feature list
          const _Feature(
            icon: Icons.all_inclusive_rounded,
            label: 'Unlimited daily logs',
          ),
          const _Feature(
            icon: Icons.science_outlined,
            label: 'Full macros (protein, carbs, fat)',
          ),
          const _Feature(
            icon: Icons.insights_rounded,
            label: 'Weekly AI coaching insights',
          ),
          const _Feature(
            icon: Icons.memory_rounded,
            label: 'Meal memory & one-tap re-logging',
          ),
          const _Feature(
            icon: Icons.restaurant_menu_rounded,
            label: 'AI meal planner + grocery lists',
          ),
          const _Feature(
            icon: Icons.emoji_events_rounded,
            label: 'Create social challenges',
          ),

          const SizedBox(height: 28),

          // CTA
          ElevatedButton(
            onPressed: () {
              HapticService.heavy();
              // TODO: connect RevenueCat / StoreKit
              Navigator.of(context).pop();
            },
            child: Text('Upgrade — ${AppConfig.premiumMonthlyPrice}'),
          ),

          const SizedBox(height: 10),

          TextButton(
            onPressed: () {
              HapticService.selection();
              Navigator.of(context).pop();
            },
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Feature({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 14),
          Text(label, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }
}
