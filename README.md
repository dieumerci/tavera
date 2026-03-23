# Tavera

**AI-powered photo calorie tracker. Snap. Confirm. Done.**

Tavera is a cross-platform mobile application that uses computer vision to estimate calories and macronutrients from a photo of your meal in under five seconds. It replaces the tedious manual food database search that causes 70% of users to abandon calorie tracking within two weeks. The app learns your eating patterns over time, pre-fills frequent meals with one tap, and delivers weekly AI coaching insights personalised to your nutrition habits.

---

## Current State

**Status:** Pre-Development (March 2026)  
**Version:** 0.0.0  
**Platforms:** iOS 15+, Android 10+ (API 29+)

Tavera is in the documentation and planning phase. No code has been written yet. The concept, system architecture, database schema, technology stack, roadmap, and pricing strategy are fully documented and ready for development to begin.

### Documentation

All project documentation lives in the `docs/` directory:

| Document | Description |
|----------|-------------|
| [docs/CONCEPT.md](docs/CONCEPT.md) | Full product concept, target audience, competitive positioning, and core values |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture, tech stack, database schema, AI pipeline, security model, and folder structure |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Five-phase development roadmap with detailed checklists for every feature |
| [docs/PRICING.md](docs/PRICING.md) | Freemium model, subscription tiers, regional pricing, paywall strategy, and revenue projections |

If you are a new developer joining this project, read the documents in the order listed above. The Concept document explains what Tavera is and why it exists. The Architecture document explains how it is built. The Roadmap document explains what to build and in what order. The Pricing document explains how it makes money.

---

## What Tavera Does

Tavera solves one problem: calorie tracking is effective but unsustainable because manual food logging is exhausting. Tavera makes logging fast enough to be habitual.

The core interaction is: open the app, point the camera at your food, tap capture, review the AI's calorie and macro estimate, tap confirm. Total time: under ten seconds. Over time, the app learns what you eat regularly and offers those meals as one-tap options, reducing logging time to under three seconds for known meals.

Beyond logging, Tavera provides a daily calorie and macro dashboard, a meal history feed, and weekly AI coaching insights that identify patterns in your eating and suggest specific, actionable changes. The coaching layer is what differentiates Tavera from a simple camera tool — it transforms tracking data into behaviour change.

Tavera is not a diet app. It does not prescribe what to eat, shame users for their choices, or promote any specific dietary philosophy. It provides clarity about what you eat so you can make informed decisions. The tone is warm, neutral, and supportive.

---

## Technology Stack

### Mobile Client

| Technology | Purpose |
|-----------|---------|
| **Flutter 3.22+** | Cross-platform mobile framework (iOS and Android from one codebase) |
| **Dart 3.4+** | Programming language for Flutter |
| **Riverpod 2.x** | State management |
| **GoRouter** | Declarative navigation with deep linking |
| **Dio** | HTTP client with interceptors |
| **Drift (SQLite)** | Local structured database for offline support |
| **Hive** | Lightweight key-value local cache |
| **Freezed** | Immutable data class code generation |

### Backend

| Technology | Purpose |
|-----------|---------|
| **Supabase** | Backend-as-a-service: auth, PostgreSQL database, file storage, edge functions, realtime |
| **PostgreSQL 15+** | Primary database (managed by Supabase) |
| **Supabase Edge Functions** | Serverless API endpoints (Deno/TypeScript) |
| **Supabase Auth** | Authentication (email, Apple Sign-In, Google Sign-In) |
| **Supabase Storage** | Meal photo storage with CDN |

### AI & Machine Learning

| Technology | Purpose |
|-----------|---------|
| **Google Cloud Vision API** | Food item identification from photos (MVP) |
| **Google Vertex AI** | Custom food recognition model (future, post-scale) |
| **OpenAI API (GPT-4o-mini)** | Weekly coaching insight generation |
| **USDA FoodData Central** | Primary nutritional database (380K+ verified foods) |
| **Open Food Facts** | International packaged food and barcode database |

### Services & Infrastructure

