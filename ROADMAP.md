# TAVERA — Product Roadmap & Development Checklist

**Document Version:** 1.1
**Last Updated:** March 24, 2026
**Status:** Phase 0 Complete · Phase 1 In Progress
**Author:** Dee (Founder)

> **Legend:** ✅ Complete · 🔄 In Progress · ⏭ Deferred · ❌ Not started

---

## Roadmap Philosophy

This roadmap is structured as five sequential phases, each with a clear objective, a definition of done, and a detailed checklist. The phases are designed to be completed by a solo developer or a small team of two to three people. Each phase should take approximately eight to twelve weeks, meaning the full roadmap spans roughly twelve to fifteen months from start to public launch through feature maturity.

The most important principle guiding this roadmap is that Phase 1 must be shipped before any work begins on Phase 2. Feature creep kills solo-developer projects. Phase 1 is deliberately constrained to the minimum product that validates Tavera's core hypothesis: that camera-first calorie logging retains users better than database-search-first logging. If that hypothesis fails, nothing built in Phase 2 through 5 matters.

---

## Phase 0 — Project Setup & Foundation (Weeks 1–2)

**Objective:** Establish all accounts, tooling, development environment, and project scaffolding so that actual feature development can begin without interruption.

**Definition of Done:** A Flutter app runs on both iOS simulator and Android emulator, connects to a Supabase instance, and a user can sign up, log in, and see an empty camera screen.

**Status: ✅ COMPLETE**

### Checklist

- [ ] Register domain name (tavera.app or gettavera.com)
- [ ] Create a GitHub repository with branch protection on `main`, require PR reviews
- ✅ Create the Flutter project
- ✅ Configure `analysis_options.yaml` with linting rules
- ✅ Set up the folder structure (MCV: Models / Controllers / Views — adapted from the architecture doc)
- ✅ Install and configure all Phase 1 Flutter packages in `pubspec.yaml` (supabase_flutter, flutter_riverpod, go_router, camera, image, cached_network_image, intl)
- ✅ Create a Supabase project
- ✅ Initialise `supabase/` directory in the project (migrations + functions)
- ✅ Write the initial database migration: `profiles`, `meal_logs`, `known_meals` tables
- ✅ Apply the migration to the Supabase project
- ✅ Configure Supabase Auth with email/password
- [ ] Configure Apple Sign-In and Google Sign-In providers _(Phase 1 remaining)_
- ✅ Set up Row-Level Security policies on all tables
- ✅ Create Supabase Storage bucket `meal-images` with RLS policies
- [ ] Import USDA FoodData Central dataset into the foods table _(deferred — using OpenAI for nutrition estimation instead of DB lookup in MVP)_
- [ ] Import Open Food Facts barcode dataset _(deferred — barcode scanning is Phase 1 remaining)_
- [ ] Create `.env` / `.env.example` files _(keys currently hardcoded in app_config.dart — move to --dart-define before production build)_
- [ ] Set up Sentry for crash reporting _(Phase 1 remaining)_
- [ ] Set up Firebase project for FCM push notifications _(Phase 1 remaining)_
- [ ] Register Apple Developer Program account
- [ ] Register Google Play Developer account
- ✅ Create the basic app theme (colours, typography, spacing, dark mode)
- ✅ Implement the authentication flow: sign up, log in, sign out
- [ ] Build the full onboarding screen sequence: goal selection, body stats, calorie target calculation _(currently sign up / sign in only — goal stats deferred)_
- ✅ Verify the app runs correctly on iOS device
- [ ] Write a basic integration test for the auth flow _(unit tests for models written, auth integration test pending)_

---

## Phase 1 — Core MVP: Camera-First Calorie Logging (Weeks 3–12)

**Objective:** Build the complete camera-to-confirmed-meal-log pipeline with AI food recognition, daily calorie dashboard, and meal history. This is the product that goes to beta testers.

**Definition of Done:** A user can open the app, point their camera at a meal, receive AI-generated calorie and macro estimates, confirm the log, and see their daily calorie progress update in real time. The user can review their meal history for the past 30 days.

**Status: 🔄 IN PROGRESS — Core pipeline working end-to-end**

> **Architecture note:** The MVP uses OpenAI GPT-4o Vision directly for food recognition rather than Google Cloud Vision + USDA database lookup as originally specified. This reduced time-to-working pipeline from weeks to days. The Google Cloud Vision + fuzzy DB-match approach remains the plan for Phase 3 (custom model) once meal photo data is accumulated.

### Camera & Photo Capture

