-- ============================================================
-- Tavera — Migration 004: daily_stats
-- ============================================================
-- Persists per-user, per-day aggregate stats that are tracked
-- in-app but need to survive restarts and be available across
-- devices.
--
-- Currently used for: water intake (ml).
-- Designed to be extended with: steps, sleep, mood, etc.
-- ============================================================

create table if not exists public.daily_stats (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  -- ISO date string YYYY-MM-DD — no timezone offset, user's local day.
  stat_date   date not null,
  water_ml    int not null default 0
                check (water_ml >= 0),
  updated_at  timestamptz not null default now(),

  -- One row per user per day.
  unique (user_id, stat_date)
);

-- ── Indexes ───────────────────────────────────────────────────

-- Most common query: single user, today's date.
create index if not exists daily_stats_user_date
  on public.daily_stats (user_id, stat_date desc);

-- ── Row-level security ────────────────────────────────────────

alter table public.daily_stats enable row level security;

-- Users can read and write only their own rows.
create policy "daily_stats: own rows"
  on public.daily_stats
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ── updated_at trigger ────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Re-use the trigger function if it already exists from a prior migration.
drop trigger if exists daily_stats_set_updated_at on public.daily_stats;
create trigger daily_stats_set_updated_at
  before update on public.daily_stats
  for each row execute procedure public.set_updated_at();
