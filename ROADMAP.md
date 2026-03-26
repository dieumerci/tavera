# TAVERA — Product Roadmap & Development Checklist

**Document Version:** 1.4
**Last Updated:** March 26, 2026
**Status:** Phase 1 Complete · Phase 2 In Progress
**Author:** Dee (Founder)

> **Legend:** ✅ Complete · 🔄 In Progress · ⏭ Deferred · ❌ Not started

---

## Roadmap Philosophy

This roadmap is structured as five sequential phases, each with a clear objective, a definition of done, and a detailed checklist. The phases are designed to be completed by a solo developer or a small team of two to three people. Each phase should take approximately eight to twelve weeks, meaning the full roadmap spans roughly twelve to fifteen months from start to public launch through feature maturity.

The most important principle guiding this roadmap is that Phase 1 must be shipped before any work begins on Phase 2. Feature creep kills solo-developer projects. Phase 1 is deliberately constrained to the minimum product that validates Tavera's core hypothesis: that camera-assisted calorie logging retains users better than database-search-first logging. If that hypothesis fails, nothing built in Phase 2 through 5 matters.

**UX Direction (enforced from Phase 1 onwards):** The app opens to the Dashboard. Food capture is triggered by the + FAB in the bottom navigation bar, not by the camera as a home screen. Steps / activity tracking is explicitly out of scope for all phases unless re-evaluated by the product owner.

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
- [ ] Import Open Food Facts barcode dataset _(deferred — barcode scanning uses Open Food Facts API directly)_
- [ ] Create `.env` / `.env.example` files _(keys currently hardcoded in app_config.dart — move to --dart-define before production build)_
- [ ] Set up Sentry for crash reporting _(Phase 1 remaining)_
- ✅ Set up Firebase project for FCM push notifications
- [ ] Register Apple Developer Program account
- [ ] Register Google Play Developer account
- ✅ Create the basic app theme (colours, typography, spacing, dark mode)
- ✅ Implement the authentication flow: sign up, log in, sign out
- [ ] Build the full onboarding screen sequence: goal selection, body stats, calorie target calculation _(currently sign up / sign in only — goal stats deferred)_
- ✅ Verify the app runs correctly on iOS device
- [ ] Write a basic integration test for the auth flow _(unit tests for models written, auth integration test pending)_

---

## Phase 1 — Core MVP: Dashboard-First Calorie Logging (Weeks 3–12)

**Objective:** Build the complete food-capture-to-confirmed-meal-log pipeline with AI food recognition, daily calorie dashboard, and meal history. This is the product that goes to beta testers.

**Definition of Done:** A user opens the app to the Dashboard, taps the + button to log a meal (via camera, gallery, barcode, or manual entry), confirms the log, and sees their daily calorie progress update in real time. The user can review their meal history for the past 30 days.

**Status: ✅ COMPLETE**

> **Architecture note:** The MVP uses OpenAI GPT-4o Vision directly for food recognition rather than Google Cloud Vision + USDA database lookup as originally specified. This reduced time-to-working pipeline from weeks to days. The Google Cloud Vision + fuzzy DB-match approach remains the plan for Phase 3 (custom model) once meal photo data is accumulated.

### Camera & Photo Capture

- ✅ Build the camera capture screen with the `camera` package (accessed via + FAB, not as home screen)
- ✅ Implement viewfinder overlay with a subtle plate guide circle
- ✅ Add a capture button with haptic feedback
- ✅ Implement gallery import fallback via `image_picker`
- ✅ Build client-side image compression (longest side ≤ 1024px, 85% JPEG quality) — runs in a `compute` isolate to keep UI responsive
- ✅ Add loading state: white flash on capture, full-screen overlay with step labels ("Uploading photo…" / "Identifying food…"), animated skeleton in review sheet
- ✅ Handle camera permission requests gracefully with explanation dialogs — branded rationale screen + "Open Settings" deep-link
- ✅ Camera controls (plate guide, shutter row, side buttons, flash overlay) gated behind `camIsReady` — permission/rationale screens are no longer obscured or unresponsive

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

### Daily Dashboard (Home Screen)