- ✅ Build the camera capture screen with the `camera` package as the **home screen**
- ✅ Implement viewfinder overlay with a subtle plate guide circle
- ✅ Add a capture button with haptic feedback
- ✅ Implement gallery import fallback via `image_picker`
- ✅ Build client-side image compression (longest side ≤ 1024px, 85% JPEG quality) — runs in a `compute` isolate to keep UI responsive
- ✅ Add loading state: white flash on capture, full-screen overlay with step labels ("Uploading photo…" / "Identifying food…"), animated skeleton in review sheet
- ✅ Handle camera permission requests gracefully with explanation dialogs — branded rationale screen + "Open Settings" deep-link

### AI Food Recognition Pipeline

- ✅ Write the Supabase Edge Function `analyse-meal` in TypeScript/Deno
- ✅ Implement image upload to Supabase Storage
- ⏭ Integrate Google Cloud Vision API _(deferred — using OpenAI GPT-4o Vision; GCV to be evaluated in Phase 3)_
- ⏭ Build fuzzy matching against foods database via `pg_trgm` _(deferred — OpenAI returns portion + nutrition estimates directly)_
- ⏭ Implement rules-based portion estimation _(deferred — GPT-4o handles portion estimation in prompt)_
- ✅ Build response assembly returning structured meal estimates (name, portion, calories, macros, confidence)
- ✅ Handle error cases: unrecognised food, API timeout, network failure — with debug-level error messages surfaced in UI
- [ ] Add fallback to manual food search when AI confidence is below 0.5
- [ ] Log all AI requests and responses for future model improvement (anonymised)
- [ ] Test with at least 50 different meal photos across cuisines and validate accuracy

### Meal Review & Confirmation Screen

- ✅ Build the meal review bottom sheet showing identified items with calorie estimates
- ✅ Implement the portion adjustment **slider** for each food item (0.5× to 3× in 0.5× steps) — inline on the card, real-time calorie preview
- ✅ Add the ability to remove an incorrectly identified item
- ✅ Add the ability to manually add a missing item — inline in the review sheet via "+ Add missing item"
- ✅ Implement the confirm button that writes `meal_logs` to Supabase
- ✅ Show a success animation after confirmation — calorie chip bounces (scale pop) when sheet dismisses after a successful save
- ✅ Calorie total updates in real time as user edits or removes items
- ✅ Confidence score indicator per food item (green / amber / red dot)

### Daily Dashboard

- ✅ Show today's total calories and logged meal count
- ✅ Linear calorie progress bar (consumed vs. daily goal)
- ✅ Build the daily calorie **progress ring** (circular) — `_RingPainter` CustomPainter in `_DailyChip`
- ✅ Build the macro breakdown bars (protein, carbs, fat) with targets — in history `_SummaryCard`
- ✅ Show today's logged meals as a scrollable list
- [ ] Display remaining calories prominently _(partially shown in history screen)_
- ✅ Add quick-add buttons for water logging (250ml increments) — `_WaterButton` in camera bottom bar
- ✅ Implement date navigation to view previous days — chevron nav + date picker in history screen
- ✅ Dashboard updates in real time when a new meal is confirmed (optimistic update)

### Meal History

- ✅ Build the meal history screen with scrollable list of today's meals
- ✅ Show meal photo thumbnails, food item names, calorie total, and timestamp
- [ ] Implement lazy loading with pagination (20 meals per page)
- ✅ Add the ability to tap a meal to view full details — `_MealDetailSheet` with photo, macros, items
- ✅ Implement meal deletion with confirmation dialog — swipe-to-delete + delete button in detail sheet
- ✅ Meal photos served via `cached_network_image`

### Barcode Scanning

- ✅ Integrate `mobile_scanner` for barcode capture — `BarcodeScanScreen` with scan-window overlay
- ⏭ Build barcode lookup against the foods table _(no local foods DB yet — using Open Food Facts directly)_
- ✅ Fall back to Open Food Facts API for barcodes not in the local database
- ✅ Display nutritional info and allow portion adjustment before logging — portion multiplier chips (0.5×–3×)

### Manual Quick-Add

- ✅ Build a simple manual entry form: meal name, estimated calories — `QuickAddSheet`
- ✅ Optional macro entry for users who know their numbers — collapsible macros row

### Push Notifications

- ✅ Implement meal-time push notification scheduling based on user timezone — `NotificationService` with timezone-aware `zonedSchedule`
- ✅ Default reminders at 8am (breakfast), 12:30pm (lunch), 7pm (dinner)
- ✅ Smart suppression: do not send notification if a meal has already been logged in that window — `ref.listen` on `logControllerProvider` reschedules after every log change
- ✅ Implement notification permission request — toggle in Profile → Notifications section; FCM wraps APNs on iOS
- [ ] Handle notification taps to deep link directly to the camera screen _(app opens to camera by default; explicit deep-link routing deferred)_

