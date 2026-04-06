import 'dart:async' show Timer, unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/extensions/date_extensions.dart';
import '../models/food_item.dart';
import '../models/meal_log.dart';
import '../models/user_profile.dart';
import '../services/analytics_service.dart';
import 'auth_controller.dart' show authStateProvider;
import 'challenge_controller.dart' show myChallengesProvider;
import 'known_meal_controller.dart' show knownMealControllerProvider;

// ── Daily summary state ─────────────────────────────────────────────────────

class DailyLogState {
  final List<MealLog> todayLogs;
  final int totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;

  const DailyLogState({
    this.todayLogs = const [],
    this.totalCalories = 0,
    this.totalProtein = 0,
    this.totalCarbs = 0,
    this.totalFat = 0,
  });

  int get logCount => todayLogs.length;

  /// Sum of dietary fibre across all today's meals (grams).
  /// Null entries (pre-migration logs) are treated as 0.
  double get totalFiber =>
      todayLogs.fold(0.0, (s, l) => s + (l.totalFiber ?? 0));

  double get totalNetCarbs =>
      todayLogs.fold(0.0, (s, l) => s + l.totalNetCarbs);

  DailyLogState copyWith({
    List<MealLog>? todayLogs,
    int? totalCalories,
    double? totalProtein,
    double? totalCarbs,
    double? totalFat,
  }) =>
      DailyLogState(
        todayLogs: todayLogs ?? this.todayLogs,
        totalCalories: totalCalories ?? this.totalCalories,
        totalProtein: totalProtein ?? this.totalProtein,
        totalCarbs: totalCarbs ?? this.totalCarbs,
        totalFat: totalFat ?? this.totalFat,
      );
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Builds a UTC timestamp range for a given LOCAL calendar day.
/// Sending UTC ISO strings ensures Postgres (which stores timestamptz as UTC)
/// compares correctly regardless of the user's timezone offset.
({String start, String end}) _dayRange(DateTime localDay) {
  final start = DateTime(localDay.year, localDay.month, localDay.day).toUtc();
  final end = start.add(const Duration(days: 1));
  return (start: start.toIso8601String(), end: end.toIso8601String());
}

DailyLogState _summarise(List<MealLog> logs) {
  final calories = logs.fold(0, (s, l) => s + l.totalCalories);
  final protein  = logs.fold(0.0, (s, l) => s + (l.totalProtein ?? 0));
  final carbs    = logs.fold(0.0, (s, l) => s + (l.totalCarbs   ?? 0));
  final fat      = logs.fold(0.0, (s, l) => s + (l.totalFat     ?? 0));
  return DailyLogState(
    todayLogs: logs,
    totalCalories: calories,
    totalProtein: protein,
    totalCarbs: carbs,
    totalFat: fat,
  );
}

// ── Today's log controller (used by camera chip) ────────────────────────────

class LogController extends AsyncNotifier<DailyLogState> {
  @override
  Future<DailyLogState> build() async {
    // Watch auth state so this controller rebuilds when the session
    // arrives on cold start — prevents the dashboard showing empty data
    // while Supabase is still restoring the session from storage.
    final authState = await ref.watch(authStateProvider.future);
    if (authState.session == null) return const DailyLogState();
    return _fetchTodayLogs();
  }

  Future<DailyLogState> _fetchTodayLogs() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const DailyLogState();

    final range = _dayRange(DateTime.now());

    final response = await client
        .from('meal_logs')
        .select()
        .eq('user_id', userId)
        .gte('logged_at', range.start)
        .lt('logged_at', range.end)
        .order('logged_at', ascending: false);

    final logs = (response as List<dynamic>)
        .map((e) => MealLog.fromMap(e as Map<String, dynamic>))
        .toList();

    return _summarise(logs);
  }

  /// Returns true if the user may log another meal right now.
  bool canLog(UserProfile? profile) {
    if (profile?.isPremium == true) return true;
    return (state.valueOrNull?.logCount ?? 0) < AppConfig.freeDailyLogLimit;
  }

  /// Instant UI update while the DB write is in-flight.
  void optimisticallyAddLog(MealLog log) {
    final current = state.valueOrNull ?? const DailyLogState();
    final logs = [log, ...current.todayLogs];
    state = AsyncData(_summarise(logs));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchTodayLogs);
  }
}

final logControllerProvider =
    AsyncNotifierProvider<LogController, DailyLogState>(LogController.new);

// ── History provider (any date, cached per date) ────────────────────────────

