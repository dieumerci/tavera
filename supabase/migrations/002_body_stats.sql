-- ============================================================
-- Tavera — Body Stats Columns
-- Run this in the Supabase SQL Editor after 001_initial_schema.sql
-- ============================================================

alter table public.profiles
  add column if not exists weight_kg  numeric(5,1),
  add column if not exists height_cm  int,
  add column if not exists age        int,
  add column if not exists sex        text
    check (sex in ('male', 'female', 'other'));
