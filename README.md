# Tavera

**AI-powered calorie tracker. Tap +. Snap. Confirm. Done.**

Tavera is a cross-platform mobile application that uses computer vision to estimate calories and macronutrients from a photo of your meal in under five seconds. It replaces the tedious manual food database search that causes 70% of users to abandon calorie tracking within two weeks. The app learns your eating patterns over time, pre-fills frequent meals with one tap, and delivers weekly AI coaching insights personalised to your nutrition habits.

---

## Current State

**Status:** Phase 1 Complete · Phase 2 In Progress (March 2026)
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

Beyond logging, Tavera provides a real-time daily calorie and macro dashboard, a complete meal history, weekly AI coaching insights, and — in Phase 2 — social accountability challenges and a personalised AI meal planner with grocery list integration.

Tavera is not a diet app. It does not prescribe what to eat, shame users for their choices, or promote any specific dietary philosophy. It provides clarity about what you eat so you can make informed decisions.

---

## App Flow

```
App Launch
    └─► Dashboard (home screen)
            ├─ Calorie ring: consumed vs. goal
            ├─ Macro bars: protein / carbs / fat
            ├─ Stat chips row
            ├─ Water intake card
            └─ Today's meals list

Bottom Navigation
    ├─ Home       → Dashboard
    ├─ History    → Meal history by date
    ├─ [+ FAB]    → AddFoodSheet ──► Take Photo    → Camera screen → AI → Review
    │                               ├─► Upload Photo → Gallery → AI → Review
    │                               ├─► Scan Barcode → Barcode screen → Log
    │                               └─► Quick Add   → Manual entry form
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
| **Drift (SQLite)** | Local structured database for offline support (Phase 2) |

### Backend

| Technology | Purpose |
|-----------|---------|
| **Supabase** | Auth, PostgreSQL database, file storage, edge functions |
| **PostgreSQL 15+** | Primary database (managed by Supabase) |
| **Supabase Edge Functions** | Serverless API endpoints (Deno/TypeScript) |
| **Supabase Auth** | Authentication (email, Apple Sign-In, Google Sign-In) |
| **Supabase Storage** | Meal photo storage with CDN |

### AI & Machine Learning

| Technology | Purpose |
|-----------|---------|
| **OpenAI GPT-4o Vision** | Food identification from photos (MVP) |
| **OpenAI API (GPT-4o)** | Weekly coaching insight generation, AI meal planner (Phase 2) |
| **Open Food Facts** | International packaged food and barcode database |
| **USDA FoodData Central** | Primary nutritional reference database |

### Services & Infrastructure

| Technology | Purpose |
|-----------|---------|
| **RevenueCat** | Cross-platform subscription management (Phase 2) |
| **Firebase Cloud Messaging** | Push notifications (iOS and Android) |
| **PostHog** | Product analytics, funnels, feature flags (Phase 2) |
| **Sentry** | Crash reporting and error monitoring |
| **Resend** | Transactional email |

---

## Languages Used

**Dart** — All mobile client code. UI, state management, local database, HTTP networking, camera integration.

**TypeScript** — Supabase Edge Functions (Deno runtime). AI processing orchestration, coaching engine, challenge notification system, grocery list generation, subscription webhook handling.

**SQL** — Database migrations, Row-Level Security policies, complex queries (known meal detection, challenge scoring, weekly meal aggregation).

---

## Development Environment Setup

### Prerequisites

1. **Flutter SDK 3.22+** — Run `flutter doctor` after installation to verify all dependencies.
2. **Android Studio** — Install with Android SDK (API 29+).
3. **Xcode 15+** (macOS only) — Required for iOS builds.
4. **Supabase CLI** — `npm install -g supabase`
5. **Node.js 20+** — Required for Supabase CLI.
6. **Deno** — `curl -fsSL https://deno.land/install.sh | sh`
7. **Git** — For version control.

### Getting Started

```bash
git clone https://github.com/your-org/tavera.git
cd tavera
```

Copy the environment template and fill in your credentials:

```bash
cp .env.example .env
```