/// FutureProvider.family keyed on a LOCAL calendar day.
/// Each unique date gets its own cached provider instance — navigating
/// back to a visited date is instant, only new dates hit Supabase.
final historyLogsProvider =
    FutureProvider.family<List<MealLog>, DateTime>((ref, date) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final range = _dayRange(date);

  final response = await client
      .from('meal_logs')
      .select()
      .eq('user_id', userId)
      .gte('logged_at', range.start)
      .lt('logged_at', range.end)
      .order('logged_at', ascending: false);

  return (response as List<dynamic>)
      .map((e) => MealLog.fromMap(e as Map<String, dynamic>))
      .toList();
});

// ── 7-day calorie trend ─────────────────────────────────────────────────────

/// Returns a list of 7 integers — calories consumed for each of the last 7
/// local calendar days, oldest first (index 0 = 6 days ago, index 6 = today).
/// Days with no logs contribute 0.
///
/// ⚠️  Uses `ref.watch(authStateProvider)` directly — NOT `.future`.
///
/// `StreamProvider.future` in Riverpod 2.x is a one-shot future that resolves
/// with the FIRST stream emission and then stays frozen at that value forever.
/// Supabase's `onAuthStateChange` always emits `AuthState(session: null)` first
/// (while it reads secure storage), then a second event with the real session.
/// Using `.future` therefore caches a null-session result and never re-runs —
/// which is exactly why the 7-day trend was blank on cold start.
///
/// Watching the `StreamProvider` directly creates a live dependency: every new
/// emission invalidates this provider and triggers a fresh DB query, so the
/// chart appears as soon as the session is restored (typically < 300 ms).
final weeklyCaloriesProvider = FutureProvider<List<int>>((ref) async {
  final authAsync = ref.watch(authStateProvider);
  final session = authAsync.valueOrNull?.session;
  // No session yet (auth still loading or truly unauthenticated).
  // Return zeros now; this provider will be re-run automatically when
  // authAsync emits a new value (i.e., once the session is restored).
  if (session == null) return List.filled(7, 0);

  final client = Supabase.instance.client;
  final userId = session.user.id;

  final today = DateTime.now();
  // Fetch 7-day window in one query: from 6 days ago (local midnight UTC) to
  // start of tomorrow.
  final windowStart =
      DateTime(today.year, today.month, today.day - 6).toUtc();
  final windowEnd =
      DateTime(today.year, today.month, today.day + 1).toUtc();

  final rows = await client
      .from('meal_logs')
      .select('logged_at, total_calories')
      .eq('user_id', userId)
      .gte('logged_at', windowStart.toIso8601String())
      .lt('logged_at', windowEnd.toIso8601String());

  // Bucket calories by local calendar day offset (0 = 6 days ago, 6 = today).
  final buckets = List.filled(7, 0);
  for (final row in (rows as List<dynamic>)) {
    final loggedAt = DateTime.parse(row['logged_at'] as String).toLocal();
    final dayOffset = today.difference(
      DateTime(loggedAt.year, loggedAt.month, loggedAt.day),
    ).inDays;
    if (dayOffset >= 0 && dayOffset < 7) {
      buckets[6 - dayOffset] += (row['total_calories'] as num?)?.toInt() ?? 0;
    }
  }
  return buckets;
});

// ── Consistency streak ──────────────────────────────────────────────────────
//
// Counts consecutive calendar days (ending today) on which the user logged
// at least one meal. Computed entirely from meal_logs — no extra DB column.
// Looks back 60 days to bound the query.

/// Current logging streak in days. 0 when today has no logs yet.
final loggingStreakProvider = FutureProvider<int>((ref) async {
  // Same live-dependency pattern as weeklyCaloriesProvider — see its comment
  // for a full explanation of why .future must NOT be used here.
  final authAsync = ref.watch(authStateProvider);
  final session = authAsync.valueOrNull?.session;
  if (session == null) return 0;

  final client = Supabase.instance.client;
  final userId = session.user.id;

  final today = DateTime.now();
  final cutoff =
      DateTime(today.year, today.month, today.day - 60).toUtc();

  final rows = await client
      .from('meal_logs')
      .select('logged_at')
      .eq('user_id', userId)
      .gte('logged_at', cutoff.toIso8601String())
      .order('logged_at', ascending: false);

  // Collect unique local calendar day strings.
  final days = <String>{};
  for (final row in (rows as List<dynamic>)) {
    final dt = DateTime.parse(row['logged_at'] as String).toLocal();
    days.add(
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}');
  }

  // Walk backwards from today until a day without a log is found.
  int streak = 0;
  var checkDate = DateTime(today.year, today.month, today.day);
  while (streak < 61) {
    final key =
        '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
    if (!days.contains(key)) break;
    streak++;
    checkDate = checkDate.subtract(const Duration(days: 1));
  }
  return streak;
});

