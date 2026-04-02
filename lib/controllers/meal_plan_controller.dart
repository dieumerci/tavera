import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/extensions/date_extensions.dart';
import '../models/grocery_list.dart';
import '../models/meal_plan.dart';
import '../services/analytics_service.dart';
import 'auth_controller.dart' show authStateProvider;

// ─── MealPlanController ───────────────────────────────────────────────────────
//
// Manages the current week's meal plan and its associated grocery list.
// Exposes `generate()` to call the `generate-meal-plan` Edge Function and
// `toggleGroceryItem()` to check/uncheck items.

// ── State ─────────────────────────────────────────────────────────────────────

class MealPlanState {
  final MealPlan? plan;
  final GroceryList? groceryList;
  final bool isGenerating;
  final String? error;
  /// Non-null while the swap bottom sheet is open with alternatives to choose from.
  final List<PlannedMeal>? swapAlternatives;
  final bool isLoadingSwap;

  const MealPlanState({
    this.plan,
    this.groceryList,
    this.isGenerating = false,
    this.error,
    this.swapAlternatives,
    this.isLoadingSwap = false,
  });

  MealPlanState copyWith({
    MealPlan? plan,
    GroceryList? groceryList,
    bool? isGenerating,
    String? error,
    List<PlannedMeal>? swapAlternatives,
    bool clearSwapAlternatives = false,
    bool? isLoadingSwap,
  }) =>
      MealPlanState(
        plan: plan ?? this.plan,
        groceryList: groceryList ?? this.groceryList,
        isGenerating: isGenerating ?? this.isGenerating,
        error: error,
        swapAlternatives: clearSwapAlternatives
            ? null
            : swapAlternatives ?? this.swapAlternatives,
        isLoadingSwap: isLoadingSwap ?? this.isLoadingSwap,
      );
}

// ── Provider ─────────────────────────────────────────────────────────────────

final mealPlanControllerProvider =
    AsyncNotifierProvider<MealPlanController, MealPlanState>(
  MealPlanController.new,
);

// ── Controller ────────────────────────────────────────────────────────────────

class MealPlanController extends AsyncNotifier<MealPlanState> {
  @override
  Future<MealPlanState> build() async {
    final authState = await ref.watch(authStateProvider.future);
    if (authState.session == null) return const MealPlanState();
    return _loadCurrentWeek();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<MealPlanState> _loadCurrentWeek() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const MealPlanState();

    final monday = _mondayOf(DateTime.now());
    final mondayStr = _fmtDate(monday);

    final planRow = await client
        .from('meal_plans')
        .select()
        .eq('user_id', userId)
        .eq('week_start', mondayStr)
        .maybeSingle();

    if (planRow == null) return const MealPlanState();

    final plan = MealPlan.fromMap(planRow);

    final groceryRow = await client
        .from('grocery_lists')
        .select()
        .eq('user_id', userId)
        .eq('meal_plan_id', plan.id)
        .maybeSingle();

    final grocery = groceryRow != null
        ? GroceryList.fromMap(groceryRow)
        : null;

    return MealPlanState(plan: plan, groceryList: grocery);
  }

  // ── Generate ──────────────────────────────────────────────────────────────

  /// Calls `generate-meal-plan` Edge Function for the current week.
  /// The function upserts both the plan and grocery list; we then reload from DB.
  Future<void> generate() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final monday = _mondayOf(DateTime.now());
    final mondayStr = _fmtDate(monday);

    state = AsyncValue.data(
      (state.valueOrNull ?? const MealPlanState())
          .copyWith(isGenerating: true, error: null),
    );

