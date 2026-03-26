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

  const MealPlanState({
    this.plan,
    this.groceryList,
    this.isGenerating = false,
    this.error,
  });

  MealPlanState copyWith({
    MealPlan? plan,
    GroceryList? groceryList,
    bool? isGenerating,
    String? error,
  }) =>
      MealPlanState(
        plan: plan ?? this.plan,
        groceryList: groceryList ?? this.groceryList,
        isGenerating: isGenerating ?? this.isGenerating,
        error: error,
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

  // ── Grocery list ──────────────────────────────────────────────────────────

  /// Toggles a grocery item's checked state and persists the change.
  Future<void> toggleGroceryItem(String itemId) async {
    final current = state.valueOrNull;
    if (current?.groceryList == null) return;

    final list = current!.groceryList!;
    final item = list.items.firstWhere((i) => i.id == itemId);
    final updated = list.withUpdatedItem(item.copyWith(isChecked: !item.isChecked));

    // Optimistic update first.
    state = AsyncValue.data(current.copyWith(groceryList: updated));

    // Persist the full items array (JSONB column).
    final client = Supabase.instance.client;
    try {
      await client.from('grocery_lists').update({
        'items': updated.items.map((i) => i.toMap()).toList(),
      }).eq('id', list.id);
    } catch (_) {
      // Rollback on failure.
      state = AsyncValue.data(current);
    }
  }

  /// Resets all grocery items to unchecked.
  Future<void> clearCheckedItems() async {
    final current = state.valueOrNull;
    if (current?.groceryList == null) return;

    final list = current!.groceryList!;
    final cleared = GroceryList(
      id: list.id,
      userId: list.userId,
      mealPlanId: list.mealPlanId,
      weekStart: list.weekStart,
      items: list.items.map((i) => i.copyWith(isChecked: false)).toList(),
      isShared: list.isShared,
      shareToken: list.shareToken,
      createdAt: list.createdAt,
    );

    state = AsyncValue.data(current.copyWith(groceryList: cleared));

    final client = Supabase.instance.client;
    await client.from('grocery_lists').update({
      'items': cleared.items.map((i) => i.toMap()).toList(),
    }).eq('id', list.id);
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