// ── Weekly full stats ────────────────────────────────────────────────────────
//
// Richer version of weeklyCaloriesProvider — returns per-day summaries with
// macros for the weekly summary screen.

class DayStats {
  final DateTime date;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final int mealCount;

  const DayStats({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.mealCount,
  });
}

/// Returns daily stats for the last 7 local calendar days, oldest first.
/// Days with no logs contribute a zero DayStats entry.
final weeklyFullStatsProvider = FutureProvider<List<DayStats>>((ref) async {
  // Same live-dependency pattern as weeklyCaloriesProvider — see its comment.
  final authAsync = ref.watch(authStateProvider);
  final session = authAsync.valueOrNull?.session;
  if (session == null) return _emptyWeek();

  final client = Supabase.instance.client;
  final userId = session.user.id;

  final today = DateTime.now();
  final windowStart =
      DateTime(today.year, today.month, today.day - 6).toUtc();
  final windowEnd =
      DateTime(today.year, today.month, today.day + 1).toUtc();

  final rows = await client
      .from('meal_logs')
      .select(
          'logged_at, total_calories, total_protein, total_carbs, total_fat')
      .eq('user_id', userId)
      .gte('logged_at', windowStart.toIso8601String())
      .lt('logged_at', windowEnd.toIso8601String());

  // Accumulate totals per local calendar day.
  // Keys are zero-padded (yyyy-MM-dd) to prevent month/day boundary mismatches
  // where e.g. Jan 5 produces "2026-1-5" instead of "2026-01-05".
  final buckets = <String, DayStats>{};
  for (final row in (rows as List<dynamic>)) {
    final dt = DateTime.parse(row['logged_at'] as String).toLocal();
    final key =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final existing = buckets[key];
    final kcal = (row['total_calories'] as num?)?.toInt() ?? 0;
    final p = (row['total_protein'] as num?)?.toDouble() ?? 0;
    final c = (row['total_carbs'] as num?)?.toDouble() ?? 0;
    final f = (row['total_fat'] as num?)?.toDouble() ?? 0;
    buckets[key] = DayStats(
      date: DateTime(dt.year, dt.month, dt.day),
      calories: (existing?.calories ?? 0) + kcal,
      protein: (existing?.protein ?? 0) + p,
      carbs: (existing?.carbs ?? 0) + c,
      fat: (existing?.fat ?? 0) + f,
      mealCount: (existing?.mealCount ?? 0) + 1,
    );
  }

  // Build ordered list for the 7-day window, filling gaps with zero entries.
  return List.generate(7, (i) {
    final d = DateTime(today.year, today.month, today.day - (6 - i));
    final key =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return buckets[key] ??
        DayStats(
            date: d,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            mealCount: 0);
  });
});

// ── Weekly feeling data ──────────────────────────────────────────────────────
//
// Returns daily average energy and mood ratings for the last 7 local calendar
// days. Days with no ratings have null values — rendered as gaps in the chart
// so the absence of a rating is visually distinct from a low rating of 1.

class DayFeeling {
  final DateTime date;
  final double? avgEnergy; // 1–5, null when no ratings that day
  final double? avgMood; // 1–5, null when no ratings that day
  final int ratedMeals;

  const DayFeeling({
    required this.date,
    required this.avgEnergy,
    required this.avgMood,
    required this.ratedMeals,
  });
}