- ✅ Dashboard is the default home screen — app opens to it on launch
- ✅ Show daily greeting with user name and today's date
- ✅ Show daily calorie progress ring (consumed vs. goal, colour-coded: green → amber → red)
- ✅ Show macro progress bars (Protein, Carbs, Fat) with targets — derived from calorie goal via standard macro splits
- ✅ Show stat chips row: Calories, Protein, Carbs, Fat with consumed vs. goal
- ✅ Show today's logged meals as a scrollable list with thumbnails, names, calories, and times
- ✅ Show water intake card with progress bar and quick +250ml add button
- ✅ Dashboard updates in real time when a new meal is confirmed (optimistic update)
- ✅ Empty state shown when no meals logged yet, directing user to the + button
- [ ] Display weekly calorie trend sparkline _(Phase 2)_
- [ ] Display AI coaching insight teaser card on dashboard _(Phase 2)_
- ✅ Dashboard data loads correctly on cold start — `LogController.build()` watches `authStateProvider.future` so it rebuilds once the session is restored from storage (was: empty state on launch)

### Add Food Entry Point (+ FAB)

- ✅ Centre + FAB in bottom navigation bar triggers `AddFoodSheet`
- ✅ `AddFoodSheet` presents four capture methods: Take Photo, Upload from Gallery, Scan Barcode, Quick Add
- ✅ Each path wired to its respective pipeline: camera screen, gallery picker + AI, barcode screen, quick add sheet
- ✅ Paywall gate applied consistently across all four paths

### Bottom Navigation Shell

- ✅ Persistent bottom navigation bar: Home (Dashboard), History, Challenges, Profile, + FAB centre
- ✅ `StatefulShellRoute.indexedStack` preserves tab scroll state across switches (4 branches: `/`, `/nutrition`, `/challenges`, `/profile`)
- ✅ Active tab highlighted in accent lime green
- ✅ Strong haptic feedback on every tab switch — medium impact; FAB uses heavy impact
- ✅ Challenges promoted to a persistent shell tab (index 2) — no longer a push modal
- ✅ Floating FAB with glow shadow — `Scaffold.floatingActionButton` + `FloatingActionButtonLocation.centerDocked` + `BottomAppBar(CircularNotchedRectangle)` notch
- ✅ Camera and barcode screens are full-screen modals (no bottom nav visible)
- ✅ Profile AppBar uses `automaticallyImplyLeading: false` — removing the back button that was crashing navigation in tab context

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
- ✅ Smart suppression: do not send notification if a meal has already been logged in that window
- ✅ Implement notification permission request — toggle in Profile → Notifications section
- [ ] Handle notification taps to deep link directly to the dashboard _(deferred)_

### Haptic Feedback

- ✅ `LabeledTextField` fires `HapticFeedback.selectionClick()` on every focus event
- ✅ All profile screen tile taps trigger selection haptic
- ✅ Goal preset chips trigger selection haptic
- ✅ Sex selection trigger selection haptic
- ✅ Macro toggle in quick-add fires selection haptic
- ✅ Successful meal save fires medium impact haptic
- ✅ Bottom nav tab switches fire selection haptic
- ✅ Centre + FAB fires medium impact haptic
- ✅ Water quick-add fires light impact haptic
- ✅ Camera capture fires medium impact haptic (pre-existing)
- ✅ Water intake persisted to `daily_stats` in Supabase — survives restarts, syncs across devices; UI updates are instant (optimistic), DB writes debounced 500ms to collapse rapid taps

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
- ✅ Implement account deletion flow — `delete-account` Edge Function with paginated Storage cleanup (batches of 1000), profile cascade delete, irreversible `auth.admin.deleteUser` last; returns `success: false` if auth row deletion fails to prevent orphaned-email re-signup
- [ ] Add notification preference controls

### Testing & Quality

- ✅ Unit tests for `FoodItem` and `MealLog` models (serialisation round-trip)
- [ ] Unit tests for all repository classes
- [ ] Widget tests for dashboard, meal review, and history screens
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

**Objective:** Add adaptive meal memory, coaching insights, premium subscription, paywall, and two high-value retention features: Social Accountability Challenges and AI Meal Planner with Grocery Integration. This is the phase where Tavera becomes a business and a habit.

