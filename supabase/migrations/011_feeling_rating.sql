-- Migration 011: After-meal feeling rating
--
-- Adds an optional `feeling` JSONB column to meal_logs so users can record
-- how they felt after eating (energy 1–5, mood 1–5). This seeds the data
-- needed for the Phase 3 Mood-Energy-Food Correlation Engine.
--
-- Structure of the feeling column:
--   { "energy": 1-5, "mood": 1-5 }
--
-- Null means the user has not rated the meal (pre-feature logs, or skipped).
-- Both keys are optional within the JSON — the client only writes keys the
-- user actually set.

ALTER TABLE meal_logs
  ADD COLUMN IF NOT EXISTS feeling jsonb;

-- Partial index speeds up the correlation-engine query that aggregates
-- only meals with feeling data (skips the many NULL rows efficiently).
CREATE INDEX IF NOT EXISTS idx_meal_logs_feeling
  ON meal_logs (user_id, logged_at)
  WHERE feeling IS NOT NULL;

COMMENT ON COLUMN meal_logs.feeling IS
  'Optional after-meal rating. JSON keys: energy (1-5), mood (1-5). '
  'Null = not rated. Used by the Mood-Energy correlation engine in Phase 3.';
