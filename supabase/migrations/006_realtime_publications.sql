-- ============================================================
-- Tavera — Migration 006: Enable Realtime on key tables
-- Run after 005_rpc_and_constraints.sql
--
-- Required for Supabase .stream() in the Flutter app to push
-- live updates to clients (e.g. subscription_tier changes in
-- profiles, challenge leaderboard updates, coaching insights).
-- ============================================================

-- Add tables to the supabase_realtime publication so Postgres
-- change events are broadcast to connected Realtime clients.
-- The `alter publication ... add table` form is idempotent-safe
-- when wrapped in a DO block.

do $$
begin
  -- profiles: subscription tier changes reflect immediately in-app
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

  -- coaching_insights: new weekly insights appear without app restart
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'coaching_insights'
  ) then
    alter publication supabase_realtime add table public.coaching_insights;
  end if;

  -- challenge_participants: leaderboard ranks update live during challenges
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'challenge_participants'
  ) then
    alter publication supabase_realtime add table public.challenge_participants;
  end if;
end;
$$;