**Status: 🔄 IN PROGRESS**

> **Infrastructure complete (March 26, 2026):** Challenges tab wired to shell nav (Tab 2). Floating FAB with notch. Strong haptics. Account deletion Edge Function live. Challenge scoring (`challenge-notifier`) wired to all log paths. Water intake persisted to `daily_stats`. Dashboard cold-start data loading fixed. Camera permission screen fixed. Profile back-button crash fixed. Paywall sheet helper + Meal Planner / Challenges features added. `DateFormatting.toIsoDateString()` extension centralised. PostHog analytics integrated (8 key events, no-op in dev). Cold-start auth fix applied to all AsyncNotifier controllers. Adaptive meal memory wired to both log paths. Migration 005: `increment_known_meal_count` RPC, `grocery_lists` upsert constraint, challenges RLS self-recursion fixed.

> **Subscription & Paywall flexibility note:** The monetisation model and paywall placement are not yet finalised. The architecture must remain flexible enough to support different models (freemium, hard paywall, trial-first) without requiring significant rewrites. Gate features behind a capabilities check that abstracts away the specific model. RevenueCat is the planned payment layer; it supports model changes at the product configuration level.

### Adaptive Meal Memory

- [ ] Write the known meal detection query: identify meals logged 3+ times with similar food item combinations
- [ ] Build the known_meals table population logic (scheduled PostgreSQL function or Edge Function running daily)
- [ ] Implement time-of-day bucketing so known meals are offered at the right time
- [ ] Build the known meals suggestion row on the Dashboard — horizontal scrollable chips
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
- [ ] Add a teaser insight card on the Dashboard for premium users
- [ ] Add a badge indicator on the insights tab when new insights are available

### Subscription & Paywall

> Architecture must support multiple monetisation models without a rewrite. See PRICING.md for the current plan. Build the capability layer first; wire the specific model second.

- [ ] Create a RevenueCat account and configure products
- [ ] Create subscription products in App Store Connect and Google Play Console
- [ ] Configure monthly and annual subscription options (pricing per PRICING.md)
- [ ] Implement 7-day free trial for annual plan
- [ ] Integrate `purchases_flutter` (RevenueCat SDK)
- [ ] Implement a `SubscriptionService` abstraction layer — all feature gates query this service, not RevenueCat directly, so the monetisation model can change without touching feature code
- [ ] Wire the existing `PaywallSheet` UI to RevenueCat purchase flow
- [ ] Implement subscription status checking on app launch and cache locally
- [ ] Gate premium features: coaching insights, adaptive meal memory, macro tracking, history export, Social Challenges (leaderboards), AI Meal Planner
- [ ] Implement subscription restoration for users who reinstall the app
- [ ] Set up RevenueCat webhooks → Supabase Edge Function for subscription status sync
- [ ] Test purchase flows on both platforms with sandbox/test accounts

### Social Accountability Challenges

> **Product intent:** Retention, motivation, and virality layer. Users create or join group nutrition and health challenges with friends. AI tracks progress, sends motivating notifications, generates leaderboards, and produces shareable visual infographics summarising the user's journey. Examples: 7-Day Protein Challenge, No Sugar Week.

#### Database schema additions
- [ ] Add `challenges` table: id, creator_id, title, description, goal_type (enum: protein_target, calorie_range, consecutive_days, custom), start_date, end_date, is_public, invite_code
- [ ] Add `challenge_participants` table: challenge_id, user_id, joined_at, current_streak, total_score, rank
- [ ] Add `challenge_events` table: challenge_id, user_id, event_type, payload, created_at (for AI progress tracking)

#### Core challenge flow
- [ ] Build challenge creation screen: title, goal type, duration, invite method (link / QR code)
- [ ] Build challenge discovery / join screen: join by invite code or browse public challenges
- [ ] Build challenge detail screen: goal description, participant list, leaderboard, days remaining
- [ ] Implement automatic progress tracking: wire meal logs to challenge goal checks via Edge Function
- [ ] Build leaderboard card: rank, avatar, username, score/streak — updates daily
- [ ] Display challenge progress card on Dashboard during active challenges

