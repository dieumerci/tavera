import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/meal_log.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logState = ref.watch(logControllerProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          DateFormat('EEEE').format(DateTime.now()),
          style: AppTextStyles.titleMedium,
        ),
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: logState.when(
        data: (state) => state.todayLogs.isEmpty
            ? const _EmptyState()
            : _LogBody(state: state, calorieGoal: profile?.calorieGoal ?? 2000),
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
          child: Text(e.toString(), style: AppTextStyles.bodyMedium),
        ),
      ),
    );
  }
}

// ─── Main body ─────────────────────────────────────────────────────────────────

class _LogBody extends StatelessWidget {
  final DailyLogState state;
  final int calorieGoal;

  const _LogBody({required this.state, required this.calorieGoal});

  @override
  Widget build(BuildContext context) {
    final progress = (state.totalCalories / calorieGoal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // Daily summary card
        _SummaryCard(
          totalCalories: state.totalCalories,
          calorieGoal: calorieGoal,
          logCount: state.logCount,
          progress: progress,
        ),

        const SizedBox(height: 20),

        Text(
          'Meals',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),

        // Meal cards
        ...state.todayLogs.map((log) => _MealCard(log: log)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int totalCalories;
  final int calorieGoal;
  final int logCount;
  final double progress;

  const _SummaryCard({
    required this.totalCalories,
    required this.calorieGoal,
    required this.logCount,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$totalCalories',
                style: AppTextStyles.calorieDisplay,
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ $calorieGoal kcal',
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0 ? AppColors.danger : AppColors.accent,
              ),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              _Stat(
                label: 'Meals logged',
                value: '$logCount',
              ),
              const SizedBox(width: 24),
              _Stat(
                label: 'Remaining',
                value: '${(calorieGoal - totalCalories).clamp(0, calorieGoal)} kcal',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.labelLarge),
      ],
    );
  }
}

// ─── Meal card ─────────────────────────────────────────────────────────────────

class _MealCard extends StatelessWidget {
  final MealLog log;
  const _MealCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat.jm().format(log.loggedAt);
    final itemNames = log.items.map((i) => i.name).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Meal thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: log.imageUrl != null
                ? Image.network(
                    log.imageUrl!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _ThumbnailPlaceholder(),
                  )
                : _ThumbnailPlaceholder(),
          ),

          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemNames.isEmpty ? 'Meal' : itemNames,
                  style: AppTextStyles.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(timeLabel, style: AppTextStyles.caption),
              ],
            ),
          ),

          // Calorie count
          Text(
            '${log.totalCalories}',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 2),
          Text('kcal', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.restaurant_outlined,
        color: AppColors.textSecondary,
        size: 22,
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
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
              Icons.camera_alt_outlined,
              color: AppColors.textSecondary,
              size: 36,
            ),
          ),
          const SizedBox(height: 20),
          Text('Nothing logged yet', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Capture your first meal to start tracking',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }
}