### Offline Mode

- [ ] Set up Drift (SQLite) local database with meal and food tables
- [ ] Implement offline meal logging for manual quick-add entries
- [ ] Queue offline entries for sync when connectivity returns
- [ ] Cache the user's top 200 most-logged foods locally for offline search
- [ ] Display a subtle offline indicator when connectivity is lost

### Settings & Profile

- ✅ Build the settings/profile screen with name, email, subscription tier display
- ✅ Sign out flow
- ✅ Add calorie target editor — `_GoalEditorSheet` with preset chips + slider 1200–4000 kcal
- ✅ Add body stats input (height, weight, age, sex) for BMR-based target calculation — Mifflin-St Jeor × 1.2
- [ ] Implement account deletion flow (data export, then delete)
- [ ] Add notification preference controls

### Testing & Quality

- ✅ Unit tests for `FoodItem` and `MealLog` models (serialisation round-trip)
- [ ] Unit tests for all repository classes
- [ ] Widget tests for camera, meal review, and history screens
- [ ] Integration tests for the full camera-to-log pipeline
- [ ] Manual testing on at least three physical devices (1 iOS, 2 Android)
- [ ] Load test the Edge Function with 100 concurrent requests
- [ ] Fix all critical and high-severity bugs

### Beta Release

- [ ] Set up TestFlight for iOS beta distribution
- [ ] Set up Google Play Internal Testing track for Android beta distribution
- [ ] Recruit 20–50 beta testers
- [ ] Create a feedback collection mechanism (in-app form or Typeform link)
- [ ] Monitor errors during beta
- [ ] Run beta for 2–4 weeks, collecting feedback and usage data

---

## Phase 2 — Intelligence Layer & Monetisation (Weeks 13–22)

**Objective:** Add adaptive meal memory, coaching insights, premium subscription, and paywall. This is the phase where Tavera becomes a business.

**Status: ❌ NOT STARTED**

> **Partially scaffolded:** Paywall sheet UI is built. Free-tier 3-log/day gate is enforced in `LogController`. `known_meals` table is in the database schema. These are intentionally stubbed ahead of time without blocking Phase 1.

### Adaptive Meal Memory

- [ ] Write the known meal detection query: identify meals logged 3+ times with similar food item combinations
- [ ] Build the known_meals table population logic (scheduled PostgreSQL function or Edge Function running daily)
- [ ] Implement time-of-day bucketing so known meals are offered at the right time
- [ ] Build the known meals suggestion UI: horizontal scrollable chips above the camera button
- [ ] Implement one-tap logging for known meals (confirm with single tap, no camera needed)
- [ ] Allow users to rename known meals
- [ ] Allow users to dismiss or hide known meals they no longer eat
- [ ] Track known meal usage frequency and retire meals unused for 30+ days

### AI Coaching Insights

- [ ] Write the Supabase Edge Function `generate-coaching`
- [ ] Design the OpenAI prompt template: user goals, weekly meal summary, detected patterns, nutritional gaps
- [ ] Constrain AI output to 1–3 actionable insights per week
- [ ] Implement insight categories: pattern observations, recommendations, milestones
- [ ] Schedule the Edge Function to run weekly (Monday morning per user timezone)
- [ ] Build the insights screen in the Flutter app
- [ ] Implement read/unread state for insights
- [ ] Add a badge indicator on the insights tab when new insights are available

### Subscription & Paywall

- [ ] Create a RevenueCat account and configure products
- [ ] Create subscription products in App Store Connect and Google Play Console
- [ ] Configure monthly ($4.99/month) and annual options _(pricing per PRICING.md)_
- [ ] Implement 7-day free trial for annual plan
- [ ] Integrate `purchases_flutter` (RevenueCat SDK)
- [ ] Wire the existing `PaywallSheet` UI to RevenueCat purchase flow
- [ ] Implement subscription status checking on app launch and cache locally
- [ ] Gate premium features: coaching insights, adaptive meal memory, macro tracking, history export
- [ ] Implement subscription restoration for users who reinstall the app
- [ ] Set up RevenueCat webhooks → Supabase Edge Function for subscription status sync
- [ ] Test purchase flows on both platforms with sandbox/test accounts

### Analytics

- [ ] Set up PostHog and integrate `posthog_flutter`
- [ ] Track key events: meal_logged, camera_opened, known_meal_used, paywall_shown, subscription_started
- [ ] Build conversion funnel from onboarding → first log → day 7 retention → subscription

### Public Launch

- [ ] Prepare App Store listing: icon, screenshots, preview video, description, keywords
- [ ] Prepare Google Play listing
- [ ] Submit to Apple for App Store Review
- [ ] Submit to Google Play
- [ ] Launch publicly

