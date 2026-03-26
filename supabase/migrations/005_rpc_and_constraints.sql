-- ============================================================
-- Tavera — Migration 005: RPC helpers, constraints, RLS fixes
-- Run after 004_daily_stats.sql
-- ============================================================

-- ── increment_known_meal_count ────────────────────────────────────────────────
-- Atomically increments occurrence_count and updates last_logged_at for a
-- known_meal row identified by (user_id, fingerprint).
-- Called from Flutter's KnownMealController.recordLog() after every
-- successful meal log. Using a dedicated RPC avoids a Dart-side read-then-
-- write race and keeps the counter increment consistent.
create or replace function public.increment_known_meal_count(
  p_user_id     uuid,
  p_fingerprint text
) returns void
language plpgsql
security definer
as $$
begin
  update public.known_meals
  set occurrence_count = occurrence_count + 1,
      last_logged_at   = now()
  where user_id    = p_user_id
    and fingerprint = p_fingerprint;
end;
$$;

-- ── grocery_lists: upsert constraint ────────────────────────────────────────
-- The generate-meal-plan edge function upserts on (user_id, meal_plan_id).
-- Without this unique constraint every plan regeneration inserts a new row
-- instead of updating the existing one, accumulating duplicates.
alter table public.grocery_lists
  add constraint if not exists grocery_lists_user_meal_plan_unique
  unique (user_id, meal_plan_id);

-- ── is_challenge_participant() — security-definer helper ─────────────────────
-- Wraps the participant existence check in a SECURITY DEFINER function so it
-- can be called from RLS policies without causing infinite recursion (Postgres
-- RLS policies that query the same table they protect recurse indefinitely).
-- SECURITY DEFINER means this function runs as its owner (postgres / rls-safe)
-- and bypasses RLS on the inner query, safely breaking the recursion.
create or replace function public.is_challenge_participant(
  p_challenge_id uuid,
  p_user_id      uuid
) returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1
    from public.challenge_participants
    where challenge_id = p_challenge_id
      and user_id      = p_user_id
  );
$$;

-- ── challenge_participants: fix recursive select RLS ─────────────────────────
-- Old policy: `exists (select 1 from challenge_participants cp where ...)`
-- ↑ This queried the same table the policy protects → infinite recursion.
-- New policy: delegates to the security-definer function above.
drop policy if exists "challenge_participants: select"
  on public.challenge_participants;

create policy "challenge_participants: select"
  on public.challenge_participants for select
  using (
    auth.uid() is not null
    and public.is_challenge_participant(challenge_id, auth.uid())
  );

-- ── challenges: allow participants to view private challenges ─────────────────
-- Old policy only let users see public challenges or ones they created.
-- Private-challenge participants (non-creators) were blocked from reading the
-- challenge row they joined, breaking the detail screen and leaderboard.
drop policy if exists "challenges: select public or own"
  on public.challenges;

create policy "challenges: select public or own"
  on public.challenges for select
  using (
    auth.uid() is not null
    and (
      is_public  = true
      or auth.uid() = creator_id
      or public.is_challenge_participant(id, auth.uid())
    )
  );