| Technology | Purpose |
|-----------|---------|
| **RevenueCat** | Cross-platform subscription management (App Store + Google Play) |
| **Firebase Cloud Messaging** | Push notifications (iOS and Android) |
| **PostHog** | Product analytics, funnels, feature flags |
| **Sentry** | Crash reporting and error monitoring |
| **Resend** | Transactional email (welcome, password reset, weekly summaries) |

### Distribution

| Platform | Purpose |
|----------|---------|
| **Apple App Store** | iOS distribution (requires Apple Developer Program, $99/year) |
| **Google Play Store** | Android distribution (requires Google Play Developer account, $25 one-time) |

---

## Languages Used

**Dart** — The primary language. All mobile client code is written in Dart via the Flutter framework. This includes the UI, state management, local database operations, HTTP networking, camera integration, and offline sync logic. Dart was chosen because Flutter is the fastest path to a high-quality cross-platform mobile app from a single codebase, and Dart's null safety, pattern matching, and async/await model make it productive for a small team.

**TypeScript** — Used for Supabase Edge Functions (which run on Deno). All serverless backend logic is written in TypeScript: the AI processing orchestration, coaching engine, push notification scheduling, and subscription webhook handling. TypeScript was chosen because it is the native language of Supabase Edge Functions and provides strong typing that reduces runtime errors in critical backend paths.

**SQL** — Used for database migrations, Row-Level Security policies, and complex queries (known meal detection, food fuzzy matching, weekly meal aggregation for coaching). PostgreSQL-specific features are used extensively: `pg_trgm` for fuzzy text search, `jsonb` for flexible data storage, and database triggers for automatic timestamp management.

**Python** — Not used in the production application, but may be used for data processing scripts (USDA data import, food database maintenance, AI model training scripts) and for any future custom machine learning model development on Vertex AI. Python is the standard language for ML model training and evaluation.

---

## Development Environment Setup

### Prerequisites

You need the following installed before working on Tavera:

