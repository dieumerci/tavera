-- ============================================================
-- Tavera — Fix RLS Policies (safe re-run)
-- Run this in Supabase SQL Editor if you see "Permission denied"
-- when logging a meal. It drops and recreates all policies so
-- partial-migration state can't leave access permanently blocked.
-- ============================================================

-- ── Drop all existing policies first (idempotent) ──────────

-- profiles
drop policy if exists "profiles: select own"  on public.profiles;
drop policy if exists "profiles: insert own"  on public.profiles;
drop policy if exists "profiles: update own"  on public.profiles;

-- meal_logs
drop policy if exists "meal_logs: select own" on public.meal_logs;
drop policy if exists "meal_logs: insert own" on public.meal_logs;
drop policy if exists "meal_logs: update own" on public.meal_logs;
drop policy if exists "meal_logs: delete own" on public.meal_logs;

-- known_meals
drop policy if exists "known_meals: select own" on public.known_meals;
drop policy if exists "known_meals: insert own" on public.known_meals;
drop policy if exists "known_meals: update own" on public.known_meals;
drop policy if exists "known_meals: delete own" on public.known_meals;

-- storage.objects (meal-images bucket)
drop policy if exists "meal-images: users upload own folder" on storage.objects;
drop policy if exists "meal-images: public read"             on storage.objects;
drop policy if exists "meal-images: users delete own"        on storage.objects;

-- ── Ensure RLS is enabled on all tables ───────────────────
alter table public.profiles    enable row level security;
alter table public.meal_logs   enable row level security;
alter table public.known_meals enable row level security;

-- ── Recreate profiles policies ─────────────────────────────
create policy "profiles: select own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles: insert own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles: update own"
  on public.profiles for update
  using (auth.uid() = id);

-- ── Recreate meal_logs policies ────────────────────────────
create policy "meal_logs: select own"
  on public.meal_logs for select
  using (auth.uid() = user_id);

create policy "meal_logs: insert own"
  on public.meal_logs for insert
  with check (auth.uid() = user_id);

create policy "meal_logs: update own"
  on public.meal_logs for update
  using (auth.uid() = user_id);

create policy "meal_logs: delete own"
  on public.meal_logs for delete
  using (auth.uid() = user_id);

-- ── Recreate known_meals policies ─────────────────────────
create policy "known_meals: select own"
  on public.known_meals for select
  using (auth.uid() = user_id);

create policy "known_meals: insert own"
  on public.known_meals for insert
  with check (auth.uid() = user_id);

create policy "known_meals: update own"
  on public.known_meals for update
  using (auth.uid() = user_id);

create policy "known_meals: delete own"
  on public.known_meals for delete
  using (auth.uid() = user_id);

-- ── Recreate storage bucket + policies ────────────────────
insert into storage.buckets (id, name, public)
values ('meal-images', 'meal-images', true)
on conflict do nothing;

create policy "meal-images: users upload own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "meal-images: public read"
  on storage.objects for select
  using (bucket_id = 'meal-images');

create policy "meal-images: users delete own"
  on storage.objects for delete
  using (
    bucket_id = 'meal-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ── Repair missing profile rows ────────────────────────────
-- Users who signed up before the trigger was created (or whose
-- trigger insert failed) will have no profiles row. This inserts
-- one for every auth user that is missing one, using their email
-- and a default 2000 kcal goal.
insert into public.profiles (id, email)
select id, email
from auth.users
where id not in (select id from public.profiles)
on conflict (id) do nothing;

-- ── Verify: run this SELECT to confirm policies are in place ─
-- select tablename, policyname, cmd
-- from pg_policies
-- where schemaname = 'public'
-- order by tablename, cmd;
