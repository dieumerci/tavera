-- ============================================================
-- Tavera — Phase 2 Tables
-- Run after 001_initial_schema.sql and 002_body_stats.sql
-- ============================================================

-- ── coaching_insights ─────────────────────────────────────────
-- AI-generated weekly coaching insights produced by the
-- `generate-coaching` Edge Function.
create table if not exists public.coaching_insights (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  week_start  date not null,
  headline    text not null,
  body        text not null,
  category    text not null default 'general'
                check (category in ('calories','macros','consistency','hydration','general')),
  is_read     boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (user_id, week_start, category)
);

create index if not exists coaching_insights_user_week
  on public.coaching_insights (user_id, week_start desc);

alter table public.coaching_insights enable row level security;

create policy "coaching_insights: select own"
  on public.coaching_insights for select
  using (auth.uid() = user_id);

create policy "coaching_insights: insert own"
  on public.coaching_insights for insert
  with check (auth.uid() = user_id);

create policy "coaching_insights: update own"
  on public.coaching_insights for update
  using (auth.uid() = user_id);

-- Edge Functions insert rows on behalf of the user — allow service_role.
-- (Service-role bypass RLS by default; this comment documents intent.)

-- ── challenges ───────────────────────────────────────────────
create table if not exists public.challenges (
  id            uuid primary key default gen_random_uuid(),
  creator_id    uuid references auth.users(id) on delete cascade not null,
  title         text not null,
  description   text not null default '',
  type          text not null default 'custom'
                  check (type in ('calorie_budget','streak','macro_target','custom')),
  target_value  numeric(10,2) not null default 0,
  start_date    date not null,
  end_date      date not null,
  is_public     boolean not null default true,
  invite_code   text unique,   -- 6-char code for private challenges
  created_at    timestamptz not null default now(),
  check (end_date >= start_date)
);

create index if not exists challenges_public_active
  on public.challenges (is_public, start_date, end_date)
  where is_public = true;

alter table public.challenges enable row level security;

-- Public challenges readable by anyone authenticated.
create policy "challenges: select public or own"
  on public.challenges for select
  using (
    auth.uid() is not null
    and (is_public = true or auth.uid() = creator_id)
  );

create policy "challenges: insert own"
  on public.challenges for insert
  with check (auth.uid() = creator_id);

create policy "challenges: update own"
  on public.challenges for update
  using (auth.uid() = creator_id);

create policy "challenges: delete own"
  on public.challenges for delete
  using (auth.uid() = creator_id);

-- ── challenge_participants ───────────────────────────────────
create table if not exists public.challenge_participants (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid references public.challenges(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  display_name  text not null default 'Anonymous',
  avatar_url    text,
  score         numeric(10,2) not null default 0,
  streak_days   int not null default 0,
  rank          int not null default 0,
  joined_at     timestamptz not null default now(),
  unique (challenge_id, user_id)
);

create index if not exists challenge_participants_challenge
  on public.challenge_participants (challenge_id, rank);

alter table public.challenge_participants enable row level security;

-- Participants are visible to everyone in the same challenge.
create policy "challenge_participants: select"
  on public.challenge_participants for select
  using (
    auth.uid() is not null
    and exists (
      select 1 from public.challenge_participants cp
      where cp.challenge_id = challenge_participants.challenge_id
        and cp.user_id = auth.uid()
    )
  );

create policy "challenge_participants: insert own"
  on public.challenge_participants for insert
  with check (auth.uid() = user_id);

create policy "challenge_participants: update own"
  on public.challenge_participants for update
  using (auth.uid() = user_id);

create policy "challenge_participants: delete own"
  on public.challenge_participants for delete
  using (auth.uid() = user_id);

-- ── challenge_events ────────────────────────────────────────
create table if not exists public.challenge_events (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid references public.challenges(id) on delete cascade not null,
  user_id       uuid references auth.users(id) on delete cascade not null,
  event_type    text not null
                  check (event_type in ('meal_logged','goal_hit','streak_milestone','joined')),
  payload       jsonb not null default '{}',
  created_at    timestamptz not null default now()
);

create index if not exists challenge_events_challenge_user
  on public.challenge_events (challenge_id, user_id, created_at desc);

alter table public.challenge_events enable row level security;

create policy "challenge_events: select participants"
  on public.challenge_events for select
  using (
    auth.uid() is not null
    and exists (
      select 1 from public.challenge_participants cp
      where cp.challenge_id = challenge_events.challenge_id
        and cp.user_id = auth.uid()
    )
  );

create policy "challenge_events: insert own"
  on public.challenge_events for insert
  with check (auth.uid() = user_id);

-- ── meal_plans ──────────────────────────────────────────────
-- Full week meal plan. The `days` column stores all PlannedMeal data
-- so the Flutter app can read the entire plan in one query.
create table if not exists public.meal_plans (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references auth.users(id) on delete cascade not null,
  week_start      date not null,
  calorie_target  int not null default 2000,
  days            jsonb not null default '[]',
  ai_notes        text,
  created_at      timestamptz not null default now(),
  unique (user_id, week_start)
);

create index if not exists meal_plans_user_week
  on public.meal_plans (user_id, week_start desc);

alter table public.meal_plans enable row level security;

create policy "meal_plans: select own"
  on public.meal_plans for select
  using (auth.uid() = user_id);

create policy "meal_plans: insert own"
  on public.meal_plans for insert
  with check (auth.uid() = user_id);

create policy "meal_plans: update own"
  on public.meal_plans for update
  using (auth.uid() = user_id);

create policy "meal_plans: delete own"
  on public.meal_plans for delete
  using (auth.uid() = user_id);

-- ── grocery_lists ───────────────────────────────────────────
create table if not exists public.grocery_lists (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete cascade not null,
  meal_plan_id  uuid references public.meal_plans(id) on delete set null,
  week_start    date not null,
  items         jsonb not null default '[]',
  is_shared     boolean not null default false,
  -- Short token used to generate shareable links / Instacart integration.
  share_token   text unique default substring(gen_random_uuid()::text, 1, 12),
  created_at    timestamptz not null default now()
);

create index if not exists grocery_lists_user_week
  on public.grocery_lists (user_id, week_start desc);

-- Share token lookup (used by delivery integration endpoint).
create index if not exists grocery_lists_share_token
  on public.grocery_lists (share_token)
  where is_shared = true;

alter table public.grocery_lists enable row level security;

create policy "grocery_lists: select own or shared"
  on public.grocery_lists for select
  using (
    auth.uid() = user_id
    or is_shared = true
  );

create policy "grocery_lists: insert own"
  on public.grocery_lists for insert
  with check (auth.uid() = user_id);

create policy "grocery_lists: update own"
  on public.grocery_lists for update
  using (auth.uid() = user_id);

create policy "grocery_lists: delete own"
  on public.grocery_lists for delete
  using (auth.uid() = user_id);
