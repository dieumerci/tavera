-- ============================================================
-- Tavera — Migration 008: Fiber tracking for net carbs
-- Run after 007_fasting_net_carbs.sql
-- ============================================================
--
-- Adds `total_fiber` to meal_logs so the app can compute
-- net carbs (carbs − fiber) when the user enables the toggle
-- in Profile → Goals → Net Carbs Mode.
--
-- Fiber is populated by the `analyse-meal` Edge Function
-- (updated to return `fiber_g` per item in the same call).
-- Legacy rows will have total_fiber = NULL, which the app
-- treats as "no fiber data → show total carbs unchanged".
-- ============================================================

alter table public.meal_logs
  add column if not exists total_fiber float8;

-- Index is intentionally omitted — fiber is only read via
-- the same row fetch that already scans by user_id + logged_at.
