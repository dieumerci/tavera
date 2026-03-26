-- ============================================================
-- Tavera — Migration 007: Intermittent Fasting + Net Carbs
-- Run after 006_realtime_publications.sql
-- ============================================================

-- ── fasting_sessions ──────────────────────────────────────
-- One row per fasting window started by the user.
-- ended_at IS NULL  →  fast is currently active.
-- ended_at IS SET   →  fast is complete / was stopped early.
create table if not exists public.fasting_sessions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  protocol    text not null
                check (protocol in ('16:8','18:6','20:4','OMAD')),
  fast_hours  int not null,
  started_at  timestamptz not null,
  target_end  timestamptz not null,
  ended_at    timestamptz,           -- null while the fast is in progress
  created_at  timestamptz not null default now()
);

-- Efficient lookup for the active-fast check on app start.
create index if not exists fasting_sessions_user_active
  on public.fasting_sessions (user_id, ended_at)
  where ended_at is null;

-- History queries: most recent first.
create index if not exists fasting_sessions_user_history
  on public.fasting_sessions (user_id, started_at desc);

alter table public.fasting_sessions enable row level security;

create policy "fasting_sessions: select own"
  on public.fasting_sessions for select
  using (auth.uid() = user_id);

create policy "fasting_sessions: insert own"
  on public.fasting_sessions for insert
  with check (auth.uid() = user_id);

create policy "fasting_sessions: update own"
  on public.fasting_sessions for update
  using (auth.uid() = user_id);

create policy "fasting_sessions: delete own"
  on public.fasting_sessions for delete
  using (auth.uid() = user_id);

-- ── profiles: net_carbs_mode ──────────────────────────────
-- When true, the app displays (carbs − fiber) instead of
-- total carbs in dashboards, history, and review sheets.
alter table public.profiles
  add column if not exists net_carbs_mode boolean not null default false;

-- ── Realtime for fasting_sessions ────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fasting_sessions'
  ) then
    alter publication supabase_realtime add table public.fasting_sessions;
  end if;
end;
$$;
