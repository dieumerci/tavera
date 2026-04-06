import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../models/user_profile.dart';

/// Raw Supabase auth state stream.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Shorthand for the current session.
final currentSessionProvider = Provider<Session?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.session;
});

/// Current user's profile — live stream from the `profiles` table.
///
/// Uses Supabase Realtime under the hood: emits immediately with the current
/// row, then re-emits whenever any field (including subscription_tier) changes
/// — even when updated externally via SQL or a webhook. All widgets watching
/// this provider rebuild automatically with no manual invalidation required.
///
/// Requires the `profiles` table to be included in the Supabase Realtime
/// publication (Dashboard → Database → Replication → supabase_realtime).
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return Stream.value(null);

  return Supabase.instance.client
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', session.user.id)
      .map((rows) => rows.isEmpty ? null : UserProfile.fromMap(rows.first));
});

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      // Rethrow so the UI catch block can display the error.
      rethrow;
    }
  }

  /// Returns the pending email if Supabase requires email confirmation,
  /// or null when the user is immediately signed in.
  Future<String?> signUpWithEmail(
    String email,
    String password,
    String name, {
    int calorieGoal = AppConfig.defaultCalorieGoal,
  }) async {
    state = const AsyncLoading();
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

      if (response.user != null && response.session != null) {
        // Email confirmation is disabled — user is live immediately.
        await Supabase.instance.client.from('profiles').upsert({
          'id': response.user!.id,
          'email': email,
          'name': name,
          'calorie_goal': calorieGoal,
          'onboarding_completed': true,
        });
        state = const AsyncData(null);
        return null;
      } else if (response.user != null && response.session == null) {
        // Supabase is waiting for email confirmation.
        state = const AsyncData(null);
        return email;
      }

      state = const AsyncData(null);
      return null;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
