import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/meal_log.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  // Normalised to midnight so it matches the _dayRange() key exactly.
  late DateTime _selectedDate;
  final _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(_today.year, _today.month, _today.day);
  }

  bool get _isToday =>
      _selectedDate.year == _today.year &&
      _selectedDate.month == _today.month &&
      _selectedDate.day == _today.day;

  void _prevDay() => setState(() =>
      _selectedDate = _selectedDate.subtract(const Duration(days: 1)));

  void _nextDay() {
    if (_isToday) return;
    setState(
        () => _selectedDate = _selectedDate.add(const Duration(days: 1)));
  }

  String _formatDate(DateTime d) {
    if (_isToday) return 'Today';
    final yesterday = DateTime(_today.year, _today.month, _today.day - 1);
    if (d == yesterday) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(historyLogsProvider(_selectedDate));
    final profile   = ref.watch(userProfileProvider).valueOrNull;
    final goal      = profile?.calorieGoal ?? 2000;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // Date navigation
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 24),
              onPressed: _prevDay,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2024),
                  lastDate: _today,
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.dark(
                        primary: AppColors.accent,
                        surface: AppColors.surface,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _selectedDate =
                      DateTime(picked.year, picked.month, picked.day));
                }
              },
              child: Text(_formatDate(_selectedDate),
                  style: AppTextStyles.titleMedium),
            ),
            IconButton(
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: _isToday
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
              ),
              onPressed: _isToday ? null : _nextDay,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: logsAsync.when(
        data: (logs) => logs.isEmpty
            ? const _EmptyState()
            : _LogBody(
                logs: logs,
                calorieGoal: goal,
                selectedDate: _selectedDate,
              ),
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) =>
            Center(child: Text(e.toString(), style: AppTextStyles.bodyMedium)),
      ),
    );
  }
}

// ─── Body ───────────────────────────────────────────────────────────────────

class _LogBody extends ConsumerWidget {
  final List<MealLog> logs;
  final int calorieGoal;
  final DateTime selectedDate;

  const _LogBody({
    required this.logs,
    required this.calorieGoal,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCalories =
        logs.fold(0, (s, l) => s + l.totalCalories);
    final totalProtein =
        logs.fold(0.0, (s, l) => s + (l.totalProtein ?? 0));
    final totalCarbs =
        logs.fold(0.0, (s, l) => s + (l.totalCarbs ?? 0));
    final totalFat =
        logs.fold(0.0, (s, l) => s + (l.totalFat ?? 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        _SummaryCard(
          totalCalories: totalCalories,
          calorieGoal: calorieGoal,
          logCount: logs.length,
          totalProtein: totalProtein,
          totalCarbs: totalCarbs,
          totalFat: totalFat,
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

        ...logs.map(
          (log) => _MealCard(
            log: log,
            selectedDate: selectedDate,
          ),
        ),
      ],
    );
  }
}

// ─── Summary card with macros ────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final int totalCalories;
  final int calorieGoal;
  final int logCount;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;

  const _SummaryCard({
    required this.totalCalories,
    required this.calorieGoal,
    required this.logCount,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (totalCalories / calorieGoal).clamp(0.0, 1.0);
    final remaining = (calorieGoal - totalCalories).clamp(0, calorieGoal);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calorie headline
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$totalCalories', style: AppTextStyles.calorieDisplay),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('/ $calorieGoal kcal',
                    style: AppTextStyles.bodyMedium),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: remaining == 0
                      ? AppColors.danger.withValues(alpha: 0.12)
                      : AppColors.accentMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  remaining == 0
                      ? 'Goal reached'
                      : '$remaining left',
                  style: AppTextStyles.caption.copyWith(
                    color: remaining == 0
                        ? AppColors.danger
                        : AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Calorie progress bar
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

          const SizedBox(height: 16),

          // Macro breakdown bars
          if (totalProtein > 0 || totalCarbs > 0 || totalFat > 0) ...[
            Row(
              children: [
                Expanded(
                  child: _MacroBar(
                    label: 'Protein',
                    value: totalProtein,
                    color: const Color(0xFF4ECDC4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MacroBar(
                    label: 'Carbs',
                    value: totalCarbs,
                    color: const Color(0xFFFFD166),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MacroBar(
                    label: 'Fat',
                    value: totalFat,
                    color: const Color(0xFFFF6B6B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          Row(
            children: [
              _Stat(label: 'Meals', value: '$logCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroBar(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.caption),
            Text(
              '${value.toStringAsFixed(1)}g',
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            // Rough daily targets: protein 150g, carbs 250g, fat 65g
            value: (value /
                    (label == 'Protein'
                        ? 150
                        : label == 'Carbs'
                            ? 250
                            : 65))
                .clamp(0.0, 1.0),
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
      ],
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

// ─── Meal card with swipe-to-delete ─────────────────────────────────────────

class _MealCard extends ConsumerWidget {
  final MealLog log;
  final DateTime selectedDate;
  const _MealCard({required this.log, required this.selectedDate});

  Future<bool> _confirmDelete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Delete meal?', style: AppTextStyles.titleMedium),
            content: Text(
              'This can\'t be undone.',
              style: AppTextStyles.bodyMedium,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Delete',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeLabel = DateFormat.jm().format(log.loggedAt);
    final itemNames = log.items.map((i) => i.name).join(', ');

    return Dismissible(
      key: ValueKey(log.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => deleteMealLog(ref, log.id, log.loggedAt),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppColors.danger, size: 22),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: log.imageUrl != null
                  ? Image.network(
                      log.imageUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _ThumbnailPlaceholder(),
                    )
                  : const _ThumbnailPlaceholder(),
            ),

            const SizedBox(width: 14),

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

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${log.totalCalories}',
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.accent),
                ),
                Text('kcal', style: AppTextStyles.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.restaurant_outlined,
          color: AppColors.textSecondary, size: 22),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

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
            child: const Icon(Icons.camera_alt_outlined,
                color: AppColors.textSecondary, size: 36),
          ),
          const SizedBox(height: 20),
          Text('Nothing logged', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Capture a meal to start tracking',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }
}
