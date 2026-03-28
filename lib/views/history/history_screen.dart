import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/log_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/food_item.dart';
import '../../models/meal_log.dart';
import '../../services/haptic_service.dart';
import '../../widgets/sheet_handle.dart';

/// Returns displayable carbs: subtracts fiber when Net Carbs Mode is on.
/// Falls back gracefully to [totalCarbs] when [totalFiber] is null.
double _netCarbs(double totalCarbs, double? totalFiber, bool netMode) {
  if (!netMode || totalFiber == null) return totalCarbs;
  return (totalCarbs - totalFiber).clamp(0.0, totalCarbs);
}

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

  void _prevDay() {
    HapticService.selection();
    setState(() =>
        _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
  }

  void _nextDay() {
    if (_isToday) return;
    HapticService.selection();
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
        automaticallyImplyLeading: false,
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
    final rawCarbs =
        logs.fold(0.0, (s, l) => s + (l.totalCarbs ?? 0));
    final totalFiber =
        logs.fold(0.0, (s, l) => s + (l.totalFiber ?? 0));
    final totalFat =
        logs.fold(0.0, (s, l) => s + (l.totalFat ?? 0));

    final netCarbsMode =
        ref.watch(userProfileProvider).valueOrNull?.netCarbsMode ?? false;
    final totalCarbs = _netCarbs(rawCarbs, totalFiber, netCarbsMode);
    final carbLabel = netCarbsMode ? 'Net Carbs' : 'Carbs';

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
          carbLabel: carbLabel,
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
  final String carbLabel;

  const _SummaryCard({
    required this.totalCalories,
    required this.calorieGoal,
    required this.logCount,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    this.carbLabel = 'Carbs',
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
                    label: carbLabel,
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
                        : label.contains('Carb')
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
    HapticService.medium();
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

  void _openDetail(BuildContext context) {
    HapticService.selection();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MealDetailSheet(log: log, selectedDate: selectedDate),
    );
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
      child: GestureDetector(
        onTap: () => _openDetail(context),
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
      ),
    );
  }
}

// ─── Meal detail sheet ────────────────────────────────────────────────────────

// Public so it can be opened from the Dashboard and other screens.
class MealDetailSheet extends ConsumerWidget {
  final MealLog log;
  // Used to invalidate the correct historyLogsProvider cache on deletion.
  // Defaults to the meal's own logged date when not specified.
  final DateTime? selectedDate;
  const MealDetailSheet({super.key, required this.log, this.selectedDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeLabel = DateFormat('EEE, MMM d · h:mm a').format(log.loggedAt);
    final netCarbsMode =
        ref.watch(userProfileProvider).valueOrNull?.netCarbsMode ?? false;
    final displayCarbs = _netCarbs(
      log.totalCarbs ?? 0,
      log.totalFiber,
      netCarbsMode,
    );
    final carbLabel = netCarbsMode ? 'Net Carbs' : 'Carbs';

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.72, 0.95],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 4),
                child: SheetHandle(),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    // Meal photo
                    if (log.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Image.network(
                            log.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(
                                  color: AppColors.card,
                                  child: const Icon(
                                    Icons.restaurant_outlined,
                                    color: AppColors.textSecondary,
                                    size: 40,
                                  ),
                                ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Timestamp + calorie headline
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(timeLabel, style: AppTextStyles.caption),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${log.totalCalories}',
                                style: AppTextStyles.titleMedium
                                    .copyWith(color: AppColors.accent),
                              ),
                              TextSpan(
                                text: ' kcal',
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Macro chips
                    if (log.totalProtein != null ||
                        log.totalCarbs != null ||
                        log.totalFat != null)
                      Row(
                        children: [
                          if (log.totalProtein != null)
                            _MacroChip(
                              label: 'Protein',
                              value: log.totalProtein!,
                              color: const Color(0xFF4ECDC4),
                            ),
                          if (log.totalCarbs != null) ...[
                            const SizedBox(width: 8),
                            _MacroChip(
                              label: carbLabel,
                              value: displayCarbs,
                              color: const Color(0xFFFFD166),
                            ),
                          ],
                          if (log.totalFat != null) ...[
                            const SizedBox(width: 8),
                            _MacroChip(
                              label: 'Fat',
                              value: log.totalFat!,
                              color: const Color(0xFFFF6B6B),
                            ),
                          ],
                        ],
                      ),

                    const SizedBox(height: 20),

                    Text('Items', style: AppTextStyles.titleMedium),
                    const SizedBox(height: 10),

                    // Food item rows
                    ...log.items.map((item) => _DetailItemRow(item: item)),

                    const SizedBox(height: 24),

                    // Delete button
                    OutlinedButton.icon(
                      onPressed: () async {
                        HapticService.medium();
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            title: Text('Delete meal?',
                                style: AppTextStyles.titleMedium),
                            content: Text('This can\'t be undone.',
                                style: AppTextStyles.bodyMedium),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(true),
                                child: Text('Delete',
                                    style: TextStyle(
                                        color: AppColors.danger)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && context.mounted) {
                          Navigator.of(context).pop(); // close sheet
                          await deleteMealLog(
                              ref, log.id, selectedDate ?? log.loggedAt);
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppColors.danger),
                      label: Text(
                        'Delete meal',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.danger),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.danger.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}g $label',
        style: AppTextStyles.caption
            .copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DetailItemRow extends StatelessWidget {
  final FoodItem item;
  const _DetailItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    // Confidence → dot colour (amber as inline constant — AppColors has no warning)
    final dotColor = item.confidenceScore >= 0.8
        ? AppColors.success
        : item.confidenceScore >= 0.5
            ? const Color(0xFFFFD166)
            : AppColors.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Confidence dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.labelLarge),
                Text(item.portionLabel, style: AppTextStyles.caption),
              ],
            ),
          ),
          Text(
            '${item.calories} kcal',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.accent),
          ),
        ],
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