#### AI motivational notifications
- ✅ Write Edge Function `challenge-notifier` — wired to both `directLogMeal` and `MealController.confirmAndSave()`; fire-and-forget with `onComplete` callback to invalidate `myChallengesProvider` leaderboard cache; guarded by `hasChallenges` check to skip the network call when the user has no active challenges
- [ ] Generate personalised motivational messages using OpenAI (progress-aware, not generic)
- [ ] Send push notifications: milestone achievements, streak alerts, friendly competitive nudges
- [ ] Notification suppression: respect the user's meal-time suppression windows

#### Social sharing & infographics
- [ ] Build auto-generated completion infographic: challenge name, user stats, rank, best day, streak
- [ ] Implement share-to-social flow (iOS Share Sheet / Android Share Intent)
- [ ] Badge system: challenge badges shown on profile screen
- [ ] Implement achievement unlock notifications with celebratory animation

#### Phase 2 Social Challenges scope
- [ ] Maximum 10 participants per challenge in Phase 2 (scale limits deferred)
- [ ] Challenge types limited to: daily protein target, daily calorie range, consecutive logging streak
- [ ] Custom challenge types deferred to Phase 3

### AI Meal Planner with Grocery Integration

> **Product intent:** After a user has tracked meals for at least one week, the AI generates a personalised weekly meal plan based on their eating patterns, nutritional gaps, goals, and behaviour trends. Includes automatic grocery list creation with exact quantities. Architecture must support grocery delivery API integration (Instacart, Amazon Fresh) as a Phase 3 enhancement.

#### Data prerequisites
- [ ] Minimum 7 days of meal logs required before meal plan generation is offered (enforced in UI and Edge Function)
- [ ] Build meal pattern analyser Edge Function `analyse-eating-patterns`: identify favourite ingredients, meal timing, typical portion sizes, nutritional gaps

#### Meal plan generation
- [ ] Write Edge Function `generate-meal-plan`:
  - Input: user profile, calorie goal, macro targets, eating patterns, top 20 logged ingredients, dietary restrictions
  - Output: 7-day meal plan (3 meals + 1 snack per day), each meal with name, ingredients, quantities, calories, macros
- [ ] Design OpenAI prompt template: emphasise pattern continuity (similar ingredients to what user already eats), nutritional gap filling, practical meal prep time
- [ ] Build meal plan display screen: week view with day tabs, each meal expandable
- [ ] Implement meal plan regeneration: "Regenerate day" and "Regenerate week" actions
- [ ] Allow individual meal swaps: tap a meal → AI suggests 3 alternatives

#### Grocery list
- [ ] Build grocery list generator from confirmed meal plan: aggregate ingredients across all meals, de-duplicate, sum quantities
- [ ] Grocery list grouped by category: Produce, Protein, Dairy, Pantry, Frozen
- [ ] Check-off UI: tap to mark items purchased, persists state locally
- [ ] Edit quantities and add/remove items manually
- [ ] Export grocery list as plain text (share sheet)

#### Grocery delivery integration (architecture only in Phase 2 — live integration Phase 3)
- [ ] Design `GroceryDeliveryService` abstract interface with: `isAvailable()`, `addItemsToCart(items)`, `openCheckout()`
- [ ] No live integration in Phase 2 — stub the interface and add a "Connect to delivery service" placeholder in the grocery list screen
- [ ] Phase 3 will implement `InstacartDeliveryService` and `AmazonFreshDeliveryService` concretely

### Analytics

