import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../controllers/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../controllers/challenge_controller.dart';
import '../../controllers/coaching_controller.dart';
import '../../controllers/fasting_controller.dart';
import '../../controllers/known_meal_controller.dart';
import '../../models/fasting_session.dart';
import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/meal_log.dart';
import '../../services/haptic_service.dart';
import '../history/history_screen.dart';

// ─── Dashboard Screen ─────────────────────────────────────────────────────────
//
// The default home screen. Shows today's calorie progress ring, macro bars,
// stat cards, today's meal list, and water intake — all wired to live providers.

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(logControllerProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final water = ref.watch(waterMlProvider);

    // Phase 2 providers — all optional; empty/null = section hidden
    final activeFast = ref.watch(fastingControllerProvider).valueOrNull;
    final knownMeals = ref.watch(topKnownMealsProvider);
    final unreadInsights = ref.watch(unreadInsightCountProvider);
    // Watch the full async state so we can render a skeleton while loading
    // instead of silently hiding the card when auth hasn't resolved yet.
    final weeklyCaloriesAsync = ref.watch(weeklyCaloriesProvider);
    final activeChallenges = ref.watch(myChallengesProvider).valueOrNull
            ?.where((c) => c.isActive)
            .toList() ??
        [];
    // Phase 3 — streak (optional: hidden when 0)
    final streak = ref.watch(loggingStreakProvider).valueOrNull ?? 0;

    final log = logAsync.valueOrNull;
    final profile = profileAsync.valueOrNull;
    final calorieGoal = profile?.calorieGoal ?? 2000;
    final netCarbsMode = profile?.netCarbsMode ?? false;
    final displayCarbs = _netCarbs(log?.totalCarbs ?? 0, log?.totalFiber, netCarbsMode);
    final carbLabel = netCarbsMode ? 'Net Carbs' : 'Carbs';

    final name = profile?.name;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    // Avatar
                    _Avatar(avatarUrl: profile?.avatarUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            name != null && name.isNotEmpty ? name : 'Welcome back',
                            style: AppTextStyles.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Date pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        DateFormat('MMM d').format(DateTime.now()),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Calorie progress ring card ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _CalorieRingCard(
                  consumed: log?.totalCalories ?? 0,
                  goal: calorieGoal,
                  protein: log?.totalProtein ?? 0,
                  proteinGoal: _macroGoal(calorieGoal, 'protein'),
                  carbs: displayCarbs,
                  carbGoal: _macroGoal(calorieGoal, 'carbs'),
                  carbLabel: carbLabel,
                  fat: log?.totalFat ?? 0,
                  fatGoal: _macroGoal(calorieGoal, 'fat'),
                  netCarbsMode: netCarbsMode,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Stat chips row ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _StatChip(
                      icon: Icons.local_fire_department_rounded,
                      iconColor: const Color(0xFFFF6B35),
                      label: 'Calories',
                      value: '${log?.totalCalories ?? 0}',
                      unit: 'kcal',
                      sub: '/ $calorieGoal goal',
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.egg_alt_rounded,
                      iconColor: const Color(0xFF64B5F6),
                      label: 'Protein',
                      value: (log?.totalProtein ?? 0).toStringAsFixed(0),
                      unit: 'g',
                      sub: '/ ${_macroGoal(calorieGoal, 'protein').toStringAsFixed(0)}g goal',
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.grain_rounded,
                      iconColor: const Color(0xFFFFF176),
                      label: carbLabel,
                      value: displayCarbs.toStringAsFixed(0),
                      unit: 'g',
                      sub: '/ ${_macroGoal(calorieGoal, 'carbs').toStringAsFixed(0)}g goal',
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.water_drop_rounded,
                      iconColor: const Color(0xFFA5D6A7),
                      label: 'Fat',
                      value: (log?.totalFat ?? 0).toStringAsFixed(0),
                      unit: 'g',
                      sub: '/ ${_macroGoal(calorieGoal, 'fat').toStringAsFixed(0)}g goal',
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Weekly calorie trend ────────────────────────────────────────
            // Always render the card placeholder so users see immediate
            // feedback: skeleton while loading, chart once auth + data arrive.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: weeklyCaloriesAsync.when(
                  loading: () => const _WeeklyTrendSkeleton(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (weeklyCalories) => weeklyCalories.any((v) => v > 0)
                      ? _WeeklyTrendCard(
                          calories: weeklyCalories,
                          goal: calorieGoal,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Phase 3: Calorie Banking ────────────────────────────────────
            // Only shown when we have actual weekly data (any day logged).
            SliverToBoxAdapter(
              child: weeklyCaloriesAsync.maybeWhen(
                data: (weeklyCalories) {
                  if (!weeklyCalories.any((v) => v > 0)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: _CalorieBankCard(
                      weeklyCalories: weeklyCalories,
                      dailyGoal: calorieGoal,
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),

            // ── Phase 3: Consistency streak ─────────────────────────────────
            if (streak > 0) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StreakCard(streak: streak),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],

            // ── Water intake ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _WaterCard(waterMl: water, ref: ref),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Fasting card (shown when a fast is active) ──────────────────
            if (activeFast != null && activeFast.isActive) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _FastingCard(session: activeFast),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],

            // ── Phase 2: Known meals quick-tap row ──────────────────────────
            if (knownMeals.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Quick log', style: AppTextStyles.titleMedium),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: knownMeals.length,
                    itemBuilder: (context, i) {
                      final meal = knownMeals[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _KnownMealChip(meal: meal),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],

            // ── Phase 2: Coaching teaser ────────────────────────────────────
            if (unreadInsights > 0) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _CoachingTeaserCard(unreadCount: unreadInsights),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],

            // ── Phase 2: Meal planner teaser ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const _MealPlannerTeaserCard(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Phase 2: Active challenge strip ─────────────────────────────
            if (activeChallenges.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ChallengeStrip(challenges: activeChallenges),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],

            // ── Today's meals ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Today's Meals", style: AppTextStyles.titleMedium),
                    if ((log?.todayLogs ?? []).isNotEmpty)
                      Text(
                        '${log!.logCount} logged',
                        style: AppTextStyles.caption,
                      ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            logAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _MealListSkeleton(),
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              data: (data) {
                if (data.todayLogs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _EmptyMealsState(),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final meal = data.todayLogs[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: _MealRow(meal: meal),
                      );
                    },
                    childCount: data.todayLogs.length,
                  ),
                );
              },
            ),

            // Bottom padding for FAB / nav bar
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  /// Returns displayable carbs value: subtracts fiber when Net Carbs Mode is on.
  /// Falls back to [totalCarbs] when [totalFiber] is null (legacy logs).
  static double _netCarbs(double totalCarbs, double? totalFiber, bool netMode) {
    if (!netMode || totalFiber == null) return totalCarbs;
    return (totalCarbs - totalFiber).clamp(0.0, totalCarbs);
  }

  // Rough macro targets based on calorie goal (standard splits: 30% protein, 50% carbs, 20% fat)
  static double _macroGoal(int calories, String macro) {
    switch (macro) {
      case 'protein':
        return (calories * 0.30 / 4).roundToDouble(); // 4 kcal/g
      case 'carbs':
        return (calories * 0.50 / 4).roundToDouble(); // 4 kcal/g
      case 'fat':
        return (calories * 0.20 / 9).roundToDouble(); // 9 kcal/g
      default:
        return 0;
    }
  }
}

// ─── Weekly calorie trend ─────────────────────────────────────────────────────

/// Dark-themed bar chart showing calorie intake for the last 7 days.
/// Powered by fl_chart for smooth animations, touch tooltips, and a goal line.
class _WeeklyTrendCard extends StatelessWidget {
  final List<int> calories; // 7 values, oldest → newest
  final int goal;
  const _WeeklyTrendCard({required this.calories, required this.goal});

  @override
  Widget build(BuildContext context) {
    final dayLabels = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      return DateFormat('E').format(d)[0]; // M T W T F S S
    });

    final maxY = goal > 0 ? goal * 1.35 : 2600.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('7-day trend', style: AppTextStyles.labelLarge),
              Text(
                'Goal: $goal kcal',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: BarChart(
              BarChartData(
                backgroundColor: Colors.transparent,
                maxY: maxY,
                minY: 0,
                // Touch tooltip shows calorie value on tap
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.card,
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final kcal = calories[groupIndex];
                      if (kcal == 0) return null;
                      return BarTooltipItem(
                        '$kcal kcal',
                        AppTextStyles.caption.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= 7) return const SizedBox.shrink();
                        final isToday = i == 6;
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            dayLabels[i],
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10,
                              color: isToday
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                              fontWeight: isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                // Dashed horizontal goal line
                gridData: FlGridData(
                  show: goal > 0,
                  drawVerticalLine: false,
                  drawHorizontalLine: true,
                  horizontalInterval: goal.toDouble(),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.accent.withValues(alpha: 0.30),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(7, (i) {
                  final kcal = calories[i];
                  final isToday = i == 6;
                  final Color barColor = kcal == 0
                      ? AppColors.border
                      : kcal <= goal
                          ? AppColors.accent
                          : AppColors.danger;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: kcal.toDouble(),
                        color:
                            barColor.withValues(alpha: isToday ? 1.0 : 0.65),
                        width: 26,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                      ),
                    ],
                  );
                }),
              ),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Weekly trend skeleton ────────────────────────────────────────────────────

/// Placeholder rendered while weeklyCaloriesProvider is loading.
/// Matches the card's dimensions so the layout doesn't shift when data arrives.
class _WeeklyTrendSkeleton extends StatelessWidget {
  const _WeeklyTrendSkeleton();

  @override
  Widget build(BuildContext context) {
    const shimmer = AppColors.card;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row placeholders
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 82,
                height: 12,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                width: 64,
                height: 12,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Bar skeletons — varying heights to look natural
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [56.0, 72.0, 40.0, 80.0, 52.0, 88.0, 64.0]
                  .map((h) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: h * 0.78,
                                decoration: BoxDecoration(
                                  color: shimmer,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: shimmer,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Calorie Bank card ────────────────────────────────────────────────────────
//
// Shows weekly calorie budget vs. total consumed so users can see whether they
// have "calories banked" (surplus budget) or are over for the week.
//
// Budget  = dailyGoal × 7
// Spent   = sum of weeklyCalories (7 values, oldest → newest)
// Banked  = Budget − Spent  (positive = under budget, negative = over)
//
// The progress bar fills from left to right as calories are consumed.
// It turns red only when the user has exceeded 100 % of the weekly budget.

class _CalorieBankCard extends StatelessWidget {
  final List<int> weeklyCalories; // 7 values
  final int dailyGoal;

  const _CalorieBankCard({
    required this.weeklyCalories,
    required this.dailyGoal,
  });

  @override
  Widget build(BuildContext context) {
    final budget = dailyGoal * 7;
    final spent = weeklyCalories.fold<int>(0, (s, v) => s + v);
    final banked = budget - spent;
    final ratio = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    final isOver = spent > budget;
    final barColor = isOver ? AppColors.danger : AppColors.accent;
    final bankedLabel = isOver
        ? '${(-banked).toString()} kcal over'
        : '${banked.toString()} kcal banked';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weekly budget', style: AppTextStyles.labelLarge),
              Text(
                bankedLabel,
                style: AppTextStyles.caption.copyWith(
                  color: isOver ? AppColors.danger : AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.card,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$spent kcal consumed',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '$budget kcal budget',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  const _Avatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: avatarUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
              ),
            )
          : const Icon(Icons.person_rounded,
              color: AppColors.textSecondary, size: 22),
    );
  }
}

// ─── Calorie ring card ────────────────────────────────────────────────────────

class _CalorieRingCard extends StatelessWidget {
  final int consumed;
  final int goal;
  final double protein;
  final double proteinGoal;
  final double carbs;
  final double carbGoal;
  final String carbLabel;
  final double fat;
  final double fatGoal;
  final bool netCarbsMode;

  const _CalorieRingCard({
    required this.consumed,
    required this.goal,
    required this.protein,
    required this.proteinGoal,
    required this.carbs,
    required this.carbGoal,
    this.carbLabel = 'Carbs',
    required this.fat,
    required this.fatGoal,
    this.netCarbsMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (goal - consumed).clamp(0, goal);
    final progress = goal > 0 ? (consumed / goal).clamp(0.0, 1.0) : 0.0;

    // Ring arc colour: green when on track, amber when close, red when over
    final Color ringColor = consumed > goal
        ? AppColors.danger
        : progress > 0.85
            ? const Color(0xFFFFB74D)
            : AppColors.accent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Calorie ring
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(130, 130),
                  painter: _RingPainter(
                    progress: progress,
                    ringColor: ringColor,
                    trackColor: AppColors.card,
                    strokeWidth: 10,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$consumed',
                      style: AppTextStyles.calorieDisplay.copyWith(
                        fontSize: 28,
                        letterSpacing: -1.2,
                        color: ringColor,
                      ),
                    ),
                    Text(
                      'kcal',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$remaining left',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Macro bars
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MacroBar(
                  label: carbLabel,
                  value: carbs,
                  goal: carbGoal,
                  color: const Color(0xFFFFF176),
                ),
                const SizedBox(height: 14),
                _MacroBar(
                  label: 'Protein',
                  value: protein,
                  goal: proteinGoal,
                  color: const Color(0xFF64B5F6),
                ),
                const SizedBox(height: 14),
                _MacroBar(
                  label: 'Fat',
                  value: fat,
                  goal: fatGoal,
                  color: const Color(0xFFA5D6A7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Ring painter (reused from camera screen pattern, self-contained here)
class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    const startAngle = -math.pi / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.ringColor != ringColor;
}

// ─── Macro bar ────────────────────────────────────────────────────────────────

class _MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final double goal;
  final Color color;

  const _MacroBar({
    required this.label,
    required this.value,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.caption),
            Text(
              '${value.toStringAsFixed(0)}/${goal.toStringAsFixed(0)}g',
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppColors.card,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ─── Stat chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;
  final String sub;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.caption),
            ],
          ),
          const Spacer(),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontSize: 24,
                    letterSpacing: -1.0,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(sub, style: AppTextStyles.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── Water card ───────────────────────────────────────────────────────────────

class _WaterCard extends StatelessWidget {
  final int waterMl;
  final WidgetRef ref;

  const _WaterCard({required this.waterMl, required this.ref});

  @override
  Widget build(BuildContext context) {
    const goalMl = AppConfig.defaultWaterGoalMl;
    final progress = (waterMl / goalMl).clamp(0.0, 1.0);
    final glasses = (waterMl / 250).round();
    const goalGlasses = goalMl ~/ 250;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_drop_rounded,
              color: Color(0xFF64B5F6), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Water', style: AppTextStyles.labelLarge),
                    Text(
                      '$glasses / $goalGlasses glasses',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: AppColors.card,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF64B5F6)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${waterMl}ml of ${goalMl}ml',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Quick add button
          GestureDetector(
            onTap: () {
              HapticService.selection();
              ref.read(waterMlProvider.notifier).add();
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF64B5F6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_rounded,
                  color: Color(0xFF64B5F6), size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Meal row ─────────────────────────────────────────────────────────────────

class _MealRow extends ConsumerWidget {
  final MealLog meal;
  const _MealRow({required this.meal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = meal.items.map((i) => i.name).take(3).join(', ');
    final timeStr = _formatTime(meal.loggedAt);
    final calorieGoal =
        ref.watch(userProfileProvider).valueOrNull?.calorieGoal ?? 2000;
    final score = meal.score(calorieGoal: calorieGoal);
    final scoreColor = switch (score) {
      MealScore.green => AppColors.success,
      MealScore.yellow => const Color(0xFFFFD166),
      MealScore.red => AppColors.danger,
    };

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => MealDetailSheet(log: meal),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Meal score dot
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: scoreColor,
                shape: BoxShape.circle,
              ),
            ),
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: meal.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: meal.imageUrl!,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 52,
                        height: 52,
                        color: AppColors.card,
                      ),
                      errorWidget: (_, __, ___) => _MealIconBox(),
                    )
                  : _MealIconBox(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    names.isNotEmpty ? names : 'Meal',
                    style: AppTextStyles.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(timeStr, style: AppTextStyles.caption),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${meal.totalCalories}',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.accent,
                  ),
                ),
                Text('kcal', style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return DateFormat('h:mm a').format(local);
  }
}

class _MealIconBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.restaurant_rounded,
          color: AppColors.textTertiary, size: 22),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyMealsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.restaurant_menu_rounded,
            color: AppColors.textTertiary,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            'No meals logged yet',
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the + button to log your first meal',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Phase 2: Known meal chip ─────────────────────────────────────────────────

class _KnownMealChip extends ConsumerWidget {
  final dynamic meal; // KnownMeal
  const _KnownMealChip({required this.meal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        HapticService.heavy();
        final logId = await ref
            .read(knownMealControllerProvider.notifier)
            .relog(meal, ref);
        if (logId != null) {
          ref.invalidate(logControllerProvider);
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not log meal. Check your connection and try again.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      onLongPress: () {
        HapticService.medium();
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _KnownMealActionSheet(meal: meal, ref: ref),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, color: AppColors.accent, size: 14),
            const SizedBox(width: 6),
            Text(
              meal.name as String,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 6),
            Text(
              '${meal.totalCalories} kcal',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Known meal action sheet ──────────────────────────────────────────────────

class _KnownMealActionSheet extends StatelessWidget {
  final dynamic meal; // KnownMeal
  final WidgetRef ref;
  const _KnownMealActionSheet({required this.meal, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(meal.name as String, style: AppTextStyles.titleMedium),
          Text(
            '${meal.totalCalories} kcal · logged ${meal.occurrenceCount}×',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined,
                color: AppColors.textSecondary),
            title: Text('Rename', style: AppTextStyles.bodyLarge),
            onTap: () async {
              HapticService.selection();
              Navigator.of(context).pop();
              final ctrl = TextEditingController(text: meal.name as String);
              String? newName;
              try {
                newName = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: Text('Rename meal',
                        style: AppTextStyles.titleMedium),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: AppTextStyles.bodyLarge,
                      decoration: const InputDecoration(hintText: 'Meal name'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(ctrl.text),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
              } finally {
                ctrl.dispose();
              }
              if (newName != null && newName.trim().isNotEmpty) {
                try {
                  await ref
                      .read(knownMealControllerProvider.notifier)
                      .rename(meal.id as String, newName);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to rename meal. Please try again.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger),
            title: Text(
              'Remove from quick log',
              style:
                  AppTextStyles.bodyLarge.copyWith(color: AppColors.danger),
            ),
            onTap: () async {
              HapticService.medium();
              Navigator.of(context).pop();
              try {
                await ref
                    .read(knownMealControllerProvider.notifier)
                    .delete(meal.id as String);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to remove meal. Please try again.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.close_rounded,
                color: AppColors.textSecondary),
            title:
                Text('Cancel', style: AppTextStyles.bodyLarge),
            onTap: () {
              HapticService.selection();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

// ─── Phase 2: Coaching teaser card ───────────────────────────────────────────

class _CoachingTeaserCard extends StatelessWidget {
  final int unreadCount;
  const _CoachingTeaserCard({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        context.push('/coaching');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.15),
              AppColors.accent.withValues(alpha: 0.05),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.insights_rounded,
                color: AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Your weekly insights are ready',
                        style: AppTextStyles.labelLarge,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tap to see your AI coaching review',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Phase 2: Meal planner teaser card ───────────────────────────────────────

class _MealPlannerTeaserCard extends ConsumerWidget {
  const _MealPlannerTeaserCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        context.push('/meal-planner');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.restaurant_menu_rounded,
                  color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meal Planner',
                      style: AppTextStyles.labelLarge),
                  SizedBox(height: 3),
                  Text(
                    'View your AI-generated plan for the week',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Phase 2: Active challenge strip ─────────────────────────────────────────

class _ChallengeStrip extends StatelessWidget {
  final List<dynamic> challenges; // List<Challenge>
  const _ChallengeStrip({required this.challenges});

  @override
  Widget build(BuildContext context) {
    final challenge = challenges.first;
    final daysLeft = challenge.daysRemaining as int;
    // Find the user's position in the leaderboard.
    final participantCount = (challenge.participants as List<dynamic>).length;

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        context.push('/challenges/${challenge.id as String}');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(
              (challenge.type as dynamic).icon as String,
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challenge.title as String,
                    style: AppTextStyles.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$daysLeft day${daysLeft == 1 ? '' : 's'} left · $participantCount participant${participantCount == 1 ? '' : 's'}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Fasting card ─────────────────────────────────────────────────────────────
//
// Shows when an IF fast is active. Taps through to the full FastingScreen.
// The StatefulWidget owns a Timer so the progress bar and label tick live
// without rebuilding the whole dashboard provider tree.

class _FastingCard extends StatefulWidget {
  final FastingSession session;
  const _FastingCard({required this.session});

  @override
  State<_FastingCard> createState() => _FastingCardState();
}

class _FastingCardState extends State<_FastingCard> {
  late Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final progress = s.progress;
    final remaining = s.remaining;
    final goalReached = s.isGoalReached;

    final hh = remaining.inHours.toString().padLeft(2, '0');
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = goalReached ? 'Goal reached!' : '$hh:$mm:$ss left';

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        context.push('/fasting');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: goalReached
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.accent.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: goalReached
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.accentMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                goalReached
                    ? Icons.check_circle_outline_rounded
                    : Icons.timer_outlined,
                color: goalReached ? AppColors.success : AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            // Text + progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${s.protocol.label} Fast',
                        style: AppTextStyles.labelLarge,
                      ),
                      Text(
                        timeStr,
                        style: AppTextStyles.caption.copyWith(
                          color: goalReached
                              ? AppColors.success
                              : AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        goalReached ? AppColors.success : AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}% complete · tap to manage',
                    style: AppTextStyles.caption.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Loading skeleton ─────────────────────────────────────────────────────────

class _MealListSkeleton extends StatelessWidget {
  const _MealListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ─── Streak card (Phase 3) ────────────────────────────────────────────────────
//
// Shown on the Dashboard when the user has a logging streak >= 1 day.
// Tapping opens the WeeklySummaryScreen for the full 7-day breakdown.

class _StreakCard extends StatelessWidget {
  final int streak;
  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    final label = streak == 1 ? '1-day streak' : '$streak-day streak';
    final subLabel = streak < 3
        ? 'Log today to keep it going'
        : streak < 7
            ? 'Great consistency!'
            : '$streak days — incredible!';

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        context.push('/weekly-summary');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.accent)),
                  Text(subLabel, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.accent, size: 20),
          ],
        ),
      ),
    );
  }
}