---

## Phase 3 — Retention & Depth (Weeks 23–34)

**Status: ❌ NOT STARTED**

### Checklist

- [ ] Build the restaurant menu scanning feature
- [ ] Integrate Apple HealthKit and Google Health Connect for activity data import
- [ ] Implement dynamic calorie budget adjustment based on imported activity data
- [ ] Build the meal scoring system: green/yellow/red rating per meal based on goal alignment
- [ ] Implement consistency streaks that reward logging frequency
- [ ] Build the weekly summary screen with visual trends
- [ ] Add intermittent fasting timer with eating window visualisation
- [ ] Implement data export (CSV) for premium users
- [ ] Add multi-language support starting with Spanish, Portuguese, French, and Hindi
- [ ] Evaluate Google Cloud Vision + USDA database lookup to replace or supplement OpenAI Vision
- [ ] Optimise app launch time to under 2 seconds on mid-range devices

---

## Phase 4 — Meal Planning & Social (Weeks 35–46)

**Status: ❌ NOT STARTED**

### Checklist

- [ ] Build the AI meal planning engine from the user's known meals
- [ ] Implement meal plan editing: swap meals, adjust portions, regenerate days
- [ ] Generate grocery lists from meal plans
- [ ] Build the accountability partner feature: invite one person to see your daily summary
- [ ] Add GLP-1 medication tracking mode with protein-prioritised coaching
- [ ] Build the recipe import feature: paste a URL, extract ingredients, calculate nutrition
- [ ] Implement food photo quality feedback loop to improve AI accuracy

---

## Phase 5 — Professional Layer & Scale (Weeks 47–60)

**Status: ❌ NOT STARTED**

### Checklist

- [ ] Design and build the professional dashboard (web application)
- [ ] Implement professional account creation and client invitation flow
- [ ] Build the client meal log viewer for professionals with annotation capability
- [ ] Implement secure data sharing consent
- [ ] Build the professional subscription tier
- [ ] Create a corporate wellness landing page and sales materials
- [ ] Evaluate custom food recognition model training on accumulated meal photo dataset
- [ ] Explore food delivery API integrations (Uber Eats, DoorDash) for automatic meal logging

---

## Key Milestones Timeline

| Milestone | Target Date | Phase | Status |
|-----------|-------------|-------|--------|
| Project scaffolding complete | Week 2 | 0 | ✅ Done (Week 1) |
| Camera-to-calorie pipeline working end-to-end | Week 6 | 1 | ✅ Done (Week 1) |
| Image compression + permission dialogs | Week 3 | 1 | 🔄 In Progress |
| Portion slider + manual add + success animation | Week 4 | 1 | 🔄 In Progress |
| Beta release to 20–50 testers | Week 10 | 1 | ❌ |
| Beta feedback incorporated, MVP stable | Week 12 | 1 | ❌ |
| Adaptive meal memory live | Week 16 | 2 | ❌ |
| Subscription and paywall live | Week 18 | 2 | ❌ |
| Public launch on App Store and Google Play | Week 22 | 2 | ❌ |
| 1,000 registered users | Week 26 | 3 | ❌ |
| Restaurant menu scanning live | Week 28 | 3 | ❌ |
| Wearable integration live | Week 30 | 3 | ❌ |
| Meal planning engine live | Week 38 | 4 | ❌ |
| 10,000 registered users | Week 40 | 4 | ❌ |
| Professional accounts live | Week 50 | 5 | ❌ |
| First corporate wellness pilot | Week 55 | 5 | ❌ |

---

## Immediate Next Actions (Phase 1 — Sprint)

These are the next concrete engineering tasks before beta:

1. ✅ **Image compression** — `compute` isolate resizes to longest side ≤ 1024px at 85% JPEG before upload
2. ✅ **Gallery import** — `image_picker` fallback button left of the shutter; same paywall gate and AI pipeline as camera capture
3. ✅ **Portion slider** — inline on each `FoodItemCard`, 0.5× to 3× in 0.5× steps, real-time calorie preview, commits to controller on drag-end
4. ✅ **Success animation** — calorie chip scale-bounce (elastic spring) when meal is saved
5. ✅ **Camera permission dialog** — branded explanation screen + "Open Settings" deep-link; "try again" re-runs check without restart
6. ✅ **Calorie target onboarding** — goal-picker step after sign-up (preset chips + fine-tune slider 1200–4000 kcal); editable in Profile
7. ✅ **Environment variables** — `Env` class reads `--dart-define` at compile time with dev fallbacks; `AppConfig` delegates to `Env`

---

*This document should be read alongside CONCEPT.md, ARCHITECTURE.md, PRICING.md, and the root README.md.*