- ✅ Integrate `posthog_flutter` (v4.6.0) with `AnalyticsService` abstraction layer — no-op when `POSTHOG_API_KEY` not set, silent error swallowing
- ✅ Track key events: `meal_logged` (source, calories, item_count), `paywall_shown` (source), `challenge_created`, `challenge_joined` (method), `meal_plan_generated`, `coaching_insights_generated`, `known_meal_relogged`
- ✅ User identify/reset wired to `authStateProvider` stream in `main.dart`
- [ ] Set up PostHog project, add `POSTHOG_API_KEY` to build configuration
- [ ] Track additional events: `camera_opened`, `barcode_scanned`, `subscription_started`, `grocery_list_opened`, `challenge_completed`
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
- [ ] Integrate Apple HealthKit and Google Health Connect for activity data import (Note: step counting explicitly excluded; focus on calorie burn from workouts and heart rate)
- [ ] Implement dynamic calorie budget adjustment based on imported activity data
- [ ] Build the meal scoring system: green/yellow/red rating per meal based on goal alignment
- [ ] Implement consistency streaks that reward logging frequency
- [ ] Build the weekly summary screen with visual trends
- [ ] Add intermittent fasting timer with eating window visualisation
- [ ] Implement data export (CSV) for premium users
- [ ] Add multi-language support starting with Spanish, Portuguese, French, and Hindi
- [ ] Evaluate Google Cloud Vision + USDA database lookup to replace or supplement OpenAI Vision
- [ ] Optimise app launch time to under 2 seconds on mid-range devices
- [ ] Expand Social Challenges: custom challenge types, up to 50 participants, public challenge discovery
- [ ] Implement `InstacartDeliveryService` and `AmazonFreshDeliveryService` grocery integrations

---

## Phase 4 — Meal Planning Maturity & Social Scale (Weeks 35–46)

**Status: ❌ NOT STARTED**

### Checklist

- [ ] Mature the AI meal planning engine: multi-week plans, plan history, personalisation feedback loop
- [ ] Implement meal plan editing: swap meals, adjust portions, regenerate days
- [ ] Build the accountability partner feature: invite one person to see your daily summary (deeper than group challenges)
- [ ] Add GLP-1 medication tracking mode with protein-prioritised coaching
- [ ] Build the recipe import feature: paste a URL, extract ingredients, calculate nutrition
- [ ] Implement food photo quality feedback loop to improve AI accuracy
- [ ] Scale Social Challenges: viral leaderboard sharing, cross-app deep links, challenge templates library

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
| Dashboard-first UX + bottom nav shell | Week 3 | 1 | ✅ Done |
| Haptic feedback system-wide | Week 3 | 1 | ✅ Done |
| Beta release to 20–50 testers | Week 10 | 1 | ❌ |
| Beta feedback incorporated, MVP stable | Week 12 | 1 | ❌ |
| Adaptive meal memory live | Week 16 | 2 | ❌ |
| Social Accountability Challenges — MVP | Week 18 | 2 | ❌ |
| Subscription and paywall live | Week 18 | 2 | ❌ |
| AI Meal Planner + grocery list | Week 20 | 2 | ❌ |
| Public launch on App Store and Google Play | Week 22 | 2 | ❌ |
| 1,000 registered users | Week 26 | 3 | ❌ |
| Restaurant menu scanning live | Week 28 | 3 | ❌ |
| Grocery delivery integration (Instacart) | Week 30 | 3 | ❌ |
| Meal planning engine mature | Week 38 | 4 | ❌ |
| 10,000 registered users | Week 40 | 4 | ❌ |
| Professional accounts live | Week 50 | 5 | ❌ |
| First corporate wellness pilot | Week 55 | 5 | ❌ |

---

## Immediate Next Actions (Phase 2 — Sprint)

1. **Apply migration 005** — run `supabase/migrations/005_rpc_and_constraints.sql` on the Tavera Supabase project (`hdtuezlbabsebkoucjhp`): adds `increment_known_meal_count` RPC, `grocery_lists` upsert constraint, fixes challenges RLS recursion. CLI: `supabase db push` or paste SQL into the Supabase dashboard SQL editor.
2. **Deploy Edge Functions** — `supabase functions deploy` for all 5 functions (challenge-notifier, generate-coaching, generate-meal-plan, analyse-eating-patterns, delete-account). All source is in `supabase/functions/`.
3. **PostHog project setup** — create project at posthog.com, copy API key, add `--dart-define=POSTHOG_API_KEY=phc_...` to build/run configuration
4. **RevenueCat setup** — create products in App Store Connect and Google Play Console, integrate `purchases_flutter` SDK, build `SubscriptionService` abstraction
5. **Beta testing setup** — TestFlight + Google Play Internal Testing track

---

*This document should be read alongside CONCEPT.md, ARCHITECTURE.md, PRICING.md, and the root README.md.*