final weeklyFeelingProvider = FutureProvider<List<DayFeeling>>((ref) async {
  final authAsync = ref.watch(authStateProvider);
  final session = authAsync.valueOrNull?.session;
  if (session == null) return _emptyFeelingWeek();

  final client = Supabase.instance.client;
  final userId = session.user.id;

  final today = DateTime.now();
  final windowStart = DateTime(today.year, today.month, today.day - 6).toUtc();
  final windowEnd = DateTime(today.year, today.month, today.day + 1).toUtc();

  // Only fetch rows that have a non-null feeling column.
  final rows = await client
      .from('meal_logs')
      .select('logged_at, feeling')
      .eq('user_id', userId)
      .gte('logged_at', windowStart.toIso8601String())
      .lt('logged_at', windowEnd.toIso8601String())
      .not('feeling', 'is', null);

  // Bucket energy/mood sums by local calendar day.
  final Map<String, List<int>> energyByDay = {};
  final Map<String, List<int>> moodByDay = {};

  for (final row in (rows as List<dynamic>)) {
    final loggedAt = DateTime.parse(row['logged_at'] as String).toLocal();
    final key =
        '${loggedAt.year}-${loggedAt.month.toString().padLeft(2, '0')}-${loggedAt.day.toString().padLeft(2, '0')}';
    final feeling = row['feeling'] as Map<String, dynamic>?;
    if (feeling == null) continue;
    final energy = (feeling['energy'] as num?)?.toInt();
    final mood = (feeling['mood'] as num?)?.toInt();
    if (energy != null) (energyByDay[key] ??= []).add(energy);
    if (mood != null) (moodByDay[key] ??= []).add(mood);
  }

  return List.generate(7, (i) {
    final d = DateTime(today.year, today.month, today.day - (6 - i));
    final key =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final energyList = energyByDay[key];
    final moodList = moodByDay[key];
    final count = (energyList?.length ?? 0) + (moodList?.length ?? 0);
    return DayFeeling(
      date: d,
      avgEnergy: energyList != null && energyList.isNotEmpty
          ? energyList.reduce((a, b) => a + b) / energyList.length
          : null,
      avgMood: moodList != null && moodList.isNotEmpty
          ? moodList.reduce((a, b) => a + b) / moodList.length
          : null,
      ratedMeals: count,
    );
  });
});

List<DayFeeling> _emptyFeelingWeek() {
  final today = DateTime.now();
  return List.generate(
    7,
    (i) => DayFeeling(
      date: DateTime(today.year, today.month, today.day - (6 - i)),
      avgEnergy: null,
      avgMood: null,
      ratedMeals: 0,
    ),
  );
}

List<DayStats> _emptyWeek() {
  final today = DateTime.now();
  return List.generate(
    7,
    (i) => DayStats(
      date: DateTime(today.year, today.month, today.day - (6 - i)),
      calories: 0,
      protein: 0,
      carbs: 0,
      fat: 0,
      mealCount: 0,
    ),
  );
}

// ── Water tracking ──────────────────────────────────────────────────────────
// Persisted to `daily_stats` in Supabase so intake survives restarts and
// syncs across devices. UI updates are instant (optimistic); DB writes are
// fire-and-forget so a network hiccup never blocks the add/subtract action.

const _waterStepMl = 250;

final waterMlProvider = StateNotifierProvider<_WaterNotifier, int>(
  (_) => _WaterNotifier()..loadToday(),
);

class _WaterNotifier extends StateNotifier<int> {
  _WaterNotifier() : super(0);

  // Capture the calendar date at construction time so that the value loaded
  // by loadToday() and every subsequent _upsert() always refer to the same
  // DB row — even if the device crosses midnight between taps.
  final String _today = DateTime.now().toIsoDateString();

  // Debounce timer: coalesces rapid button taps into a single upsert.
  Timer? _debounce;

  /// Load today's persisted value from DB on first build.
  Future<void> loadToday() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) return;

      final row = await client
          .from('daily_stats')
          .select('water_ml')
          .eq('user_id', userId)
          .eq('stat_date', _today)
          .maybeSingle();

      // Re-check mounted after the async gap before mutating state.
      if (!mounted) return;
      state = (row?['water_ml'] as int?) ?? 0;
    } catch (_) {
      // Non-fatal — fall back to in-memory zero.
    }
  }

  void add() {
    state = state + _waterStepMl;
    _persist();
  }

  void subtract() {
    if (state >= _waterStepMl) {
      state = state - _waterStepMl;
      _persist();
    }
  }

  void reset() {
    state = 0;
    _persist();
  }

  /// Debounced persist — rapid taps (e.g. 5× in 500 ms) collapse into one
  /// upsert, preventing a burst of redundant network requests.
  void _persist() {
    _debounce?.cancel();
    // Capture the current state value now so that the upsert always writes
    // the state that was current when the last tap fired, not a later value.
    final snapshot = state;
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _upsert(snapshot, _today),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  static Future<void> _upsert(int waterMl, String statDate) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) return;

      await client.from('daily_stats').upsert(
        {
          'user_id': userId,
          'stat_date': statDate,
          'water_ml': waterMl,
        },
        onConflict: 'user_id,stat_date',
      );
    } catch (_) {
      // Non-fatal — next successful write will self-correct.
    }
  }
}

// ── Challenge scoring ────────────────────────────────────────────────────────

