import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/analytics_service.dart';
import '../../services/haptic_service.dart';
import '../../services/revenue_cat_service.dart';
import '../../services/subscription_service.dart';

/// Convenience helper — shows [PaywallSheet] as a bottom sheet from any
/// [BuildContext]. Centralises the identical `showModalBottomSheet` call that
/// was previously duplicated across four screens.
void showPaywallSheet(BuildContext context, {String source = 'unknown'}) {
  AnalyticsService.track('paywall_shown', properties: {'source': source});
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const PaywallSheet(),
  );
}

class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key});

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  // The monthly package from RevenueCat; null when SDK is not configured.
  Package? _monthlyPackage;
  Package? _annualPackage;

  bool _loading = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offering = await RevenueCatService.getDefaultOffering();
    if (!mounted) return;
    setState(() {
      _monthlyPackage = offering?.monthly;
      _annualPackage = offering?.annual;
    });
  }

  // ── Purchase ──────────────────────────────────────────────────────────────

  Future<void> _purchase(Package package) async {
    setState(() => _loading = true);
    HapticService.heavy();
    try {
      final success = await RevenueCatService.purchasePackage(package);
      if (!mounted) return;
      if (success) {
        // Invalidate cached status so the rest of the app unlocks immediately.
        ref.invalidate(revenueCatPremiumProvider);
        AnalyticsService.track('subscription_started', properties: {
          'package_id': package.identifier,
          'product_id': package.storeProduct.identifier,
        });
        Navigator.of(context).pop();
        _showSuccessSnack();
      }
    } catch (_) {
      if (!mounted) return;
      _showErrorSnack('Purchase failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    HapticService.selection();
    try {
      final success = await RevenueCatService.restore();
      if (!mounted) return;
      if (success) {
        ref.invalidate(revenueCatPremiumProvider);
        AnalyticsService.track('subscription_restored');
        Navigator.of(context).pop();
        _showSuccessSnack(message: 'Premium restored!');
      } else {
        _showErrorSnack('No active subscription found.');
      }
    } catch (_) {
      if (!mounted) return;
      _showErrorSnack('Restore failed. Please try again.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _showSuccessSnack({String message = 'Welcome to Tavera Premium! 🎉'}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Price helpers ──────────────────────────────────────────────────────────

  String get _monthlyPriceText {
    final pkg = _monthlyPackage;
    if (pkg != null) return '${pkg.storeProduct.priceString}/month';
    return AppConfig.premiumMonthlyPrice;
  }

  String get _annualPriceText {
    final pkg = _annualPackage;
    if (pkg != null) return '${pkg.storeProduct.priceString}/year';
    return '\$39.99/year';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasPackages = _monthlyPackage != null || _annualPackage != null;

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

          // ── Annual package (best value) ──────────────────────────────────
          if (_annualPackage != null) ...[
            _PlanOption(
              label: 'Annual',
              price: _annualPriceText,
              badge: 'Best value',
              onTap: _loading ? null : () => _purchase(_annualPackage!),
              loading: _loading,
            ),
            const SizedBox(height: 10),
          ],

          // ── Monthly CTA (primary) ────────────────────────────────────────
          ElevatedButton(
            onPressed: _loading
                ? null
                : () {
                    final pkg = _monthlyPackage;
                    if (pkg != null) {
                      _purchase(pkg);
                    } else {
                      // RevenueCat not configured — show coming-soon note.
                      HapticService.heavy();
                      Navigator.of(context).pop();
                    }
                  },
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    hasPackages
                        ? 'Upgrade — $_monthlyPriceText'
                        : 'Upgrade — ${AppConfig.premiumMonthlyPrice}',
                  ),
          ),

          const SizedBox(height: 10),

          // ── Restore + dismiss row ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _restoring ? null : _restore,
                child: _restoring
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : Text(
                        'Restore',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
              Text(
                '·',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
              ),
              TextButton(
                onPressed: () {
                  HapticService.selection();
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Not now',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Annual plan option ───────────────────────────────────────────────────────

class _PlanOption extends StatelessWidget {
  final String label;
  final String price;
  final String? badge;
  final VoidCallback? onTap;
  final bool loading;

  const _PlanOption({
    required this.label,
    required this.price,
    this.badge,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.labelLarge),
                Text(
                  price,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            const Spacer(),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Feature row ─────────────────────────────────────────────────────────────

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
