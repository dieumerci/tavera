# Tavera

**AI-powered calorie tracker. Tap +. Snap. Confirm. Done.**

Tavera is a cross-platform mobile application that uses computer vision to estimate calories and macronutrients from a photo of your meal in under five seconds. It replaces the tedious manual food database search that causes 70% of users to abandon calorie tracking within two weeks. The app learns your eating patterns over time, pre-fills frequent meals with one tap, and delivers weekly AI coaching insights personalised to your nutrition habits.

---

## Current State

**Status:** Phase 1 ✅ Complete · Phase 2 ✅ Complete · Phase 3 🔄 In Progress
**Version:** 1.0.0
**Platforms:** iOS 15+, Android 10+ (API 29+)

The core logging pipeline is fully working end-to-end. A user can open the app, see their daily Dashboard, tap the + button to log a meal (via camera, gallery, barcode, or manual entry), confirm AI-identified food items, and see their calorie and macro progress update in real time.

### Documentation

All project documentation lives in the `docs/` directory:

| Document | Description |
|----------|-------------|
| [docs/CONCEPT.md](docs/CONCEPT.md) | Product concept, target audience, competitive positioning, and core values |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture, tech stack, database schema, AI pipeline, security model |
| [ROADMAP.md](ROADMAP.md) | Five-phase development roadmap with detailed checklists for every feature |
| [docs/PRICING.md](docs/PRICING.md) | Freemium model, subscription tiers, regional pricing, paywall strategy |

If you are a new developer joining this project, read the documents in the order listed above.

---

## What Tavera Does

Tavera solves one problem: calorie tracking is effective but unsustainable because manual food logging is exhausting. Tavera makes logging fast enough to become habitual.

**The core interaction:**
1. Open the app → **Dashboard shows your day at a glance**
2. Tap the **+ button** in the navigation bar → choose how to log (photo, gallery, barcode, or manual)
3. AI identifies your food in under 5 seconds
4. Tap confirm → dashboard updates instantly

Over time, the app learns what you eat regularly and offers those meals as one-tap options, reducing logging time to under three seconds for known meals.

Beyond logging, Tavera provides:
- Real-time daily calorie and macro dashboard
- Complete meal history with date navigation
- **Meal scoring** — green/yellow/red rating per meal relative to your daily goal
- **Consistency streaks** — visual reward for logging every day
- **Weekly summary screen** — 7-day calorie bars, macro averages, best/worst day
- Weekly AI coaching insights (premium)
- Intermittent fasting timer with smart calorie gate
- Net carbs mode (carbs minus dietary fibre)
- Social accountability challenges (premium)
- AI meal planner with grocery list (premium)
- Barcode scanning via Open Food Facts

Tavera is not a diet app. It does not prescribe what to eat, shame users for their choices, or promote any specific dietary philosophy.

---

## App Flow

```
App Launch
    └─► Dashboard (home screen)
            ├─ Calorie ring: consumed vs. goal
            ├─ Macro bars: protein / carbs / fat
            ├─ Stat chips row
            ├─ Streak card → Weekly Summary screen
            ├─ Water intake card
            └─ Today's meals list (with meal score dots)

Bottom Navigation
    ├─ Home       → Dashboard
    ├─ History    → Meal history by date
    ├─ [+ FAB]    → AddFoodSheet ──► Take Photo    → Camera screen → AI → Review
    │                               ├─► Upload Photo → Gallery → AI → Review
    │                               ├─► Scan Barcode → Barcode screen → Log
    │                               └─► Quick Add   → Manual entry form
    ├─ Challenges → Social challenges
    └─ Profile    → Settings, goals, subscription
```

**Note:** Steps / activity tracking is explicitly out of scope.

---

## Technology Stack

### Mobile Client

| Technology | Purpose |
|-----------|---------|
| **Flutter 3.22+** | Cross-platform mobile framework (iOS and Android from one codebase) |
| **Dart 3.4+** | Programming language for Flutter |
| **Riverpod 2.x** | Reactive state management |
| **GoRouter 14.x** | Declarative navigation with `StatefulShellRoute` for tab state preservation |
| **RevenueCat** | Cross-platform subscription management and paywall |

### Backend

| Technology | Purpose |
|-----------|---------|
| **Supabase** | Auth, PostgreSQL database, file storage, edge functions |
| **PostgreSQL 15+** | Primary database (managed by Supabase) |
| **Supabase Edge Functions** | Serverless API endpoints (Deno/TypeScript) |
| **Supabase Auth** | Authentication (email/password) |
| **Supabase Storage** | Meal photo storage with CDN |

### AI & Machine Learning

| Technology | Purpose |
|-----------|---------|
| **Google Gemini 2.0 Flash** | Food identification from photos, AI meal planner, meal swaps |
| **Google Gemini 2.0 Flash** | Weekly coaching insight generation |
| **Open Food Facts** | International packaged food and barcode database |

