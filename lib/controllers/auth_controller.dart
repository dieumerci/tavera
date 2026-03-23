import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

/// Raw Supabase auth state stream.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Shorthand for the current session.
final currentSessionProvider = Provider<Session?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.session;
});

/// Current user's profile from the `profiles` table.
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;

  final response = await Supabase.instance.client
      .from('profiles')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();

  if (response == null) return null;
  return UserProfile.fromMap(response);
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
    String name,
  ) async {
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
