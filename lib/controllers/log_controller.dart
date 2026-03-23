import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../models/meal_log.dart';
import '../models/user_profile.dart';

class DailyLogState {
  final List<MealLog> todayLogs;
  final int totalCalories;

  const DailyLogState({
    this.todayLogs = const [],
    this.totalCalories = 0,
  });

  int get logCount => todayLogs.length;

  DailyLogState copyWith({
    List<MealLog>? todayLogs,
    int? totalCalories,
  }) =>
      DailyLogState(
        todayLogs: todayLogs ?? this.todayLogs,
        totalCalories: totalCalories ?? this.totalCalories,
      );
}

class LogController extends AsyncNotifier<DailyLogState> {
  @override
  Future<DailyLogState> build() async {
    return _fetchTodayLogs();
  }

  Future<DailyLogState> _fetchTodayLogs() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const DailyLogState();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final response = await client
        .from('meal_logs')
        .select()
        .eq('user_id', userId)
        .gte('logged_at', startOfDay.toIso8601String())
        .lt('logged_at', endOfDay.toIso8601String())
        .order('logged_at', ascending: false);

    final logs = (response as List<dynamic>)
        .map((e) => MealLog.fromMap(e as Map<String, dynamic>))
        .toList();

    final totalCalories = logs.fold(0, (sum, log) => sum + log.totalCalories);

    return DailyLogState(todayLogs: logs, totalCalories: totalCalories);
  }

  /// Returns true if the user is allowed to log another meal.
  /// Enforces the free tier 3-log/day limit.
  bool canLog(UserProfile? profile) {
    if (profile?.isPremium == true) return true;
    final count = state.valueOrNull?.logCount ?? 0;
    return count < AppConfig.freeDailyLogLimit;
  }

  /// Optimistic update: add the log to local state immediately
  /// before waiting for the next full refresh.
  void optimisticallyAddLog(MealLog log) {
    final current = state.valueOrNull ?? const DailyLogState();
    state = AsyncData(
      current.copyWith(
        todayLogs: [log, ...current.todayLogs],
        totalCalories: current.totalCalories + log.totalCalories,
      ),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchTodayLogs);
  }
}

final logControllerProvider =
    AsyncNotifierProvider<LogController, DailyLogState>(LogController.new);