> **AI migration note (March 2026):** All AI features were migrated from OpenAI GPT-4o to Google Gemini 2.0 Flash, achieving ~66× cost reduction with comparable accuracy for food recognition. The `GEMINI_API_KEY` secret must be set in Supabase Edge Function secrets.

### Services & Infrastructure

| Technology | Purpose |
|-----------|---------|
| **RevenueCat** | Cross-platform subscription management — entitlement: `Kazadi Inc Pro` |
| **Firebase Cloud Messaging** | Push notifications (iOS and Android) |
| **PostHog** | Product analytics, funnels, feature flags |
| **pg_cron** | Scheduled DB jobs: nightly known-meal backfill, weekly coaching trigger |

---

## Languages Used

**Dart** — All mobile client code. UI, state management, HTTP networking, camera integration.

**TypeScript** — Supabase Edge Functions (Deno runtime). AI processing orchestration, coaching engine, challenge notification system, grocery list generation, subscription webhook handling.

**SQL** — Database migrations, Row-Level Security policies, complex queries (known meal detection and backfill, challenge scoring, weekly meal aggregation).

---

## Development Environment Setup

### Prerequisites

1. **Flutter SDK 3.22+** — Run `flutter doctor` after installation to verify all dependencies.
2. **Android Studio** — Install with Android SDK (API 29+).
3. **Xcode 15+** (macOS only) — Required for iOS builds.
4. **Supabase CLI** — `npm install -g supabase`
5. **Node.js 20+** — Required for Supabase CLI.
6. **Deno** — `curl -fsSL https://deno.land/install.sh | sh`

### Getting Started

```bash
git clone https://github.com/your-org/tavera.git
cd tavera
```

Copy the environment template and fill in your credentials:

```bash
cp .env.example .env
# Edit .env with your actual keys
```

Install Flutter dependencies:

```bash
flutter pub get
```

Apply database migrations:

```bash
supabase db push
```

Run the app (keys are loaded from `.env` automatically in development):

```bash
flutter run
```

### Environment Variables

The `.env` file is loaded at runtime during local development via `flutter_dotenv`. For production builds, keys are injected at compile time via `--dart-define` flags instead — the `.env` file is not bundled in release builds.

#### Required Keys

