-- ============================================================
-- Tavera — Migration 009: Products curated database
-- Run after 008_fiber_net_carbs.sql
-- ============================================================
--
-- Enables the product identification fallback pipeline:
--   1. Barcode lookup     — barcodes[] GIN-indexed array
--   2. Alias matching     — aliases[]  GIN-indexed array
--   3. OCR text fallback  — brand + canonical_name ilike search
--
-- Products are publicly readable (anon/authenticated SELECT).
-- INSERT / UPDATE restricted to service role for data integrity.
--
-- Three companion RPC functions give the Dart layer a clean,
-- injectable API and avoid PostgREST array-filter syntax issues.
-- ============================================================

-- ── Table ──────────────────────────────────────────────────────────────────

create table if not exists public.products (
  id                  uuid        primary key default gen_random_uuid(),
  brand               text        not null,
  canonical_name      text        not null,
  aliases             text[]      not null default '{}',
  barcodes            text[]      not null default '{}',

  -- Liquid: measurements in ml
  size_ml             float8,
  calories_per_100ml  float8,
  serving_size_ml     float8,

  -- Solid: measurements in grams
  size_g              float8,
  calories_per_100g   float8,
  serving_size_g      float8,

  -- Per-100-unit macros (unit matches liquid vs solid branch)
  protein_per_100     float8,
  carbs_per_100       float8,
  fat_per_100         float8,
  fiber_per_100       float8,

  -- Metadata
  region              text,
  source              text        not null default 'manual',
  confidence          float8      not null default 1.0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ── Indexes ───────────────────────────────────────────────────────────────

-- Fast element-in-array lookup: WHERE 'barcode' = ANY(barcodes)
create index if not exists products_barcodes_gin
  on public.products using gin(barcodes);

-- Fast element-in-array lookup: WHERE 'alias' = ANY(aliases)
create index if not exists products_aliases_gin
  on public.products using gin(aliases);

-- Brand + canonical name case-insensitive search
create index if not exists products_brand_name_lower
  on public.products (lower(brand), lower(canonical_name));

-- ── RLS ───────────────────────────────────────────────────────────────────

alter table public.products enable row level security;

create policy "products_public_read"
  on public.products for select
  using (true);

-- ── RPC helpers ───────────────────────────────────────────────────────────
-- Called by Dart ProductMatchingService (SupabaseProductMatchingService).
-- security definer lets the anon role call them without further grants.

create or replace function find_product_by_barcode(p_barcode text)
  returns setof public.products
  language sql stable security definer as
$$
  select * from public.products
  where p_barcode = any(barcodes)
  limit 1;
$$;

create or replace function find_product_by_alias(p_alias text)
  returns setof public.products
  language sql stable security definer as
$$
  select * from public.products
  where p_alias = any(aliases)
  limit 1;
$$;

-- Size-aware brand + name search; results ordered by proximity to p_size_ml.
-- p_size_ml is optional — pass null to skip size sorting.
create or replace function search_products_by_brand_name(
  p_brand    text,
  p_name     text,
  p_size_ml  float8 default null
)
  returns setof public.products
  language sql stable security definer as
$$
  select * from public.products
  where brand          ilike '%' || p_brand || '%'
    and canonical_name ilike '%' || p_name  || '%'
  order by
    case
      when p_size_ml is not null
      then abs(coalesce(size_ml, 99999) - p_size_ml)
      else 0
    end
  limit 5;
$$;

-- ── Seed: Sanpellegrino Melograno & Arancia 330 ml ────────────────────────
-- Canonical failing case from the product-identification bug report.
-- 38 kcal / 100 ml → 125 kcal per 330 ml can.
--
-- Aliases cover:
--   Italian label text  : "Melograno e Arancia"
--   English label text  : "Pomegranate & Orange", "Pomegranate and Orange"
--   Full product title  : "Sparkling Pomegranate & Orange"
--   Italian full title  : "Sparkling Melograno & Arancia"
--
-- Barcodes:
--   8002270105036  — Italy EAN-13 (primary, 330 ml can)
--   800227010503   — 12-digit truncated variant seen on some imports
--   8002270105043  — alternate batch barcode (select markets)

insert into public.products (
  brand,
  canonical_name,
  aliases,
  barcodes,
  size_ml,
  calories_per_100ml,
  serving_size_ml,
  protein_per_100,
  carbs_per_100,
  fat_per_100,
  fiber_per_100,
  region,
  source,
  confidence
) values (
  'Sanpellegrino',
  'Melograno & Arancia',
  array[
    'Melograno e Arancia',
    'Pomegranate & Orange',
    'Pomegranate and Orange',
    'Sparkling Pomegranate & Orange',
    'Sparkling Melograno & Arancia'
  ],
  array[
    '8002270105036',
    '800227010503',
    '8002270105043'
  ],
  330,
  38,
  330,
  0,
  9.3,
  0,
  0,
  'IT',
  'manual',
  1.0
) on conflict do nothing;