The `.env` file requires:

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-supabase-anon-key
OPENAI_API_KEY=your-openai-api-key
REVENUECAT_API_KEY=your-revenuecat-api-key  # Phase 2
SENTRY_DSN=your-sentry-dsn
POSTHOG_API_KEY=your-posthog-api-key        # Phase 2
```

Install Flutter dependencies:

```bash
flutter pub get
```

Start a local Supabase instance:

```bash
supabase start
supabase db push
```

Run the app:

```bash
flutter run
```

### Running Tests

```bash
# Unit and widget tests
flutter test

# Integration tests (requires a running emulator)
flutter test integration_test/

# Edge Function tests
supabase functions serve analyse-meal --env-file .env
```

### Building for Release

**Android:**
```bash
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ipa --release
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
├── lib/
│   ├── main.dart               # Entry point (Firebase, Supabase, ProviderScope)
│   ├── controllers/            # Riverpod notifiers (auth, camera, log, meal)
│   ├── models/                 # Data classes (FoodItem, MealLog, UserProfile, etc.)
│   ├── services/               # External service wrappers (notifications)
│   ├── views/
│   │   ├── auth/               # Onboarding & sign-in screen
│   │   ├── shell/              # AppShell — persistent bottom nav + FAB
│   │   ├── dashboard/          # Home screen (calorie ring, macros, today's meals)
│   │   ├── capture/            # AddFoodSheet — entry point for all logging methods
│   │   ├── camera/             # Full-screen camera capture (accessed via + FAB)
│   │   ├── barcode/            # Barcode scanning
│   │   ├── history/            # Meal history by date
│   │   ├── profile/            # Settings, goals, subscription
│   │   ├── review/             # AI meal confirmation sheet
│   │   ├── quick_add/          # Manual entry form
│   │   └── paywall/            # Premium upgrade sheet
│   ├── widgets/                # Shared reusable widgets
│   └── core/
│       ├── config/             # AppConfig, environment variables
│       ├── router/             # GoRouter with StatefulShellRoute
│       └── theme/              # Colors, typography, dark theme
├── supabase/
│   ├── migrations/             # PostgreSQL migration files
│   ├── seed.sql                # Food database import
│   └── functions/              # Edge Functions (TypeScript/Deno)
├── test/                       # Unit and widget tests
├── integration_test/           # Integration tests
└── pubspec.yaml                # Flutter dependencies
```

---

## Roadmap Summary

See [ROADMAP.md](ROADMAP.md) for the full checklist. In summary:

**Phase 1 (✅ Complete):** Dashboard-first UX, camera-to-log AI pipeline, barcode scanning, manual quick-add, meal history, push notifications with smart suppression, calorie and macro tracking, water tracking, haptic feedback system-wide.

**Phase 2 (🔄 In Progress):** Adaptive meal memory, AI coaching insights, subscription with RevenueCat, paywall, PostHog analytics, Social Accountability Challenges, AI Meal Planner with grocery list integration, public launch.

**Phase 3:** Restaurant menu scanning, HealthKit/Health Connect integration (workout activity only — no step tracking), meal scoring, consistency streaks, grocery delivery integration (Instacart, Amazon Fresh), expanded Social Challenges.

**Phase 4:** AI meal planning maturity, accountability partner feature, GLP-1 tracking mode, recipe URL import.

**Phase 5:** Professional accounts for dietitians, corporate wellness, custom food recognition model.

---

## Key Product Decisions

- **Dashboard first.** The app opens to the Dashboard, not the camera. Food capture is always triggered by the + FAB. This lowers the activation barrier and reinforces the tracking habit.
- **No step tracking.** Steps / pedometer integration is explicitly out of scope.
- **Subscription flexibility.** The paywall and monetisation model are not yet finalised. Feature gates are built behind a `SubscriptionService` abstraction so the model can change without rewrites.
- **OpenAI for vision, not Google Cloud Vision.** Chosen for the MVP because it handles food recognition and nutrition estimation in a single API call. GCV + USDA lookup remains the plan for a custom trained model in Phase 3.

---

## Contributing

Tavera is currently a private project. If you are a developer who has been invited to contribute, read all documents in the `docs/` directory before writing any code. All changes go through pull requests to `main`. Write tests for new features. Follow the linting rules in `analysis_options.yaml`.

---

## License

Proprietary. All rights reserved.

---

## Contact

For questions about the project, reach out to Dee (Founder).
