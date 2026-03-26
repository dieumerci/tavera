import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../controllers/coaching_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/coaching_insight.dart';
import '../../services/haptic_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/tavera_loading.dart';
import '../paywall/paywall_sheet.dart';

// ─── CoachingScreen ───────────────────────────────────────────────────────────
//
// Shows the user's AI coaching insights grouped by week.
// Premium-gated: shows upgrade prompt to free users.

class CoachingScreen extends ConsumerStatefulWidget {
  const CoachingScreen({super.key});

  @override
  ConsumerState<CoachingScreen> createState() => _CoachingScreenState();
}

class _CoachingScreenState extends ConsumerState<CoachingScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger generation for the current week when the screen first opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (SubscriptionService.isPremium(ref)) {
        ref.read(coachingControllerProvider.notifier).generate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = SubscriptionService.isPremium(ref);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            HapticService.selection();
            context.pop();
          },
        ),
        title: const Text('AI Coaching'),
        actions: [
          if (isPremium)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () {
                HapticService.selection();
                ref.read(coachingControllerProvider.notifier).generate();
              },
              tooltip: 'Refresh insights',
            ),
        ],
      ),
      body: isPremium ? const _InsightsList() : const _PaywallPlaceholder(),
    );
  }
}

// ─── Insights list ────────────────────────────────────────────────────────────

class _InsightsList extends ConsumerWidget {
  const _InsightsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(coachingControllerProvider);

    return insightsAsync.when(
      loading: () => const Center(child: TaveraLoading()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 36),
              const SizedBox(height: 12),
              Text('Could not load insights',
                  style: AppTextStyles.titleMedium),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  HapticService.medium();
                  ref.invalidate(coachingControllerProvider);
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
      data: (insights) {
        if (insights.isEmpty) {
          return const _EmptyState();
        }

        // Group by week_start descending.
        final Map<DateTime, List<CoachingInsight>> grouped = {};
        for (final insight in insights) {
          grouped.putIfAbsent(insight.weekStart, () => []).add(insight);
        }
        final weeks = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          itemCount: weeks.length,
          itemBuilder: (context, i) {
            final week = weeks[i];
            final weekInsights = grouped[week]!;
            final isCurrentWeek = _isCurrentWeek(week);
            return _WeekSection(
              weekStart: week,
              insights: weekInsights,
              isCurrentWeek: isCurrentWeek,
            );
          },
        );
      },
    );
  }

  static bool _isCurrentWeek(DateTime weekStart) {
    final now = DateTime.now();
    final thisMonday = DateTime(
        now.year, now.month, now.day - (now.weekday - DateTime.monday));
    return weekStart.year == thisMonday.year &&
        weekStart.month == thisMonday.month &&
        weekStart.day == thisMonday.day;
  }
}

// ─── Week section ─────────────────────────────────────────────────────────────

class _WeekSection extends StatelessWidget {
  final DateTime weekStart;
  final List<CoachingInsight> insights;
  final bool isCurrentWeek;

  const _WeekSection({
    required this.weekStart,
    required this.insights,
    required this.isCurrentWeek,
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = isCurrentWeek
        ? 'This week'
        : '${DateFormat('MMM d').format(weekStart)} – ${DateFormat('MMM d').format(weekEnd)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Row(
            children: [
              Text(label, style: AppTextStyles.titleMedium),
              if (isCurrentWeek) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'NEW',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ...insights.map((insight) => _InsightCard(insight: insight)),
      ],
    );
  }
}

// ─── Insight card ─────────────────────────────────────────────────────────────

class _InsightCard extends ConsumerWidget {
  final CoachingInsight insight;
  const _InsightCard({required this.insight});

  Color _categoryColor(InsightCategory cat) => switch (cat) {
        InsightCategory.calories    => AppColors.accent,
        InsightCategory.macros      => const Color(0xFF4ECDC4),
        InsightCategory.consistency => const Color(0xFFFFD166),
        InsightCategory.hydration   => const Color(0xFF64B5F6),
        InsightCategory.general     => AppColors.textSecondary,
      };

  IconData _categoryIcon(InsightCategory cat) => switch (cat) {
        InsightCategory.calories    => Icons.local_fire_department_rounded,
        InsightCategory.macros      => Icons.science_outlined,
        InsightCategory.consistency => Icons.calendar_today_rounded,
        InsightCategory.hydration   => Icons.water_drop_rounded,
        InsightCategory.general     => Icons.auto_awesome_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _categoryColor(insight.category);

    return GestureDetector(
      onTap: () {
        if (!insight.isRead) {
          HapticService.selection();
          ref
              .read(coachingControllerProvider.notifier)
              .markRead(insight.id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: insight.isRead
              ? AppColors.surface
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: insight.isRead
                ? AppColors.border
                : color.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_categoryIcon(insight.category),
                      color: color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    insight.category.label,
                    style: AppTextStyles.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!insight.isRead)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              insight.headline,
              style: AppTextStyles.labelLarge,
            ),
            const SizedBox(height: 6),
            Text(
              insight.body,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.insights_rounded,
                color: AppColors.textSecondary,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text('No insights yet', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Log meals for a full week and Tavera will analyse your patterns and generate personalised coaching.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                HapticService.heavy();
                ref.read(coachingControllerProvider.notifier).generate();
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Generate insights'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Paywall placeholder ──────────────────────────────────────────────────────

class _PaywallPlaceholder extends StatelessWidget {
  const _PaywallPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.accentMuted,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.accent,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text('Premium feature', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Upgrade to Tavera Premium to unlock weekly AI coaching insights — personalised analysis of your eating patterns with actionable advice.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                HapticService.heavy();
                showPaywallSheet(context);
              },
              child: const Text('Unlock AI Coaching'),
            ),
          ],
        ),
      ),
    );
  }
}