/// Fire-and-forget: posts the saved [log] to the `challenge-notifier` Edge
/// Function so active challenges are scored and ranked without blocking the UI.
///
/// [onComplete] — optional callback invoked after the edge function returns
/// (whether it succeeded or not). Use it to invalidate provider caches, e.g.:
///   `notifyChallenges(log, onComplete: () => ref.invalidate(myChallengesProvider))`
///
/// Silently swallows errors — a scoring failure must never surface to the user
/// because the meal has already been saved successfully.
void notifyChallenges(MealLog log, {void Function()? onComplete}) {
  unawaited(_postChallengeEvent(log, onComplete: onComplete));
}

Future<void> _postChallengeEvent(
  MealLog log, {
  void Function()? onComplete,
}) async {
  try {
    final client = Supabase.instance.client;
    final userId = client.auth.currentSession?.user.id;
    if (userId == null) return;

    await client.functions.invoke(
      'challenge-notifier',
      body: {
        'user_id': userId,
        'meal_log_id': log.id,
        'calories': log.totalCalories,
        'protein_g': log.totalProtein,
        'carbs_g': log.totalCarbs,
        'fat_g': log.totalFat,
        'logged_at': log.loggedAt.toIso8601String(),
      },
    );
  } catch (_) {
    // Non-fatal — challenge scores will self-correct on the next log.
  } finally {
    onComplete?.call();
  }
}

// ── Direct log (barcode / manual quick-add) ─────────────────────────────────

/// Saves a meal without the AI pipeline — used by barcode scan and quick-add.
/// Optimistically updates the daily chip and invalidates the history cache.
/// Returns the saved [MealLog] or null if the write fails.
Future<MealLog?> directLogMeal(
  WidgetRef ref, {
  required List<FoodItem> items,
  String? imageUrl,
}) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentSession?.user.id;
  if (userId == null || items.isEmpty) return null;

  final totalCalories = items.fold<int>(0, (s, i) => s + i.calories);
  final totalProtein  = items.fold<double>(0.0, (s, i) => s + (i.protein ?? 0));
  final totalCarbs    = items.fold<double>(0.0, (s, i) => s + (i.carbs   ?? 0));
  final totalFat      = items.fold<double>(0.0, (s, i) => s + (i.fat     ?? 0));
  final totalFiber    = items.fold<double>(0.0, (s, i) => s + (i.fiber   ?? 0));

  try {
    final response = await client.from('meal_logs').insert({
      'user_id': userId,
      'image_url': imageUrl,
      'items': items.map((e) => e.toMap()).toList(),
      'total_calories': totalCalories,
      'total_protein': totalProtein,
      'total_carbs': totalCarbs,
      'total_fat': totalFat,
      'total_fiber': totalFiber,
    }).select().single();

    final log = MealLog.fromMap(response);

    AnalyticsService.track('meal_logged', properties: {
      'source': imageUrl != null ? 'gallery' : 'barcode_or_quick_add',
      'calories': log.totalCalories,
      'item_count': items.length,
    });

    // Record to adaptive meal memory — fire-and-forget, non-fatal.
    ref
        .read(knownMealControllerProvider.notifier)
        .recordLog(items)
        .ignore();

    // Instant chip update + invalidate today's history cache.
    ref.read(logControllerProvider.notifier).optimisticallyAddLog(log);
    final today = DateTime.now();
    ref.invalidate(historyLogsProvider(
      DateTime(today.year, today.month, today.day),
    ));

    // Score any active challenges in the background — never awaited.
    // Skip if no active challenges to avoid a needless network call.
    // On completion, invalidate so the leaderboard reflects the new scores.
    final hasChallenges =
        ref.read(myChallengesProvider).valueOrNull?.isNotEmpty == true;
    if (hasChallenges) {
      notifyChallenges(log, onComplete: () {
        try {
          ref.invalidate(myChallengesProvider);
        } catch (_) {}
      });
    }

    return log;
  } catch (_) {
    return null;
  }
}

// ── Meal deletion ────────────────────────────────────────────────────────────

/// Deletes a meal log by ID, then invalidates both the history cache for
/// that day and today's running totals so the chip stays accurate.
Future<void> deleteMealLog(
  WidgetRef ref,
  String logId,
  DateTime loggedAt,
) async {
  await Supabase.instance.client
      .from('meal_logs')
      .delete()
      .eq('id', logId);

  // Invalidate the history cache for that day.
  ref.invalidate(historyLogsProvider(
    DateTime(loggedAt.year, loggedAt.month, loggedAt.day),
  ));

  // If it was today, also refresh the camera chip totals.
  final today = DateTime.now();
  if (loggedAt.year == today.year &&
      loggedAt.month == today.month &&
      loggedAt.day == today.day) {
    ref.read(logControllerProvider.notifier).refresh();
  }
}
