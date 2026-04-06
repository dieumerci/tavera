import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../controllers/meal_plan_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/grocery_list.dart';
import '../../models/meal_plan.dart';
import '../../services/analytics_service.dart';
import '../../services/haptic_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/tavera_loading.dart';
import '../paywall/paywall_sheet.dart';

// ─── MealPlannerScreen ────────────────────────────────────────────────────────
//
// Two-tab screen (Plan | Grocery) with paywall gate for free users.
//   Plan tab: day selector + meal slot cards for the week
//   Grocery tab: categorised checklist with progress bar + share export

class MealPlannerScreen extends ConsumerStatefulWidget {
  const MealPlannerScreen({super.key});

  @override
  ConsumerState<MealPlannerScreen> createState() => _MealPlannerScreenState();
}

class _MealPlannerScreenState extends ConsumerState<MealPlannerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  // Day index 0 = Monday (ISO week).
  int _selectedDay = DateTime.now().weekday - 1;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && !_tabCtrl.indexIsChanging) {
        AnalyticsService.track('grocery_list_opened');
      }
    });

    // Auto-generate if premium and no plan exists for this week.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (SubscriptionService.isPremium(ref)) {
        final current = ref.read(mealPlanControllerProvider).valueOrNull;
        if (current?.plan == null) {
          ref.read(mealPlanControllerProvider.notifier).generate();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = SubscriptionService.isPremium(ref);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () {
            HapticService.selection();
            context.pop();
          },
        ),
        title: const Text('Meal Planner'),
        actions: [
          if (isPremium)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () {
                HapticService.selection();
                ref.read(mealPlanControllerProvider.notifier).generate();
              },
              tooltip: 'Regenerate plan',
            ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTextStyles.labelLarge.copyWith(fontSize: 14),
          onTap: (_) => HapticService.selection(),
          tabs: const [
            Tab(text: 'This Week'),
            Tab(text: 'Grocery List'),
          ],
        ),
      ),
      body: isPremium
          ? TabBarView(
              controller: _tabCtrl,
              children: [
                _PlanTab(
                  selectedDay: _selectedDay,
                  onDayChanged: (d) => setState(() => _selectedDay = d),
                ),
                const _GroceryTab(),
              ],
            )
          : const _PaywallPlaceholder(),
    );
  }
}

// ─── Plan tab ─────────────────────────────────────────────────────────────────

class _PlanTab extends ConsumerWidget {
  final int selectedDay;
  final ValueChanged<int> onDayChanged;

  const _PlanTab({required this.selectedDay, required this.onDayChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mealPlanControllerProvider);

    return async.when(
      loading: () => const Center(child: TaveraLoading()),
      error: (e, _) => _ErrorState(
        error: e.toString(),
        onRetry: () => ref.invalidate(mealPlanControllerProvider),
      ),
      data: (state) {
        if (state.isGenerating) {
          return const _GeneratingState();
        }

        if (state.plan == null) {
          final loggedDays =
              ref.watch(distinctLoggedDaysProvider).valueOrNull ?? 0;
          if (loggedDays < 7) {
            return _InsufficientDataState(loggedDays: loggedDays);
          }
          return _EmptyPlanState(
            onGenerate: () =>
                ref.read(mealPlanControllerProvider.notifier).generate(),
          );
        }

        return _PlanContent(
          plan: state.plan!,
          selectedDay: selectedDay,
          onDayChanged: onDayChanged,
        );
      },
    );
  }
}

class _PlanContent extends ConsumerWidget {
  final MealPlan plan;
  final int selectedDay;
  final ValueChanged<int> onDayChanged;

  const _PlanContent({
    required this.plan,
    required this.selectedDay,
    required this.onDayChanged,
  });

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Guard: clamp selectedDay in case the plan has fewer than 7 days.
    final safeDay =
        selectedDay.clamp(0, (plan.days.length - 1).clamp(0, 6));
    final day =
        plan.days.isEmpty ? null : plan.days[safeDay];

