import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

// ─── WeeklySummaryScreen ──────────────────────────────────────────────────────
//
// Full-screen weekly retrospective — 7-day calorie bars, macro averages,
// streak highlight, best/worst day. All data comes from existing providers;
// no new network calls.

class WeeklySummaryScreen extends ConsumerWidget {
  const WeeklySummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekAsync = ref.watch(weeklyFullStatsProvider);
    final streakAsync = ref.watch(loggingStreakProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final goal = profile?.calorieGoal ?? 2000;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Weekly Summary', style: AppTextStyles.titleMedium),
        centerTitle: true,
      ),
      body: weekAsync.when(
        data: (days) => _SummaryBody(
          days: days,
          calorieGoal: goal,
          streak: streakAsync.valueOrNull ?? 0,
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) =>
            Center(child: Text(e.toString(), style: AppTextStyles.bodyMedium)),
      ),
    );
  }
}

// ─── Body ────────────────────────────────────────────────────────────────────

class _SummaryBody extends StatelessWidget {
  final List<DayStats> days;
  final int calorieGoal;
  final int streak;

  const _SummaryBody({
    required this.days,
    required this.calorieGoal,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final activeDays = days.where((d) => d.calories > 0).toList();
    final totalCalories = activeDays.fold(0, (s, d) => s + d.calories);
    final avgCalories =
        activeDays.isEmpty ? 0 : (totalCalories / activeDays.length).round();
    final avgProtein = activeDays.isEmpty
        ? 0.0
        : activeDays.fold(0.0, (s, d) => s + d.protein) / activeDays.length;
    final avgCarbs = activeDays.isEmpty
        ? 0.0
        : activeDays.fold(0.0, (s, d) => s + d.carbs) / activeDays.length;
    final avgFat = activeDays.isEmpty
        ? 0.0
        : activeDays.fold(0.0, (s, d) => s + d.fat) / activeDays.length;

    // Best day = closest to goal without exceeding it. Fallback: highest.
    DayStats? bestDay;
    DayStats? worstDay;
    if (activeDays.isNotEmpty) {
      bestDay = activeDays.reduce((a, b) {
        final da = (a.calories - calorieGoal).abs();
        final db = (b.calories - calorieGoal).abs();
        return da <= db ? a : b;
      });
      worstDay = activeDays.reduce(
          (a, b) => a.calories > b.calories ? a : b);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // ── Streak banner ──────────────────────────────────────────────────
        if (streak > 0) ...[
          _StreakBanner(streak: streak),
          const SizedBox(height: 16),
        ],

        // ── Calorie bar chart ──────────────────────────────────────────────
        _SectionHeader('Calories this week'),
        const SizedBox(height: 12),
        _CalorieBars(days: days, calorieGoal: calorieGoal),
        const SizedBox(height: 20),

        // ── Summary stats ──────────────────────────────────────────────────
        _SectionHeader('Averages (${activeDays.length}/7 days logged)'),
        const SizedBox(height: 12),
        _StatsGrid(
          avgCalories: avgCalories,
          avgProtein: avgProtein,
          avgCarbs: avgCarbs,
          avgFat: avgFat,
          calorieGoal: calorieGoal,
        ),
        const SizedBox(height: 20),

        // ── Best / worst day ───────────────────────────────────────────────
        if (bestDay != null && worstDay != null && bestDay != worstDay) ...[
          _SectionHeader('Highlights'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HighlightCard(
                  label: 'Best day',
                  dayLabel: DateFormat('EEE d').format(bestDay.date),
                  calories: bestDay.calories,
                  goal: calorieGoal,
                  positive: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HighlightCard(
                  label: 'Heaviest day',
                  dayLabel: DateFormat('EEE d').format(worstDay.date),
                  calories: worstDay.calories,
                  goal: calorieGoal,
                  positive: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        // ── Macro breakdown ────────────────────────────────────────────────
        if (activeDays.isNotEmpty) ...[
          _SectionHeader('Average macro split'),
          const SizedBox(height: 12),
          _MacroPie(
            protein: avgProtein,
            carbs: avgCarbs,
            fat: avgFat,
          ),
        ],
      ],
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ─── Streak banner ────────────────────────────────────────────────────────────

class _StreakBanner extends StatelessWidget {
  final int streak;
  const _StreakBanner({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Text('🔥', style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$streak-day streak',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.accent),
              ),
              Text(
                streak == 1
                    ? 'Great start — keep it going!'
                    : 'Logging every day. Keep it up!',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Calorie bar chart ────────────────────────────────────────────────────────

class _CalorieBars extends StatelessWidget {
  final List<DayStats> days;
  final int calorieGoal;

  const _CalorieBars({required this.days, required this.calorieGoal});

  @override
  Widget build(BuildContext context) {
    final maxCal =
        days.fold(0, (m, d) => math.max(m, d.calories));
    // Chart ceiling = max of (goal * 1.3) and the actual max, for headroom.
    final ceiling = math.max((calorieGoal * 1.3).round(), maxCal + 100);

    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month}-${today.day}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Goal line label
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 16,
                height: 2,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text('Goal $calorieGoal kcal', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: days.map((day) {
                final isToday =
                    '${day.date.year}-${day.date.month}-${day.date.day}' ==
                        todayKey;
                final ratio =
                    ceiling > 0 ? day.calories / ceiling : 0.0;
                final goalRatio = ceiling > 0 ? calorieGoal / ceiling : 0.0;

                Color barColor;
                if (day.calories == 0) {
                  barColor = AppColors.border;
                } else if (day.calories > calorieGoal) {
                  barColor = AppColors.danger;
                } else if (day.calories >= calorieGoal * 0.8) {
                  barColor = AppColors.accent;
                } else {
                  barColor = AppColors.accent.withValues(alpha: 0.55);
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Calorie label above bar
                        if (day.calories > 0)
                          Text(
                            day.calories >= 1000
                                ? '${(day.calories / 1000).toStringAsFixed(1)}k'
                                : '${day.calories}',
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 9,
                              color: isToday
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Bar with goal-line overlay
                        Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // Full-height guide (empty space)
                            SizedBox(
                              height: 110,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 500),
                                    curve: Curves.easeOut,
                                    height: (ratio * 110).clamp(2.0, 110.0),
                                    color: barColor,
                                  ),
                                ),
                              ),
                            ),
                            // Goal line
                            Positioned(
                              bottom: (goalRatio * 110).clamp(0.0, 110.0),
                              left: 0,
                              right: 0,
                              child: Container(
                                  height: 1.5,
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('E').format(day.date)[0],
                          style: AppTextStyles.caption.copyWith(
                            color: isToday
                                ? AppColors.accent
                                : AppColors.textSecondary,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats grid ───────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final int avgCalories;
  final double avgProtein;
  final double avgCarbs;
  final double avgFat;
  final int calorieGoal;

  const _StatsGrid({
    required this.avgCalories,
    required this.avgProtein,
    required this.avgCarbs,
    required this.avgFat,
    required this.calorieGoal,
  });

  @override
  Widget build(BuildContext context) {
    final calorieColor = avgCalories > calorieGoal
        ? AppColors.danger
        : avgCalories >= calorieGoal * 0.8
            ? AppColors.accent
            : AppColors.textSecondary;

    return Column(
      children: [
        // Calories
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Avg. daily calories', style: AppTextStyles.bodyMedium),
              RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: '$avgCalories',
                    style: AppTextStyles.titleMedium.copyWith(color: calorieColor),
                  ),
                  TextSpan(
                    text: ' / $calorieGoal kcal',
                    style: AppTextStyles.caption,
                  ),
                ]),
              ),
            ],
          ),
        ),
        // Macros row
        Row(
          children: [
            Expanded(
                child: _MacroAvgChip(
                    label: 'Protein',
                    value: avgProtein,
                    color: const Color(0xFF4ECDC4))),
            const SizedBox(width: 10),
            Expanded(
                child: _MacroAvgChip(
                    label: 'Carbs',
                    value: avgCarbs,
                    color: const Color(0xFFFFD166))),
            const SizedBox(width: 10),
            Expanded(
                child: _MacroAvgChip(
                    label: 'Fat',
                    value: avgFat,
                    color: const Color(0xFFFF6B6B))),
          ],
        ),
      ],
    );
  }
}

class _MacroAvgChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroAvgChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            '${value.toStringAsFixed(0)}g',
            style: AppTextStyles.labelLarge.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

// ─── Highlight cards ──────────────────────────────────────────────────────────

class _HighlightCard extends StatelessWidget {
  final String label;
  final String dayLabel;
  final int calories;
  final int goal;
  final bool positive;

  const _HighlightCard({
    required this.label,
    required this.dayLabel,
    required this.calories,
    required this.goal,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(dayLabel,
              style: AppTextStyles.labelLarge.copyWith(color: color)),
          const SizedBox(height: 4),
          Text('$calories kcal', style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}

// ─── Macro pie (simple visual) ────────────────────────────────────────────────

class _MacroPie extends StatelessWidget {
  final double protein;
  final double carbs;
  final double fat;

  const _MacroPie(
      {required this.protein, required this.carbs, required this.fat});

  @override
  Widget build(BuildContext context) {
    final proteinKcal = protein * 4;
    final carbKcal = carbs * 4;
    final fatKcal = fat * 9;
    final total = proteinKcal + carbKcal + fatKcal;

    if (total <= 0) return const SizedBox.shrink();

    final pPct = (proteinKcal / total * 100).round();
    final cPct = (carbKcal / total * 100).round();
    final fPct = (fatKcal / total * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Simple horizontal stacked bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 20,
                child: Row(
                  children: [
                    _BarSegment(
                        fraction: proteinKcal / total,
                        color: const Color(0xFF4ECDC4)),
                    _BarSegment(
                        fraction: carbKcal / total,
                        color: const Color(0xFFFFD166)),
                    _BarSegment(
                        fraction: fatKcal / total,
                        color: const Color(0xFFFF6B6B)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Legend
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendDot(
                  color: const Color(0xFF4ECDC4),
                  label: 'Protein $pPct%'),
              _LegendDot(
                  color: const Color(0xFFFFD166), label: 'Carbs $cPct%'),
              _LegendDot(color: const Color(0xFFFF6B6B), label: 'Fat $fPct%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarSegment extends StatelessWidget {
  final double fraction;
  final Color color;
  const _BarSegment({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) =>
      Expanded(flex: (fraction * 100).round(), child: Container(color: color));
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