1. **Flutter SDK 3.22+** — Follow the [official installation guide](https://docs.flutter.dev/get-started/install). Run `flutter doctor` after installation to verify all dependencies.

2. **Android Studio** — Install with Android SDK (API 29 through 34). Create at least one AVD (Android Virtual Device) for testing. Recommended: Pixel 7 emulator with API 34.

3. **Xcode 15+** (macOS only) — Required for iOS builds. Install from the Mac App Store. Open Xcode once to accept the license and install command-line tools.

4. **Supabase CLI** — Install with `npm install -g supabase`. Used for local development, migrations, and Edge Function development.

5. **Node.js 20+** — Required for Supabase CLI.

6. **Deno** — Required for Edge Function development. Install with `curl -fsSL https://deno.land/install.sh | sh`.

7. **Google Cloud CLI** — Install from [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install). Authenticate with `gcloud auth login`. Enable the Cloud Vision API on your project.

8. **Git** — For version control.

### Getting Started

Clone the repository:

```bash
git clone https://github.com/your-org/tavera.git
cd tavera
```

Copy the environment template and fill in your credentials:

```bash
cp .env.example .env
```

The `.env` file requires the following values:

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-supabase-anon-key
GOOGLE_CLOUD_VISION_API_KEY=your-google-cloud-api-key
OPENAI_API_KEY=your-openai-api-key
REVENUECAT_API_KEY=your-revenuecat-api-key
SENTRY_DSN=your-sentry-dsn
POSTHOG_API_KEY=your-posthog-api-key
RESEND_API_KEY=your-resend-api-key
```

Install Flutter dependencies:

```bash
flutter pub get
```

Run code generation (for Freezed data classes and Riverpod providers):

```bash
dart run build_runner build --delete-conflicting-outputs
```

Start a local Supabase instance for development:

```bash
supabase start
```

This starts a local PostgreSQL database, Auth server, Storage server, and Edge Function runtime. The local Supabase URL and keys are printed to the console — use these in your `.env` for local development.

Apply database migrations:

```bash
supabase db push
```

Seed the food database (this may take several minutes due to the size of the USDA dataset):

```bash
supabase db seed
```

Run the app on an emulator or connected device:

```bash
flutter run
```

### Running Tests

```bash
# Unit and widget tests
flutter test

# Integration tests (requires a running emulator)
flutter test integration_test/

# Edge Function tests (requires Supabase running locally)
supabase functions serve process-meal-photo --env-file .env
# Then test with curl or the Supabase dashboard
```

### Building for Release

**Android:**

```bash
flutter build appbundle --release
```

The `.aab` file is generated at `build/app/outputs/bundle/release/app-release.aab`. Upload this to Google Play Console.

**iOS:**

```bash
flutter build ipa --release
```

The `.ipa` file is generated at `build/ios/ipa/tavera.ipa`. Upload this via Xcode Organizer or Transporter to App Store Connect.

---

## Project Structure

```
tavera/
├── docs/
│   ├── CONCEPT.md          # Product concept and vision
│   ├── ARCHITECTURE.md     # System design and technical specification
│   ├── ROADMAP.md          # Development roadmap with checklists
│   └── PRICING.md          # Monetisation strategy and pricing
├── lib/                    # Flutter application source code
│   ├── main.dart           # Entry point
│   ├── app.dart            # MaterialApp configuration
│   ├── router.dart         # GoRouter route definitions
│   ├── theme/              # App theme, colours, typography
│   ├── core/               # Constants, exceptions, extensions, utilities
│   ├── config/             # Environment and Supabase configuration
│   ├── data/
│   │   ├── models/         # Freezed data classes
│   │   ├── repositories/   # Data access layer
│   │   ├── services/       # External service wrappers
│   │   └── local/          # Drift local database
│   ├── providers/          # Riverpod providers
│   └── ui/
│       ├── screens/        # App screens (camera, dashboard, history, etc.)
│       ├── widgets/        # Shared reusable widgets
│       └── shared/         # Shared layouts and dialogs
├── supabase/
│   ├── migrations/         # PostgreSQL migration files
│   ├── seed.sql            # Food database import script
│   └── functions/          # Edge Functions (TypeScript/Deno)
├── test/                   # Unit and widget tests
├── integration_test/       # Integration tests
├── assets/                 # Images, fonts, animations
├── .env.example            # Environment variable template
├── pubspec.yaml            # Flutter dependencies
├── analysis_options.yaml   # Dart linting configuration
└── README.md               # This file
```

---

## Future Plans

The full roadmap is documented in [docs/ROADMAP.md](docs/ROADMAP.md). In summary:

**Phase 1 (Current Target):** Camera-first calorie logging with AI food recognition, daily dashboard, meal history, barcode scanning, offline support, and push notifications. Beta release to 20–50 testers.

**Phase 2:** Adaptive meal memory (known meal pre-filling), AI coaching insights, premium subscription with RevenueCat, paywall implementation, analytics, and public launch on both app stores.

**Phase 3:** Restaurant menu scanning, wearable integration (Apple HealthKit, Google Health Connect), meal scoring, consistency streaks, weekly trend visualisations, fasting timer, grocery list generation, and multi-language support.

**Phase 4:** AI-powered meal planning from personal meal history, grocery list generation from meal plans, accountability partner feature, GLP-1 medication tracking mode, recipe URL import, and food recognition model improvement feedback loop.

**Phase 5:** Professional accounts for dietitians and nutritionists, corporate wellness program support, custom food recognition model training on accumulated data, and food delivery API integrations.

---

## Contributing

Tavera is currently a private project. If you are a developer who has been invited to contribute, please read all four documents in the `docs/` directory before writing any code. The Architecture document contains the complete folder structure, coding conventions, and package decisions. The Roadmap document contains the specific checklist of what needs to be built and in what order.

All code changes must go through a pull request to `main`. PRs require at least one review. Write tests for any new feature or bug fix. Follow the linting rules in `analysis_options.yaml` without exceptions.

---

## License

Proprietary. All rights reserved. This software is not open source.

---

## Contact

For questions about the project, reach out to Dee (Founder).
