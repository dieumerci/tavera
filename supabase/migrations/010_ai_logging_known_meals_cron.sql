-- ============================================================
-- Tavera — Migration 010: AI request logging, known-meal backfill,
--                          weekly coaching cron
-- Run after 009_products_table.sql
-- ============================================================

-- ── ai_request_logs ────────────────────────────────────────────────────────────
-- Anonymised log of AI API requests for cost tracking and model improvement.
-- Deliberately contains NO user_id — fully de-identified by design.
-- Rows are written by Edge Functions using the service role key.
create table if not exists public.ai_request_logs (
  id             uuid         primary key default gen_random_uuid(),
  function_name  text         not null,
  model          text         not null,
  latency_ms     int,
  success        boolean      not null default true,
  error_code     text,
  created_at     timestamptz  not null default now()
);

-- Support per-function cost dashboards (query by function + calendar day).
create index if not exists ai_request_logs_fn_day
  on public.ai_request_logs (function_name, created_at desc);

-- ── _djb2_hash() ──────────────────────────────────────────────────────────────
-- Reproduces the djb2 hash used by Flutter's KnownMealController._fingerprint().
-- Keeping the algorithm identical means backfilled known_meals rows share the
-- same fingerprint as incrementally-inserted rows, so the Dashboard chip
-- deduplication constraint fires correctly on future logs.
--
-- Dart source reference:
--   hash = ((hash << 5) + hash + rune) & 0xFFFFFFFF  ≡  (hash * 33 + cp) & mask
-- PostgreSQL's ascii() returns the Unicode codepoint, matching Dart's .runes.
create or replace function public._djb2_hash(s text)
returns text
language plpgsql
immutable strict
as $$
declare
  hash bigint := 5381;
  i    int;
begin
  for i in 1..char_length(s) loop
    hash := ((hash * 33) + ascii(substring(s from i for 1))) & 4294967295;
  end loop;
  return lpad(to_hex(hash), 8, '0');
end;
$$;

-- ── _known_meal_fingerprint() ─────────────────────────────────────────────────
-- Derives the deduplication fingerprint from a meal_log.items JSONB array.
-- Algorithm: extract item names → lowercase + trim → sort → join with '|' →
--            djb2-hash. Mirrors KnownMealController._fingerprint() exactly.
create or replace function public._known_meal_fingerprint(items jsonb)
returns text
language sql
immutable strict
as $$
  select public._djb2_hash(
    coalesce(
      (
        select string_agg(lower(trim(n)), '|' order by lower(trim(n)))
        from   jsonb_array_elements(items) as elem,
               lateral (select elem->>'name' as n) as sub
        where  sub.n is not null and trim(sub.n) <> ''
      ),
      ''
    )
  );
$$;

-- ── backfill_known_meals() ────────────────────────────────────────────────────
-- Scans meal_logs and promotes any item-combination logged ≥ 3 times into
-- known_meals so existing users immediately see one-tap re-logging chips.
--
-- Safe to re-run: ON CONFLICT only updates occurrence_count and last_logged_at,
-- never overwriting a name the user has already customised.
--
-- Returns the number of rows upserted (useful for observability in cron logs).
create or replace function public.backfill_known_meals()
returns int
language plpgsql
security definer
as $$
declare
  rec          record;
  meal_name    text;
  total_count  int := 0;
begin
  for rec in
    select
      m.user_id,
      public._known_meal_fingerprint(m.items)           as fingerprint,
      -- Items snapshot from the most-recent occurrence (freshest portion sizes).
      (array_agg(m.items order by m.logged_at desc))[1] as items,
      -- Average calories gives a realistic one-tap preview value.
      round(avg(m.total_calories))::int                  as avg_calories,
      count(*)::int                                      as occurrence_count,
      max(m.logged_at)                                   as last_logged_at
    from   public.meal_logs m
    where  jsonb_array_length(m.items) > 0
    group  by m.user_id, public._known_meal_fingerprint(m.items)
    having count(*) >= 3
  loop
    -- Human-readable name: first 1–3 item names, title-cased and comma-joined.
    select string_agg(initcap(trim(n)), ', ' order by ord)
    into   meal_name
    from (
      select elem->>'name'  as n,
             ordinality     as ord
      from   jsonb_array_elements(rec.items) with ordinality as t(elem, ordinality)
      where  (elem->>'name') is not null
         and trim(elem->>'name') <> ''
      limit  3
    ) sub;

    meal_name := coalesce(meal_name, 'Meal');

    insert into public.known_meals
      (user_id, name, fingerprint, items, total_calories, occurrence_count, last_logged_at)
    values
      (rec.user_id, meal_name, rec.fingerprint, rec.items,
       rec.avg_calories, rec.occurrence_count, rec.last_logged_at)
    on conflict (user_id, fingerprint) do update
      set occurrence_count = greatest(known_meals.occurrence_count, excluded.occurrence_count),
          last_logged_at   = greatest(known_meals.last_logged_at,   excluded.last_logged_at);

    total_count := total_count + 1;
  end loop;

  return total_count;
end;
$$;

-- Run immediately so existing users get their known-meal chips right away.
select public.backfill_known_meals();

-- ── pg_cron schedules ─────────────────────────────────────────────────────────
-- Prerequisites (enable in Supabase Dashboard → Database → Extensions):
--   • pg_cron
--   • pg_net
--
-- Also add two Vault secrets (Dashboard → Database → Vault):
--   • supabase_project_url  → e.g. https://xxxx.supabase.co
--   • service_role_key      → your project's service_role JWT
--
-- The DO block is fully idempotent and skips silently when prerequisites are
-- absent, so this migration is safe to run in any environment.
do $$
begin
  -- Guard: only schedule if both extensions are available.
  if not (
    exists (select 1 from pg_extension where extname = 'pg_cron')
    and exists (select 1 from pg_extension where extname = 'pg_net')
  ) then
    raise notice 'pg_cron / pg_net not enabled — skipping cron schedule registration.';
    return;
  end if;

  -- ── Nightly known-meal backfill ─────────────────────────────────────────────
  -- Runs the SQL-only backfill function at 02:00 UTC daily.
  -- No network call needed — pure Postgres.
  begin
    perform cron.unschedule('nightly-known-meal-backfill');
  exception when others then null; end;

  perform cron.schedule(
    'nightly-known-meal-backfill',
    '0 2 * * *',
    $cron$ select public.backfill_known_meals(); $cron$
  );

  -- ── Weekly coaching insights (Monday 08:00 UTC) ─────────────────────────────
  -- Calls generate-coaching with trigger:"weekly_cron" so the Edge Function
  -- fetches all qualifying premium users and generates insights in one batch.
  begin
    perform cron.unschedule('weekly-coaching-insights');
  exception when others then null; end;

  perform cron.schedule(
    'weekly-coaching-insights',
    '0 8 * * 1',
    $cron$
      select net.http_post(
        url     := (
          select decrypted_secret
          from   vault.decrypted_secrets
          where  name = 'supabase_project_url'
        ) || '/functions/v1/generate-coaching',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || (
            select decrypted_secret
            from   vault.decrypted_secrets
            where  name = 'service_role_key'
          )
        ),
        body    := '{"trigger":"weekly_cron"}'::jsonb
      );
    $cron$
  );

end;
$$;