    return Column(
      children: [
        // ── Day selector ──────────────────────────────────────────────────
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: List.generate(7, (i) {
              final isSelected = i == safeDay;
              final dayPlan = plan.days.length > i ? plan.days[i] : null;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    onDayChanged(i);
                  },
                  onLongPress: () {
                    HapticService.medium();
                    _showRegenerateDayDialog(context, ref, i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _dayNames[i],
                          style: AppTextStyles.caption.copyWith(
                            color: isSelected
                                ? AppColors.background
                                : AppColors.textSecondary,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            fontSize: 11,
                          ),
                        ),
                        if (dayPlan != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${dayPlan.totalCalories}',
                            style: AppTextStyles.caption.copyWith(
                              color: isSelected
                                  ? AppColors.background
                                  : AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // ── Summary bar ───────────────────────────────────────────────────
        if (day != null)
          Container(
            color: AppColors.surface,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  '${_dayNames[safeDay]} — ${day.totalCalories} kcal',
                  style: AppTextStyles.labelLarge,
                ),
                const SizedBox(width: 6),
                Text(
                  '· ${day.meals.length} meals',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    _showRegenerateDayDialog(context, ref, safeDay);
                  },
                  child: Row(
                    children: [
                      Icon(Icons.refresh_rounded,
                          size: 14, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Regenerate',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // ── Meal cards ────────────────────────────────────────────────────
        Expanded(
          child: day == null
              ? const Center(
                  child: Text('No plan for this day.',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    ...day.meals.map((meal) => _MealCard(
                          meal: meal,
                          onSwap: () => _showSwapSheet(
                              context, ref, plan.id, safeDay, meal),
                        )),
                    if (plan.aiNotes != null && plan.aiNotes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _AiNotesCard(notes: plan.aiNotes!),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ─── Regenerate-day dialog helper ─────────────────────────────────────────────

void _showRegenerateDayDialog(
    BuildContext context, WidgetRef ref, int dayIndex) {
  const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Regenerate ${dayNames[dayIndex]}?',
          style: AppTextStyles.labelLarge),
      content: Text(
        'AI will replace meals for this day with fresh ideas. '
        'Other days and your grocery list are unchanged.',
        style:
            AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ref
                .read(mealPlanControllerProvider.notifier)
                .regenerateDay(dayIndex);
          },
          child: const Text('Regenerate',
              style: TextStyle(color: AppColors.accent)),
        ),
      ],
    ),
  );
}

// ─── Swap bottom sheet ────────────────────────────────────────────────────────

void _showSwapSheet(
  BuildContext context,
  WidgetRef ref,
  String planId,
  int dayIndex,
  PlannedMeal currentMeal,
) {
  // Kick off the alternatives load immediately.
  ref.read(mealPlanControllerProvider.notifier).loadSwapAlternatives(
        dayIndex: dayIndex,
        slot: currentMeal.slot,
        currentMealName: currentMeal.name,
      );

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    isScrollControlled: true,
    builder: (ctx) => _SwapSheet(
      dayIndex: dayIndex,
      currentMeal: currentMeal,
      onDismiss: () {
        ref.read(mealPlanControllerProvider.notifier).dismissSwap();
        Navigator.of(ctx).pop();
      },
      onApply: (replacement) {
        ref.read(mealPlanControllerProvider.notifier).applySwap(
              dayIndex: dayIndex,
              slot: currentMeal.slot,
              replacement: replacement,
            );
        HapticService.medium();
        Navigator.of(ctx).pop();
      },
    ),
  );
}

class _SwapSheet extends ConsumerWidget {
  final int dayIndex;
  final PlannedMeal currentMeal;
  final VoidCallback onDismiss;
  final ValueChanged<PlannedMeal> onApply;

  const _SwapSheet({
    required this.dayIndex,
    required this.currentMeal,
    required this.onDismiss,
    required this.onApply,
  });

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planState =
        ref.watch(mealPlanControllerProvider).valueOrNull;
    final isLoading = planState?.isLoadingSwap ?? false;
    final alternatives = planState?.swapAlternatives;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Swap ${currentMeal.slot.label}',
                        style: AppTextStyles.titleMedium,
                      ),
                      Text(
                        '${_dayNames[dayIndex]} · ${currentMeal.name}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose an alternative:',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const Expanded(child: Center(child: TaveraLoading()))
            else if (alternatives == null || alternatives.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No alternatives available.\nTry again.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: alternatives.length,
                  itemBuilder: (_, i) {
                    final alt = alternatives[i];
                    return _SwapAlternativeCard(
                      meal: alt,
                      onTap: () => onApply(alt),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SwapAlternativeCard extends StatelessWidget {
  final PlannedMeal meal;
  final VoidCallback onTap;

  const _SwapAlternativeCard({required this.meal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.selection();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meal.name, style: AppTextStyles.labelLarge),
                  if (meal.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meal.description,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (meal.prepMinutes != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.timer_outlined,
                          size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${meal.prepMinutes} min',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${meal.calories} kcal',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Use this',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Meal card ────────────────────────────────────────────────────────────────

class _MealCard extends StatelessWidget {
  final PlannedMeal meal;
  final VoidCallback? onSwap;
  const _MealCard({required this.meal, this.onSwap});

  Color get _slotColor => switch (meal.slot) {
        MealSlot.breakfast => const Color(0xFFFFD166),
        MealSlot.lunch     => const Color(0xFF4ECDC4),
        MealSlot.dinner    => const Color(0xFF9B59B6),
        MealSlot.snack     => AppColors.textSecondary,
      };

  IconData get _slotIcon => switch (meal.slot) {
        MealSlot.breakfast => Icons.wb_sunny_rounded,
        MealSlot.lunch     => Icons.wb_cloudy_rounded,
        MealSlot.dinner    => Icons.nightlight_rounded,
        MealSlot.snack     => Icons.coffee_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = _slotColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_slotIcon, color: color, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                meal.slot.label,
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${meal.calories} kcal',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onSwap != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    HapticService.selection();
                    onSwap!();
                  },
                  child: const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(meal.name, style: AppTextStyles.labelLarge),
          if (meal.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meal.description,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Macros row
          if (meal.proteinG != null ||
              meal.carbsG != null ||
              meal.fatG != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (meal.proteinG != null)
                  _MacroPill(
                      label: 'P',
                      value: '${meal.proteinG!.toStringAsFixed(0)}g',
                      color: const Color(0xFF4ECDC4)),
                if (meal.carbsG != null) ...[
                  const SizedBox(width: 6),
                  _MacroPill(
                      label: 'C',
                      value: '${meal.carbsG!.toStringAsFixed(0)}g',
                      color: const Color(0xFFFFD166)),
                ],
                if (meal.fatG != null) ...[
                  const SizedBox(width: 6),
                  _MacroPill(
                      label: 'F',
                      value: '${meal.fatG!.toStringAsFixed(0)}g',
                      color: const Color(0xFFFF6B6B)),
                ],
                if (meal.prepMinutes != null) ...[
                  const Spacer(),
                  Icon(Icons.timer_outlined,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    '${meal.prepMinutes} min',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MacroPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── AI notes card ────────────────────────────────────────────────────────────

class _AiNotesCard extends StatelessWidget {
  final String notes;
  const _AiNotesCard({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              color: AppColors.accent, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              notes,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grocery tab ──────────────────────────────────────────────────────────────

class _GroceryTab extends ConsumerWidget {
  const _GroceryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mealPlanControllerProvider);

    return async.when(
      loading: () => const Center(child: TaveraLoading()),
      error: (e, _) => _ErrorState(
        error: e.toString(),
        onRetry: () => ref.invalidate(mealPlanControllerProvider),
      ),
      data: (state) {
        if (state.isGenerating) {
          return const _GeneratingState();
        }
        if (state.groceryList == null) {
          return _EmptyGroceryState(
            hasPlan: state.plan != null,
            onGenerate: () =>
                ref.read(mealPlanControllerProvider.notifier).generate(),
          );
        }
        return _GroceryContent(groceryList: state.groceryList!);
      },
    );
  }
}

class _GroceryContent extends ConsumerWidget {
  final GroceryList groceryList;
  const _GroceryContent({required this.groceryList});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = groceryList.groupedItems;
    final progress = groceryList.progress;

    return CustomScrollView(
      slivers: [
        // ── Progress bar + actions ─────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${groceryList.checkedItems} / ${groceryList.totalItems} items',
                            style: AppTextStyles.labelLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Week of ${DateFormat('MMM d').format(groceryList.weekStart)}',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        // Add custom item
                        _IconAction(
                          icon: Icons.add_rounded,
                          tooltip: 'Add item',
                          onTap: () {
                            HapticService.selection();
                            _showAddItemDialog(context, ref);
                          },
                        ),
                        const SizedBox(width: 4),
                        // Clear checked
                        if (groceryList.checkedItems > 0)
                          _IconAction(
                            icon: Icons.check_circle_outline_rounded,
                            tooltip: 'Clear checked',
                            onTap: () {
                              HapticService.medium();
                              ref
                                  .read(mealPlanControllerProvider.notifier)
                                  .clearCheckedItems();
                            },
                          ),
                        const SizedBox(width: 4),
                        // Share
                        _IconAction(
                          icon: Icons.share_rounded,
                          tooltip: 'Share list',
                          onTap: () => _share(context, ref),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress >= 1.0
                          ? AppColors.success
                          : AppColors.accent,
                    ),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Category sections ──────────────────────────────────────────────
        for (final entry in grouped.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Text(entry.key.emoji,
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(
                    entry.key.label,
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${entry.value.length})',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final tile = entry.value[i];
                return _GroceryItemTile(
                  item: tile,
                  onToggle: () {
                    HapticService.selection();
                    ref
                        .read(mealPlanControllerProvider.notifier)
                        .toggleGroceryItem(tile.id);
                  },
                  onLongPress: () {
                    HapticService.medium();
                    _showItemActions(context, ref, tile);
                  },
                );
              },
              childCount: entry.value.length,
            ),
          ),
        ],

        // ── Grocery delivery stub (Phase 3 integration placeholder) ──────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: _DeliveryStubBanner(),
          ),
        ),
      ],
    );
  }

  void _showItemActions(BuildContext context, WidgetRef ref, GroceryItem item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GroceryItemActionSheet(
        item: item,
        onEdit: (newQty) => ref
            .read(mealPlanControllerProvider.notifier)
            .editGroceryItem(item.id, quantity: newQty),
        onRemove: () => ref
            .read(mealPlanControllerProvider.notifier)
            .removeGroceryItem(item.id),
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add item', style: AppTextStyles.titleMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: AppTextStyles.bodyLarge,
              decoration:
                  const InputDecoration(hintText: 'Item name (e.g. Oats)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              style: AppTextStyles.bodyLarge,
              decoration:
                  const InputDecoration(hintText: 'Quantity (e.g. 500g)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop();
              ref.read(mealPlanControllerProvider.notifier).addGroceryItem(
                    name: name,
                    quantity: qtyCtrl.text.trim(),
                  );
            },
            child: Text('Add', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    HapticService.heavy();
    final token =
        await ref.read(mealPlanControllerProvider.notifier).shareGroceryList();
    if (token == null) return;
    if (!context.mounted) return;

    // Copy token to clipboard and show snack.
    await Clipboard.setData(ClipboardData(text: token));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Share code "$token" copied to clipboard!'),
        backgroundColor: AppColors.success.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─── Grocery delivery stub ────────────────────────────────────────────────────
// Phase 3 will wire a real GroceryDeliveryService here.

class _DeliveryStubBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_grocery_store_outlined,
                color: AppColors.textTertiary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect delivery service',
                    style: AppTextStyles.labelLarge),
                Text(
                  'Order your groceries in one tap — coming soon',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textTertiary, size: 18),
        ],
      ),
    );
  }
}

class _GroceryItemTile extends StatelessWidget {
  final GroceryItem item;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  const _GroceryItemTile(
      {required this.item, required this.onToggle, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: item.isChecked
              ? AppColors.surface.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: item.isChecked ? AppColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: item.isChecked
                      ? AppColors.accent
                      : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: item.isChecked
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: AppColors.background)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: AppTextStyles.labelLarge.copyWith(
                      decoration: item.isChecked
                          ? TextDecoration.lineThrough
                          : null,
                      color: item.isChecked
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (item.quantity.isNotEmpty)
                    Text(
                      item.quantity,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
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

// ─── Grocery item action sheet ────────────────────────────────────────────────

class _GroceryItemActionSheet extends StatefulWidget {
  final GroceryItem item;
  final Future<void> Function(String newQty) onEdit;
  final VoidCallback onRemove;
  const _GroceryItemActionSheet(
      {required this.item, required this.onEdit, required this.onRemove});

  @override
  State<_GroceryItemActionSheet> createState() =>
      _GroceryItemActionSheetState();
}

class _GroceryItemActionSheetState extends State<_GroceryItemActionSheet> {
  late final TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: widget.item.quantity);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
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
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.item.name, style: AppTextStyles.titleMedium),
          const SizedBox(height: 16),
          // Quantity editor
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  style: AppTextStyles.bodyLarge,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    labelStyle: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () async {
                  HapticService.selection();
                  Navigator.of(context).pop();
                  await widget.onEdit(_qtyCtrl.text.trim());
                },
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger),
            title: Text('Remove from list',
                style:
                    AppTextStyles.bodyLarge.copyWith(color: AppColors.danger)),
            onTap: () {
              HapticService.medium();
              Navigator.of(context).pop();
              widget.onRemove();
            },
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

// ─── State widgets ────────────────────────────────────────────────────────────

class _GeneratingState extends StatelessWidget {
  const _GeneratingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TaveraLoading(),
            const SizedBox(height: 24),
            Text('Generating your plan…', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tavera AI is analysing your eating patterns to create a personalised weekly plan.',
              style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsufficientDataState extends StatelessWidget {
  final int loggedDays;
  const _InsufficientDataState({required this.loggedDays});

  @override
  Widget build(BuildContext context) {
    final remaining = 7 - loggedDays;
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
              child: const Icon(Icons.bar_chart_rounded,
                  color: AppColors.textSecondary, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Almost there!', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Log $remaining more day${remaining == 1 ? '' : 's'} of meals and Tavera will build a personalised plan tailored to your nutrition goals.',
              style:
                  AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Progress indicator
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: loggedDays / 7,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.accent),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$loggedDays / 7 days',
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlanState extends StatelessWidget {
  final VoidCallback onGenerate;
  const _EmptyPlanState({required this.onGenerate});

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
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.restaurant_menu_rounded,
                  color: AppColors.textSecondary, size: 36),
            ),
            const SizedBox(height: 20),
            Text('No plan this week', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Log at least 7 days of meals and Tavera will build a personalised plan tailored to your goals.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                HapticService.heavy();
                onGenerate();
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Generate plan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGroceryState extends StatelessWidget {
  final bool hasPlan;
  final VoidCallback onGenerate;
  const _EmptyGroceryState(
      {required this.hasPlan, required this.onGenerate});

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
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shopping_cart_outlined,
                  color: AppColors.textSecondary, size: 36),
            ),
            const SizedBox(height: 20),
            Text('No grocery list yet', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              hasPlan
                  ? 'Regenerate your plan to build the grocery list.'
                  : 'Generate a meal plan first and your shopping list will appear here.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                HapticService.heavy();
                onGenerate();
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                  hasPlan ? 'Regenerate plan' : 'Generate plan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 36),
            const SizedBox(height: 12),
            Text('Something went wrong', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              error,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                HapticService.medium();
                onRetry();
              },
              child: const Text('Try again'),
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
              child: const Icon(Icons.lock_outline_rounded,
                  color: AppColors.accent, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Premium feature', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Upgrade to Tavera Premium to unlock AI-generated meal plans and smart grocery lists tailored to your nutrition goals.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                HapticService.heavy();
                showPaywallSheet(context);
              },
              child: const Text('Unlock Meal Planner'),
            ),
          ],
        ),
      ),
    );
  }
}