    try {
      await client.auth.getSession();
      await client.functions.invoke(
        'generate-meal-plan',
        body: {'user_id': userId, 'week_start': mondayStr},
      );
      AnalyticsService.track('meal_plan_generated', properties: {
        'week_start': mondayStr,
      });
      state = await AsyncValue.guard(_loadCurrentWeek);
    } catch (e) {
      state = AsyncValue.data(
        (state.valueOrNull ?? const MealPlanState()).copyWith(
          isGenerating: false,
          error: e.toString(),
        ),
      );
    }
  }

  // ── Regenerate single day ─────────────────────────────────────────────────

  /// Regenerates meals for [dayIndex] (0 = Monday) without touching other days.
  /// The existing grocery list is preserved; a note is shown in the UI.
  Future<void> regenerateDay(int dayIndex) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final monday = _mondayOf(DateTime.now());
    final mondayStr = _fmtDate(monday);

    state = AsyncValue.data(
      (state.valueOrNull ?? const MealPlanState())
          .copyWith(isGenerating: true, error: null),
    );

    try {
      await client.auth.getSession();
      await client.functions.invoke(
        'generate-meal-plan',
        body: {'user_id': userId, 'week_start': mondayStr, 'day_index': dayIndex},
      );
      state = await AsyncValue.guard(_loadCurrentWeek);
    } catch (e) {
      state = AsyncValue.data(
        (state.valueOrNull ?? const MealPlanState()).copyWith(
          isGenerating: false,
          error: e.toString(),
        ),
      );
    }
  }

  // ── Meal swap ─────────────────────────────────────────────────────────────

  /// Fetches 3 alternative meals for [slot] on [dayIndex] from GPT.
  /// Sets [isLoadingSwap] while the request is in flight, then stores
  /// [swapAlternatives] for the bottom sheet to display.
  Future<void> loadSwapAlternatives({
    required int dayIndex,
    required MealSlot slot,
    required String currentMealName,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    final planId = state.valueOrNull?.plan?.id;
    if (userId == null || planId == null) return;

    state = AsyncValue.data(
      (state.valueOrNull ?? const MealPlanState()).copyWith(
        isLoadingSwap: true,
        error: null,
        clearSwapAlternatives: true,
      ),
    );

    try {
      await client.auth.getSession();
      final result = await client.functions.invoke(
        'swap-planned-meal',
        body: {
          'user_id': userId,
          'plan_id': planId,
          'day_index': dayIndex,
          'slot': slot.name,
          'current_meal_name': currentMealName,
        },
      );
      final data = result.data as Map<String, dynamic>?;
      final altList = data?['alternatives'] as List<dynamic>? ?? [];
      final alternatives = altList
          .map((m) => PlannedMeal.fromMap(m as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(
        (state.valueOrNull ?? const MealPlanState()).copyWith(
          isLoadingSwap: false,
          swapAlternatives: alternatives,
        ),
      );
    } catch (e) {
      state = AsyncValue.data(
        (state.valueOrNull ?? const MealPlanState()).copyWith(
          isLoadingSwap: false,
          error: e.toString(),
          clearSwapAlternatives: true,
        ),
      );
    }
  }

  /// Replaces a meal in the current plan with [replacement] and persists.
  Future<void> applySwap({
    required int dayIndex,
    required MealSlot slot,
    required PlannedMeal replacement,
  }) async {
    final current = state.valueOrNull;
    final plan = current?.plan;
    if (plan == null) return;

    // Build the updated days list.
    final updatedDays = plan.days.map((day) {
      if (day.dayIndex != dayIndex) return day;
      final updatedMeals = day.meals.map((m) {
        return m.slot == slot ? replacement : m;
      }).toList();
      return MealPlanDay(dayIndex: day.dayIndex, meals: updatedMeals);
    }).toList();

    // Optimistic update.
    final updatedPlan = MealPlan(
      id: plan.id,
      userId: plan.userId,
      weekStart: plan.weekStart,
      calorieTarget: plan.calorieTarget,
      days: updatedDays,
      aiNotes: plan.aiNotes,
      createdAt: plan.createdAt,
    );

    state = AsyncValue.data(
      current!.copyWith(
        plan: updatedPlan,
        clearSwapAlternatives: true,
        isLoadingSwap: false,
      ),
    );

    // Persist to DB.
    final client = Supabase.instance.client;
    try {
      await client.from('meal_plans').update({
        'days': updatedDays.map((d) => d.toMap()).toList(),
      }).eq('id', plan.id);
    } catch (_) {
      // Roll back on failure.
      state = AsyncValue.data(current);
    }
  }

  /// Clears any loaded swap alternatives without applying them.
  void dismissSwap() {
    state = AsyncValue.data(
      (state.valueOrNull ?? const MealPlanState())
          .copyWith(clearSwapAlternatives: true, isLoadingSwap: false),
    );
  }

  // ── Grocery list ──────────────────────────────────────────────────────────

  /// Toggles a grocery item's checked state and persists the change.
  Future<void> toggleGroceryItem(String itemId) async {
    await _mutateList((list) {
      final item = list.items.firstWhere((i) => i.id == itemId);
      return list.withUpdatedItem(item.copyWith(isChecked: !item.isChecked));
    });
  }

  /// Updates the quantity (or name) of a grocery item and persists.
  Future<void> editGroceryItem(
      String itemId, {String? quantity, String? name}) async {
    await _mutateList((list) {
      final item = list.items.firstWhere((i) => i.id == itemId);
      return list.withUpdatedItem(item.copyWith(quantity: quantity, name: name));
    });
  }

  /// Removes a grocery item by id and persists.
  Future<void> removeGroceryItem(String itemId) async {
    await _mutateList((list) => list.withRemovedItem(itemId));
  }

  /// Adds a custom grocery item to the list and persists.
  Future<void> addGroceryItem({
    required String name,
    required String quantity,
    GroceryCategory category = GroceryCategory.other,
  }) async {
    await _mutateList((list) => list.withAddedItem(GroceryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name.trim(),
          quantity: quantity.trim(),
          category: category,
        )));
  }

  /// Shared optimistic-update-then-persist helper for all grocery mutations.
  Future<void> _mutateList(
      GroceryList Function(GroceryList) transform) async {
    final current = state.valueOrNull;
    if (current?.groceryList == null) return;

    final updated = transform(current!.groceryList!);
    state = AsyncValue.data(current.copyWith(groceryList: updated));

    final client = Supabase.instance.client;
    try {
      await client.from('grocery_lists').update({
        'items': updated.items.map((i) => i.toMap()).toList(),
      }).eq('id', updated.id);
    } catch (_) {
      state = AsyncValue.data(current);
    }
  }

  /// Resets all grocery items to unchecked.
  Future<void> clearCheckedItems() async {
    await _mutateList((list) => list.withReplacedItems(
          list.items.map((i) => i.copyWith(isChecked: false)).toList(),
        ));
  }

  // ── Share ─────────────────────────────────────────────────────────────────

  /// Marks the grocery list as shared and returns its share token.
  Future<String?> shareGroceryList() async {
    final current = state.valueOrNull;
    if (current?.groceryList == null) return null;

    final list = current!.groceryList!;
    if (list.isShared && list.shareToken != null) return list.shareToken;

    final client = Supabase.instance.client;
    final row = await client
        .from('grocery_lists')
        .update({'is_shared': true})
        .eq('id', list.id)
        .select('share_token')
        .single();

    final token = row['share_token'] as String?;
    state = await AsyncValue.guard(_loadCurrentWeek);
    return token;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static DateTime _mondayOf(DateTime date) {
    final diff = date.weekday - DateTime.monday;
    return DateTime(date.year, date.month, date.day - diff);
  }

  static String _fmtDate(DateTime d) => d.toIsoDateString();
}

// ── 7-day minimum check ───────────────────────────────────────────────────────

/// Returns the count of distinct calendar days (in UTC) that have at least
/// one meal log. Used to gate meal plan generation (requires ≥ 7 days).
final distinctLoggedDaysProvider = FutureProvider<int>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return 0;

  // Fetch all logged_at timestamps and count distinct local calendar days.
  final rows = await client
      .from('meal_logs')
      .select('logged_at')
      .eq('user_id', userId);

  final days = (rows as List<dynamic>)
      .map((r) {
        final dt = DateTime.parse(r['logged_at'] as String).toLocal();
        return '${dt.year}-${dt.month}-${dt.day}';
      })
      .toSet();

  return days.length;
});
