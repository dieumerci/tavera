-- ============================================================
-- Tavera — Initial Schema
-- Run this once in the Supabase SQL Editor
-- ============================================================

-- ── profiles ──────────────────────────────────────────────────
-- Extends auth.users with app-specific fields.
-- A trigger auto-creates a row on sign-up.
create table if not exists public.profiles (
  id                    uuid references auth.users(id) on delete cascade primary key,
  email                 text,
  name                  text,
  avatar_url            text,
  calorie_goal          int not null default 2000,
  subscription_tier     text not null default 'free'
                          check (subscription_tier in ('free', 'premium')),
  onboarding_completed  boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- ── meal_logs ─────────────────────────────────────────────────
-- One row per meal capture. Items stored as JSONB array.
create table if not exists public.meal_logs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users(id) on delete cascade not null,
  image_url       text,
  logged_at       timestamptz not null default now(),
  total_calories  int not null,
  total_protein   numeric(6,1),
  total_carbs     numeric(6,1),
  total_fat       numeric(6,1),
  items           jsonb not null default '[]',
  ai_raw_response jsonb,
  created_at      timestamptz not null default now()
);

-- Index for the daily log query (user + date range)
create index if not exists meal_logs_user_date
  on public.meal_logs (user_id, logged_at desc);

-- ── known_meals ───────────────────────────────────────────────
-- Stores recurring meals for one-tap re-logging.
-- Fingerprint is a hash of sorted item names — deduplication key.
create table if not exists public.known_meals (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references auth.users(id) on delete cascade not null,
  name             text not null,
  fingerprint      text not null,
  items            jsonb not null default '[]',
  total_calories   int not null,
  occurrence_count int not null default 1,
  last_logged_at   timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  unique(user_id, fingerprint)
);

-- ── Row Level Security ────────────────────────────────────────
alter table public.profiles   enable row level security;
alter table public.meal_logs  enable row level security;
alter table public.known_meals enable row level security;

-- profiles policies
create policy "profiles: select own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles: insert own"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles: update own"
  on public.profiles for update
  using (auth.uid() = id);

-- meal_logs policies
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

-- known_meals policies
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

-- ── Storage bucket ────────────────────────────────────────────
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

-- ── Auto-create profile on sign-up ────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── updated_at auto-maintenance ───────────────────────────────
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();
