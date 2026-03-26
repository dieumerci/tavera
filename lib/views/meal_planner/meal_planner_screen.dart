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
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
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

class _PlanContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_dayNames[safeDay]} — ${day.totalCalories} kcal',
                  style: AppTextStyles.labelLarge,
                ),
                Text(
                  '${day.meals.length} meals',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
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
                    ...day.meals.map((meal) => _MealCard(meal: meal)),
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

// ─── Meal card ────────────────────────────────────────────────────────────────

class _MealCard extends StatelessWidget {
  final PlannedMeal meal;
  const _MealCard({required this.meal});

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
                        const SizedBox(width: 8),
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
              (context, i) => _GroceryItemTile(
                item: entry.value[i],
                onToggle: () {
                  HapticService.selection();
                  ref
                      .read(mealPlanControllerProvider.notifier)
                      .toggleGroceryItem(entry.value[i].id);
                },
              ),
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
  const _GroceryItemTile({required this.item, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
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