| Key | Where to get it | Used by |
|-----|----------------|---------|
| `SUPABASE_URL` | Supabase Dashboard → Project Settings → API | Flutter app |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Project Settings → API | Flutter app |
| `GEMINI_API_KEY` | [aistudio.google.com](https://aistudio.google.com) (free, 1,500 req/day) | Supabase Edge Functions secret |
| `REVENUECAT_API_KEY_IOS` | RevenueCat Dashboard → Project Settings → API Keys | Flutter app (iOS builds) |
| `REVENUECAT_API_KEY_ANDROID` | RevenueCat Dashboard → Project Settings → API Keys | Flutter app (Android builds) |

#### Optional Keys

| Key | Purpose |
|-----|---------|
| `POSTHOG_API_KEY` | Product analytics — app works without it (events are discarded) |

#### Supabase Edge Function Secrets

Set these in the **Supabase Dashboard → Edge Functions → Secrets**, NOT in `.env`:

```bash
supabase secrets set GEMINI_API_KEY=AIzaSy...
supabase secrets set REVENUECAT_WEBHOOK_SECRET=<value-from-revenuecat>
```

### RevenueCat Setup

1. Create a project at [app.revenuecat.com](https://app.revenuecat.com)
2. Create an entitlement named exactly **`Kazadi Inc Pro`**
3. Configure products in App Store Connect + Google Play Console
4. Link products to the `Kazadi Inc Pro` entitlement in RevenueCat
5. Add the **public SDK keys** (`appl_...` for iOS, `goog_...` for Android) to `.env`
6. Add the webhook secret to Supabase secrets (see above)
7. Set the webhook URL in RevenueCat Dashboard → Project Settings → Integrations → Webhooks:
   ```
   https://<your-project-ref>.supabase.co/functions/v1/revenuecat-webhook
   ```

> **Key types:** Use the **public SDK key** (`appl_...` / `goog_...` / `test_...`) in the Flutter app. The V2 secret key (`sk_...`) is for server-to-server REST calls only and must NOT go in the app.

### Running Tests

```bash
# Unit and widget tests
flutter test

# Integration tests (requires a running emulator)
flutter test integration_test/

# Test an Edge Function locally
supabase functions serve analyse-meal --env-file .env
```

### Building for Release

All secrets must be passed via `--dart-define` for production builds. The `.env` file is **not** included in release builds.

**iOS:**
```bash
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=REVENUECAT_API_KEY_IOS=appl_... \
  --dart-define=POSTHOG_API_KEY=phc_...
```

**Android:**
```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=REVENUECAT_API_KEY_ANDROID=goog_... \
  --dart-define=POSTHOG_API_KEY=phc_...
```

---

## Project Structure

```
tavera/
├── docs/
│   ├── CONCEPT.md              # Product concept and vision
│   ├── ARCHITECTURE.md         # System design and technical specification
│   └── PRICING.md              # Monetisation strategy and pricing
├── ROADMAP.md                  # Development roadmap with checklists
├── .env.example                # Template for required environment variables
├── lib/
│   ├── main.dart               # Entry point (dotenv, Firebase, Supabase, RevenueCat, ProviderScope)
│   ├── controllers/            # Riverpod notifiers (auth, camera, log, meal, challenges)
│   ├── models/                 # Data classes (FoodItem, MealLog, MealScore, UserProfile, etc.)
│   ├── services/               # External service wrappers (RevenueCat, notifications, analytics)
│   ├── views/
│   │   ├── auth/               # Onboarding & sign-in screen
│   │   ├── shell/              # AppShell — persistent bottom nav + FAB
│   │   ├── dashboard/          # Home screen (calorie ring, macros, streak card, meals)
│   │   ├── capture/            # AddFoodSheet — entry point for all logging methods
│   │   ├── camera/             # Full-screen camera capture
│   │   ├── barcode/            # Barcode scanning
│   │   ├── history/            # Meal history by date
│   │   ├── weekly_summary/     # 7-day calorie bars, macro averages, streak (Phase 3)
│   │   ├── challenges/         # Social challenges
│   │   ├── coaching/           # AI weekly insights
│   │   ├── meal_planner/       # AI meal planner + grocery list
│   │   ├── fasting/            # Intermittent fasting timer
│   │   ├── profile/            # Settings, goals, subscription
│   │   ├── review/             # AI meal confirmation sheet
│   │   ├── quick_add/          # Manual entry form
│   │   └── paywall/            # Premium upgrade sheet
│   ├── widgets/                # Shared reusable widgets
│   └── core/
│       ├── config/             # AppConfig, Env (dart-define + dotenv)
│       ├── router/             # GoRouter with StatefulShellRoute
│       └── theme/              # Colors, typography, dark theme
├── supabase/
│   ├── migrations/             # PostgreSQL migration files (001–010)
│   └── functions/              # Edge Functions (TypeScript/Deno)
│       ├── analyse-meal/       # Gemini vision food recognition
│       ├── generate-coaching/  # Weekly AI insights (single-user + batch cron)
│       ├── generate-meal-plan/ # AI meal planner
│       ├── swap-planned-meal/  # Meal plan swap
│       ├── challenge-notifier/ # Challenge scoring + motivational messages
│       ├── revenuecat-webhook/ # Subscription status sync from RevenueCat
│       ├── delete-account/     # GDPR account deletion
│       └── identify-product/   # Barcode + OCR product lookup
├── test/                       # Unit and widget tests
└── pubspec.yaml                # Flutter dependencies
```

---

## Roadmap Summary

See [ROADMAP.md](ROADMAP.md) for the full checklist. In summary:

**Phase 1 (✅ Complete):** Dashboard-first UX, camera-to-log AI pipeline, barcode scanning, manual quick-add, meal history, push notifications with smart suppression, calorie and macro tracking, water tracking, haptic feedback system-wide.

**Phase 2 (✅ Complete):** Adaptive meal memory with nightly backfill, AI coaching insights with weekly cron, RevenueCat subscription + paywall, Social Accountability Challenges, AI Meal Planner with grocery list, intermittent fasting timer, net carbs mode, PostHog analytics, RevenueCat webhook for subscription sync, Gemini API migration (66× cheaper than GPT-4o).

**Phase 3 (🔄 In Progress):** Meal scoring (green/yellow/red per meal), consistency streaks with weekly summary screen, food label scanner, GLP-1 medication tracking mode, mood-energy correlation engine, restaurant menu scanning, HealthKit/Health Connect, data export.

**Phase 4:** AI meal planning maturity, accountability partner feature, recipe URL import.

**Phase 5:** Professional accounts for dietitians, corporate wellness, custom food recognition model.

---

## Key Product Decisions

- **Dashboard first.** The app opens to the Dashboard, not the camera. Food capture is always triggered by the + FAB.
- **No step tracking.** Steps / pedometer integration is explicitly out of scope.
- **Subscription flexibility.** Feature gates are built behind a `SubscriptionService` abstraction so the monetisation model can change without rewrites.
- **Gemini over GPT-4o.** Gemini 2.0 Flash delivers comparable food recognition accuracy at ~66× lower cost. GPT-4o remains an option via environment variable swap if needed.
- **Non-judgmental scoring.** Meal score colours (green/yellow/red) indicate portion context relative to the daily goal — they do not label foods as "good" or "bad".

---

## Contributing

Tavera is currently a private project. If you are a developer who has been invited to contribute, read all documents in the `docs/` directory before writing any code. All changes go through pull requests to `main`. Write tests for new features. Follow the linting rules in `analysis_options.yaml`.

---

## License

Proprietary. All rights reserved.

---

## Contact

For questions about the project, reach out to Dee (Founder).
