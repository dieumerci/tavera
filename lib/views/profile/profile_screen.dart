import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/challenge_controller.dart';
import '../../controllers/fasting_controller.dart';
import '../../controllers/log_controller.dart';
import '../../core/config/app_config.dart';
import '../../services/haptic_service.dart';
import '../../services/notification_service.dart';
import '../../services/revenue_cat_service.dart';
import '../../services/subscription_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/challenge.dart';
import '../../models/user_profile.dart';
import '../../widgets/labeled_text_field.dart';
import '../../widgets/sheet_handle.dart';
import '../paywall/paywall_sheet.dart';

/// Calls the `delete-account` Edge Function, signs out, and navigates away.
/// Uses a top-level function so the logic is reusable and not buried inside
/// a `ConsumerWidget.build` closure.
Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  // Optimistic UX: show a loading overlay via the scaffold messenger.
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Deleting account…'),
      duration: Duration(seconds: 30),
    ),
  );

  try {
    final response = await Supabase.instance.client.functions.invoke(
      'delete-account',
    );

    messenger.hideCurrentSnackBar();

    final body = response.data as Map<String, dynamic>?;
    final success = body?['success'] == true;

    if (!success) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Deletion failed', style: AppTextStyles.titleMedium),
            content: Text(
              body?['hint'] as String? ??
                  'Something went wrong. Please try again or contact support.',
              style: AppTextStyles.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // If there's a non-fatal warning (e.g. Auth row cleanup failed), show it
    // but continue — the user's data is already deleted.
    final warning = body?['warning'] as String?;

    await ref.read(authControllerProvider.notifier).signOut();

    if (context.mounted) {
      if (warning != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Note', style: AppTextStyles.titleMedium),
            content: Text(warning, style: AppTextStyles.bodyMedium),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      if (context.mounted) context.go('/onboarding');
    }
  } catch (e) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final isPremium = SubscriptionService.isPremium(ref);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        // Profile is a root tab — no back button. An explicit leading: null
        // here prevents GoRouter or the framework from auto-inserting one,
        // which would call Navigator.pop() and break the shell navigator.
        automaticallyImplyLeading: false,
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
                if (isPremium)
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
          _Tile(
            icon: Icons.monitor_weight_outlined,
            label: 'Body stats',
            value: profile?.canComputeBmr == true ? 'Edit' : 'Add',
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _BodyStatsSheet(profile: profile),
            ),
          ),

          // Net Carbs toggle
          _NetCarbsTile(netCarbsMode: profile?.netCarbsMode ?? false),

          const SizedBox(height: 24),

          // ── Subscription section ───────────────────────────────────
          _SectionLabel('Subscription'),
          if (!isPremium)
            _UpgradeBanner(
              onTap: () => showPaywallSheet(context, source: 'profile'),
            )
          else
            _Tile(
              icon: Icons.star_rounded,
              label: 'Premium active',
              value: 'Restore',
              onTap: () async {
                HapticService.selection();
                await RevenueCatService.restore();
                ref.invalidate(revenueCatPremiumProvider);
              },
            ),

          const SizedBox(height: 24),

          // ── Features section ───────────────────────────────────────
          _SectionLabel('Features'),
          _Tile(
            icon: Icons.insights_rounded,
            label: 'AI Coaching',
            value: isPremium ? 'View' : 'Premium',
            onTap: () {
              if (isPremium) {
                context.push('/coaching');
              } else {
                showPaywallSheet(context, source: 'profile_coaching');
              }
            },
          ),
          _Tile(
            icon: Icons.restaurant_menu_rounded,
            label: 'Meal Planner',
            value: isPremium ? 'View' : 'Premium',
            onTap: () {
              if (isPremium) {
                context.push('/meal-planner');
              } else {
                showPaywallSheet(context, source: 'profile_meal_planner');
              }
            },
          ),
          _Tile(
            icon: Icons.emoji_events_rounded,
            label: 'Challenges',
            value: 'View',
            onTap: () => context.push('/challenges'),
          ),
          _FastingTile(),

          const SizedBox(height: 24),

          // ── Challenge badges ───────────────────────────────────────
          _ChallengeBadgesSection(),

          const SizedBox(height: 32),

          // ── Danger zone ────────────────────────────────────────────
          _SectionLabel('Account'),
          _Tile(
            icon: Icons.delete_outline_rounded,
            label: 'Delete account',
            value: '',
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text('Delete account?',
                    style: AppTextStyles.titleMedium),
                content: Text(
                  'All your meal logs and data will be permanently deleted. '
                  'This cannot be undone.',
                  style: AppTextStyles.bodyMedium,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _deleteAccount(context, ref);
                    },
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Notifications ──────────────────────────────────────────
          _SectionLabel('Notifications'),
          const _NotificationTile(),

          const SizedBox(height: 16),

          // ── Sign out ───────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              HapticService.medium();
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

// ─── Challenge badge section ─────────────────────────────────────────────────

class _ChallengeBadgesSection extends ConsumerWidget {
  const _ChallengeBadgesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(completedChallengesProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (completed) {
        if (completed.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Achievements'),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: completed.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _BadgeChip(completed[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final Challenge challenge;
  const _BadgeChip(this.challenge);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(challenge.type.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(
            challenge.title,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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
      onTap: () {
        HapticService.selection();
        onTap();
      },
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
            const SheetHandle(),
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
                  onTap: () {
                    HapticService.selection();
                    setState(() => _goal = p);
                  },
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

// ─── Body stats sheet ────────────────────────────────────────────────────────

class _BodyStatsSheet extends ConsumerStatefulWidget {
  final UserProfile? profile;
  const _BodyStatsSheet({required this.profile});

  @override
  ConsumerState<_BodyStatsSheet> createState() => _BodyStatsSheetState();
}

class _BodyStatsSheetState extends ConsumerState<_BodyStatsSheet> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _ageCtrl;
  Sex? _sex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(
      text: widget.profile?.weightKg?.toStringAsFixed(1) ?? '',
    );
    _heightCtrl = TextEditingController(
      text: widget.profile?.heightCm?.toString() ?? '',
    );
    _ageCtrl = TextEditingController(
      text: widget.profile?.age?.toString() ?? '',
    );
    _sex = widget.profile?.sex;
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  // Compute BMR preview from the current form values.
  int? get _bmrPreview {
    final w = double.tryParse(_weightCtrl.text);
    final h = int.tryParse(_heightCtrl.text);
    final a = int.tryParse(_ageCtrl.text);
    if (w == null || h == null || a == null || _sex == null) return null;
    final bmr = _sex == Sex.female
        ? 10 * w + 6.25 * h - 5 * a - 161
        : 10 * w + 6.25 * h - 5 * a + 5;
    return (bmr * 1.2).round();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        await Supabase.instance.client.from('profiles').update({
          'weight_kg': double.tryParse(_weightCtrl.text),
          'height_cm': int.tryParse(_heightCtrl.text),
          'age': int.tryParse(_ageCtrl.text),
          'sex': _sex?.name,
          // Auto-apply the BMR-based goal suggestion if available.
          if (_bmrPreview != null) 'calorie_goal': _bmrPreview,
        }).eq('id', session.user.id);
        ref.invalidate(userProfileProvider);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Non-fatal.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _bmrPreview;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 20),
              Text('Body stats', style: AppTextStyles.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Used to compute a personalised calorie goal via the '
                'Mifflin-St Jeor equation.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),

              // ── Input row: weight + height ─────────────────────────
              Row(
                children: [
                  Expanded(
                    child: LabeledTextField(
                      controller: _weightCtrl,
                      label: 'Weight',
                      suffixText: 'kg',
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledTextField(
                      controller: _heightCtrl,
                      label: 'Height',
                      suffixText: 'cm',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledTextField(
                      controller: _ageCtrl,
                      label: 'Age',
                      suffixText: 'yrs',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Sex selection ─────────────────────────────────────
              Text('Biological sex', style: AppTextStyles.caption),
              const SizedBox(height: 8),
              Row(
                children: Sex.values.map((s) {
                  final selected = s == _sex;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticService.selection();
                        setState(() => _sex = s);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: EdgeInsets.only(
                            right: s != Sex.values.last ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.accent
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? AppColors.accent
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          s.name[0].toUpperCase() + s.name.substring(1),
                          style: AppTextStyles.caption.copyWith(
                            color: selected
                                ? AppColors.background
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // ── BMR preview ───────────────────────────────────────
              if (preview != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accentMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded,
                          color: AppColors.accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Estimated goal: $preview kcal/day '
                          '(sedentary baseline)',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
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
      ),
    );
  }
}

// ─── Notification tile ────────────────────────────────────────────────────────

class _NotificationTile extends ConsumerStatefulWidget {
  const _NotificationTile();

  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  bool? _enabled; // null = loading

  @override
  void initState() {
    super.initState();
    NotificationService.isEnabled().then(
      (v) { if (mounted) setState(() => _enabled = v); },
    );
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!mounted) return;
      setState(() => _enabled = granted);
      if (granted) {
        final logs =
            ref.read(logControllerProvider).valueOrNull?.todayLogs ?? [];
        await NotificationService.scheduleDailyReminders(logs);
      }
    } else {
      await NotificationService.cancelAll();
      if (mounted) setState(() => _enabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_outlined,
              color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meal Reminders', style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(
                  'Breakfast · Lunch · Dinner',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_enabled == null)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent),
            )
          else
            Switch(
              value: _enabled!,
              activeThumbColor: AppColors.accent,
              activeTrackColor: AppColors.accentMuted,
              onChanged: _toggle,
            ),
        ],
      ),
    );
  }
}

// ─── Net Carbs Toggle ─────────────────────────────────────────────────────────

class _NetCarbsTile extends ConsumerWidget {
  final bool netCarbsMode;
  const _NetCarbsTile({required this.netCarbsMode});

  Future<void> _toggle(bool value, WidgetRef ref) async {
    HapticService.selection();
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    await Supabase.instance.client
        .from('profiles')
        .update({'net_carbs_mode': value})
        .eq('id', session.user.id);
    // userProfileProvider is a StreamProvider — it will auto-update via
    // Supabase Realtime, so no manual invalidation is needed here.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.grain_rounded,
              color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Carbs mode', style: AppTextStyles.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  'Show carbs − fiber in all macro displays',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: netCarbsMode,
            activeThumbColor: AppColors.accent,
            activeTrackColor: AppColors.accentMuted,
            onChanged: (v) => _toggle(v, ref),
          ),
        ],
      ),
    );
  }
}

// ─── Fasting Tile ─────────────────────────────────────────────────────────────

class _FastingTile extends ConsumerWidget {
  const _FastingTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fastAsync = ref.watch(fastingControllerProvider);
    final isActive = fastAsync.valueOrNull?.isActive == true;

    return _Tile(
      icon: Icons.timer_outlined,
      label: 'Intermittent Fasting',
      value: isActive ? 'Active' : 'Start',
      onTap: () => context.push('/fasting'),
    );
  }
}

// ─── Upgrade Banner ───────────────────────────────────────────────────────────

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
