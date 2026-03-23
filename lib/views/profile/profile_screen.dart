import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/log_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../paywall/paywall_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── User card ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Avatar placeholder
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.textSecondary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.name ?? 'Your Name',
                        style: AppTextStyles.labelLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        profile?.email ?? '',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                if (profile?.isPremium == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accentMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Premium',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Goals section ──────────────────────────────────────────
          _SectionLabel('Goals'),
          _Tile(
            icon: Icons.local_fire_department_outlined,
            label: 'Daily calorie goal',
            value: '${profile?.calorieGoal ?? 2000} kcal',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _GoalEditorSheet(
                currentGoal: profile?.calorieGoal ?? 2000,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Subscription section ───────────────────────────────────
          _SectionLabel('Subscription'),
          if (profile?.isPremium != true)
            _UpgradeBanner(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const PaywallSheet(),
              ),
            )
          else
            _Tile(
              icon: Icons.star_rounded,
              label: 'Premium active',
              value: 'Manage',
              onTap: () {},
            ),

          const SizedBox(height: 24),

          // ── App section ────────────────────────────────────────────
          _SectionLabel('App'),
          _Tile(
            icon: Icons.insights_rounded,
            label: 'Weekly insights',
            value: profile?.isPremium == true ? 'View' : 'Premium',
            onTap: () {
              if (profile?.isPremium != true) {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const PaywallSheet(),
                );
              }
            },
          ),

          const SizedBox(height: 32),

          // ── Sign out ───────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go('/onboarding');
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha:0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded,
                      color: AppColors.danger, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Sign out',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.caption.copyWith(letterSpacing: 0.8),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label, style: AppTextStyles.bodyLarge)),
            Text(value, style: AppTextStyles.bodyMedium),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Goal editor sheet ───────────────────────────────────────────────────────

class _GoalEditorSheet extends ConsumerStatefulWidget {
  final int currentGoal;
  const _GoalEditorSheet({required this.currentGoal});

  @override
  ConsumerState<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<_GoalEditorSheet> {
  late int _goal;
  bool _saving = false;

  static const _presets = [1500, 1800, 2000, 2500, 3000];

  @override
  void initState() {
    super.initState();
    _goal = widget.currentGoal;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'calorie_goal': _goal})
            .eq('id', session.user.id);
        // Refresh profile and today's log chip so changes are immediate.
        ref.invalidate(userProfileProvider);
        ref.read(logControllerProvider.notifier).refresh();
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // show nothing — non-fatal, user can try again
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Daily calorie goal', style: AppTextStyles.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Tap a preset or drag the slider to fine-tune.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),

            // Presets
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _presets.map((p) {
                final selected = p == _goal;
                return GestureDetector(
                  onTap: () => setState(() => _goal = p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.accent
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      '$p kcal',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: selected
                            ? AppColors.background
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Fine-tune slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fine-tune', style: AppTextStyles.caption),
                Text(
                  '$_goal kcal / day',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.accent),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.accent,
                overlayColor: AppColors.accent.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: _goal.toDouble(),
                min: 1200,
                max: 4000,
                divisions: 56,
                onChanged: (v) => setState(() => _goal = v.round()),
              ),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _UpgradeBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha:0.12),
              AppColors.accent.withValues(alpha:0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha:0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded,
                color: AppColors.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upgrade to Premium',
                      style: AppTextStyles.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    'Unlimited logs · Macros · Insights · ${AppConfig.premiumMonthlyPrice}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.accent, size: 18),
          ],
        ),
      ),
    );
  }
}
