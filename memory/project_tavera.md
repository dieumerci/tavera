---
name: project_tavera
description: Tavera app overview — AI camera-first calorie tracker, Flutter+Riverpod+Supabase+OpenAI, Phase 1 complete, Phase 2 in progress
type: project
---

Tavera is a Flutter mobile app — AI-powered calorie tracker.

**Why:** Eliminate the friction of manual calorie logging so users actually stick with it.

**Stack:** Flutter 3.22 / Dart 3.4, Riverpod 2.x, GoRouter 14.x, Supabase (Auth + Postgres + Storage + Edge Functions), OpenAI GPT-4o Vision, Firebase FCM.

**Status (March 2026):** Phase 1 complete, Phase 2 in progress.

**Key architecture decisions:**
- Dashboard-first UX — app opens to `/` (DashboardScreen), NOT camera
- Food capture triggered via centre + FAB → `AddFoodSheet` (options: photo, gallery, barcode, manual)
- Camera (`/camera`) and barcode (`/barcode`) are full-screen modal routes outside the `StatefulShellRoute` shell
- Bottom nav: Home, History, + FAB, Profile (3 tabs + FAB)
- `MealDetailSheet` is public and usable from both Dashboard and History screens
- Steps / activity tracking is explicitly OUT OF SCOPE

**Phase 2 planned features:**
1. Adaptive meal memory (known_meals detection + quick-tap chips on Dashboard)
2. AI coaching insights (weekly, Edge Function `generate-coaching`)
3. Subscription & Paywall via RevenueCat — kept flexible with `SubscriptionService` abstraction
4. Social Accountability Challenges (challenges, challenge_participants, challenge_events tables)
5. AI Meal Planner + Grocery List (meal_plans, grocery_lists tables; grocery delivery integration deferred to Phase 3)
6. PostHog analytics

**How to apply:** When asked to add features or fix bugs, the architecture above is authoritative. Camera is a modal, not home. Steps are out of scope. Feature gates use SubscriptionService abstraction.
