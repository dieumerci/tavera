-- Migration 012: GLP-1 medication tracking mode
--
-- Adds glp1_mode flag to profiles. When true the app:
--   • Displays calorie goal reduced by 20% (appetite suppression)
--   • Raises protein target to 1.2 g/kg body weight (muscle preservation)
--   • Routes coaching prompts through the GLP-1 variant
--
-- Column is nullable on purpose — existing rows stay NULL until the user
-- explicitly toggles the feature (NULL is treated as false in app logic).

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS glp1_mode BOOLEAN DEFAULT FALSE;
