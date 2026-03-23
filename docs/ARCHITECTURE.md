# TAVERA — System Architecture & Technical Design

**Document Version:** 1.0  
**Last Updated:** March 23, 2026  
**Status:** Pre-Development  
**Author:** Dee (Founder)

---

## Architecture Overview

Tavera is a cross-platform mobile application built with Flutter, backed by Supabase as the primary backend-as-a-service platform, with dedicated AI services for food recognition and coaching intelligence. The architecture is designed around three principles: speed of iteration for a solo developer or small team, real-time responsiveness for the user experience, and modularity so that individual components (AI model, backend, mobile client) can be upgraded or replaced independently as the product scales.

The system is composed of four layers: the mobile client, the backend platform, the AI processing pipeline, and external integrations. Each layer communicates through well-defined interfaces, and the architecture intentionally avoids tight coupling between the Flutter client and any specific backend implementation, so that a migration from Supabase to a custom backend is possible in the future without rewriting the mobile app.

---

## Technology Stack — Complete Reference

### Mobile Client

**Framework:** Flutter (Dart)  
**Minimum SDK:** Flutter 3.22+ / Dart 3.4+  
**Target Platforms:** iOS 15+ and Android 10+ (API level 29+)  
**State Management:** Riverpod 2.x — chosen over Bloc for less boilerplate and better testability in a small team. Riverpod's code generation with `riverpod_annotation` reduces ceremony while maintaining type safety.  
**Navigation:** GoRouter — Flutter's recommended declarative routing solution with deep linking support, which is required for push notification handling and future web companion.  
**Local Storage:** Hive for lightweight key-value caching (user preferences, cached meal data), SQLite via Drift for structured local meal history and offline queue.  
**Camera:** The `camera` package for direct viewfinder control combined with `image_picker` as a fallback. Images are compressed client-side to a maximum of 1024x1024 pixels at 85% JPEG quality before upload, balancing AI recognition accuracy against upload speed and storage cost.  
**Push Notifications:** Firebase Cloud Messaging (FCM) for both iOS and Android. Even though the primary backend is Supabase, FCM remains the industry standard for reliable cross-platform push delivery. The `firebase_messaging` Flutter package handles foreground and background notification receipt.  
**Analytics:** PostHog (self-hostable, privacy-focused) for product analytics, funnel tracking, and feature flag management. Preferred over Firebase Analytics because PostHog provides session recording and feature flags in a single tool without Google's data practices.  
**Crash Reporting:** Sentry for Flutter. Provides real-time crash reporting with Dart stack traces, breadcrumbs, and release health monitoring.  
**HTTP Client:** Dio with interceptors for authentication token injection, request retry logic, and error standardisation.  
**Image Processing:** The `image` Dart package for client-side resizing and compression before upload.

### Backend Platform

**Primary Backend:** Supabase (hosted)  
**Database:** PostgreSQL 15+ (managed by Supabase) — relational data model for users, meals, foods, coaching insights, subscriptions, and analytics events.  
**Authentication:** Supabase Auth with email/password, Apple Sign-In (required by Apple for App Store), and Google Sign-In. Magic link (passwordless) email authentication as the recommended default to reduce onboarding friction.  
**File Storage:** Supabase Storage for meal photos. Photos are stored in user-scoped buckets with row-level security (RLS) policies ensuring users can only access their own images. A CDN layer serves cached images for the meal history feed.  
**Real-time:** Supabase Realtime for live subscription status changes and future social features. Not used for meal logging (which is request-response) but reserved for features where live updates matter.  
**Edge Functions:** Supabase Edge Functions (Deno/TypeScript) for serverless API endpoints that require logic beyond what Supabase's auto-generated REST API provides. Used for: AI processing orchestration, coaching insight generation, push notification scheduling, and subscription webhook handling.  
**Row-Level Security:** All database tables enforce RLS policies. No client ever accesses another user's data, even if the client code is compromised. This is the primary security boundary.

### AI Processing Pipeline

**Food Recognition API:** Google Cloud Vision API for initial food identification, combined with a custom fine-tuned model hosted on Google Cloud Vertex AI as the product matures. In the MVP phase, the pipeline works as follows: the meal photo is uploaded to Supabase Storage, a Supabase Edge Function is triggered, the Edge Function sends the image to the food recognition service, the service returns identified food items with confidence scores, and the Edge Function maps those items to a nutritional database to produce calorie and macro estimates.

**Nutritional Database:** The USDA FoodData Central database (public domain, over 380,000 food items with verified nutritional data) serves as the foundational data source. This is supplemented by the Open Food Facts database for international packaged foods and barcode data. Both databases are imported into PostgreSQL tables and updated quarterly.

**Portion Estimation:** A secondary AI model estimates portion sizes from the photo using depth cues, plate-relative sizing, and learned portion distributions. In the MVP, this uses a rules-based estimator calibrated against common plate sizes (a standard dinner plate is approximately 26cm in diameter). As the user base grows and meal photo data accumulates, a trained model replaces the rules-based system.

**Coaching Engine:** OpenAI API (GPT-4o-mini for cost efficiency) processes a user's weekly meal data to generate personalised coaching insights. The prompt is structured with the user's goals, their logged meals for the week, detected patterns, and nutritional gaps. The response is constrained to one to three actionable recommendations. This runs as a weekly scheduled Edge Function, not on-demand, to control API costs.

**Adaptive Meal Memory:** A pattern recognition system built in PostgreSQL using temporal queries and frequency analysis. When a user logs the same meal (identified by food item combination and approximate quantities) more than three times, it is promoted to a "known meal" and offered as a one-tap option at the time of day it typically occurs. This does not require a dedicated ML model — it is implemented as SQL queries against the meal history table with time-of-day bucketing.

### External Integrations

**Payments:** RevenueCat for in-app subscription management across iOS and Android. RevenueCat abstracts the differences between Apple's StoreKit and Google Play Billing, provides a unified subscription status API, handles receipt validation, and offers analytics on trial conversion, churn, and LTV. This is critical because implementing cross-platform subscription management from scratch is one of the most error-prone and time-consuming tasks in mobile development.

**Barcode Scanning:** The `mobile_scanner` Flutter package for on-device barcode reading. Scanned barcodes are looked up against the Open Food Facts API for nutritional data. This is a secondary logging method behind photo capture.

**Wearable Integration:** Apple HealthKit (via `health` Flutter package) and Google Health Connect for importing activity data (steps, active calories burned) to adjust the user's daily calorie budget. This is a Phase 3 feature, not MVP.

**Email:** Resend for transactional email (welcome emails, password resets, weekly summary emails for users who opt in). Chosen over SendGrid for simpler API, better developer experience, and lower cost at startup scale.

**Error Monitoring:** Sentry for both the Flutter client and Supabase Edge Functions. A single Sentry project with separate environments (mobile, edge-functions) provides unified error tracking.

---

## System Architecture Diagram (Textual)

```
┌─────────────────────────────────────────────────────────┐
│                    MOBILE CLIENT                         │
│                   (Flutter / Dart)                        │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │  Camera   │  │  Meal    │  │ Dashboard │  │Coaching │ │
│  │  Capture  │  │  History │  │  & Goals  │  │Insights │ │
│  └────┬─────┘  └────┬─────┘  └────┬──────┘  └────┬────┘ │
│       │              │             │               │      │
│       └──────────────┴─────────────┴───────────────┘      │
│                          │                                │
│              ┌───────────┴────────────┐                   │
│              │    Riverpod State      │                   │
│              │    Management          │                   │
│              └───────────┬────────────┘                   │
│                          │                                │
│              ┌───────────┴────────────┐                   │
│              │    Dio HTTP Client     │                   │
│              │    + Auth Interceptor  │                   │
│              └───────────┬────────────┘                   │
└──────────────────────────┼────────────────────────────────┘
                           │
                    HTTPS / REST
                           │
┌──────────────────────────┼────────────────────────────────┐
│                     SUPABASE                              │
│                                                           │
│  ┌────────────┐  ┌────────────┐  ┌─────────────────────┐ │
│  │   Auth     │  │  Storage   │  │   PostgreSQL DB      │ │
│  │ (email,    │  │ (meal      │  │ (users, meals,       │ │
│  │  Apple,    │  │  photos)   │  │  foods, insights,    │ │
│  │  Google)   │  │            │  │  subscriptions)      │ │
│  └────────────┘  └─────┬──────┘  └──────────────────────┘ │
│                        │                                   │
│  ┌─────────────────────┴───────────────────────────────┐  │
│  │              Edge Functions (Deno/TS)                │  │
│  │                                                     │  │
│  │  ┌──────────────┐  ┌────────────┐  ┌─────────────┐ │  │
│  │  │ AI Orchestr. │  │  Coaching  │  │ Push Notif. │ │  │
│  │  │ (food recog) │  │  Engine    │  │ Scheduler   │ │  │
│  │  └──────┬───────┘  └─────┬──────┘  └─────────────┘ │  │
│  └─────────┼────────────────┼──────────────────────────┘  │
└────────────┼────────────────┼─────────────────────────────┘
             │                │
             ▼                ▼
┌────────────────┐  ┌──────────────────┐
│ Google Cloud   │  │   OpenAI API     │
│ Vision /       │  │   (GPT-4o-mini)  │
│ Vertex AI      │  │   Coaching       │
│ Food Recog.    │  │   Insights       │
└────────────────┘  └──────────────────┘

        ┌───────────────────────┐
        │   External Services   │
        │                       │
        │  RevenueCat (subs)    │
        │  FCM (push)           │
        │  Resend (email)       │
        │  Sentry (errors)      │
        │  PostHog (analytics)  │
        │  Open Food Facts API  │
        └───────────────────────┘
```

---

## Database Schema — Core Tables

The database design follows a normalised relational model. All tables use UUID primary keys generated by PostgreSQL's `gen_random_uuid()` function. All tables include `created_at` and `updated_at` timestamp columns with automatic triggers. Row-level security is enforced on every table.

### users
Stores user profile and goal configuration. Linked to Supabase Auth via the `id` field which matches `auth.uid()`.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Matches Supabase Auth user ID |
| email | text | User's email address |
| display_name | text | User's chosen display name |
| goal_type | enum | 'lose', 'maintain', 'gain' |
| daily_calorie_target | integer | Calculated or manually set |
| protein_target_g | integer | Daily protein goal in grams |
| carb_target_g | integer | Daily carb goal in grams |
| fat_target_g | integer | Daily fat goal in grams |
| height_cm | numeric | For BMR calculation |
| weight_kg | numeric | Current weight |
| birth_date | date | For BMR calculation |
| sex | enum | 'male', 'female', 'other' |
| activity_level | enum | 'sedentary' through 'very_active' |
| timezone | text | For correct meal time bucketing |
| onboarding_completed | boolean | Whether initial setup is done |
| subscription_tier | enum | 'free', 'premium' |
| created_at | timestamptz | Account creation |
| updated_at | timestamptz | Last profile update |

### meals
The central table. One row per logged meal.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Meal identifier |
| user_id | uuid (FK → users) | Owner |
| logged_at | timestamptz | When the meal was eaten |
| meal_type | enum | 'breakfast', 'lunch', 'dinner', 'snack' |
| photo_url | text | Path in Supabase Storage |
| total_calories | integer | Sum of all items |
| total_protein_g | numeric | Sum |
| total_carbs_g | numeric | Sum |
| total_fat_g | numeric | Sum |
| is_from_memory | boolean | Was this a pre-filled known meal |
| source | enum | 'photo', 'barcode', 'manual', 'memory' |
| created_at | timestamptz | When logged |
| updated_at | timestamptz | Last edit |

### meal_items
Individual food items within a meal. A meal with chicken, rice, and broccoli has three meal_items rows.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Item identifier |
| meal_id | uuid (FK → meals) | Parent meal |
| food_name | text | Human-readable name |
| food_id | uuid (FK → foods, nullable) | Link to food database if matched |
| quantity_g | numeric | Estimated weight in grams |
| calories | integer | For this item |
| protein_g | numeric | For this item |
| carbs_g | numeric | For this item |
| fat_g | numeric | For this item |
| confidence_score | numeric | AI confidence 0.0 to 1.0 |
| user_adjusted | boolean | Did the user modify the AI estimate |
| created_at | timestamptz | When created |

### foods
The nutritional database. Pre-populated from USDA FoodData Central and Open Food Facts. Values are stored per 100g for easy portion scaling.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Food identifier |
| name | text | Food name |
| source | enum | 'usda', 'openfoodfacts', 'user' |
| external_id | text | ID in source database |
| barcode | text (nullable) | EAN/UPC barcode |
| calories_per_100g | numeric | Energy |
| protein_per_100g | numeric | Protein |
| carbs_per_100g | numeric | Carbohydrates |
| fat_per_100g | numeric | Fat |
| fiber_per_100g | numeric | Fiber |
| serving_size_g | numeric | Common serving size |
| serving_description | text | e.g., "1 medium apple (182g)" |
| category | text | Food category for search |
| created_at | timestamptz | Import date |

### known_meals
The adaptive meal memory. Meals that the user eats frequently enough to be pre-filled.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Known meal identifier |
| user_id | uuid (FK → users) | Owner |
| name | text | Auto-generated or user-named |
| typical_meal_type | enum | Most common time of day |
| typical_hour | integer | Hour (0-23) most commonly logged |
| occurrence_count | integer | Times this meal has been logged |
| last_logged_at | timestamptz | Most recent occurrence |
| total_calories | integer | Nutritional values |
| total_protein_g | numeric | |
| total_carbs_g | numeric | |
| total_fat_g | numeric | |
| items_snapshot | jsonb | Array of meal_items for pre-fill |
| is_active | boolean | Currently offered to user |
| created_at | timestamptz | First detected |
| updated_at | timestamptz | Last occurrence |

### coaching_insights
Weekly AI-generated coaching observations.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Insight identifier |
| user_id | uuid (FK → users) | Owner |
| week_start | date | Monday of the insight's week |
| insight_type | enum | 'pattern', 'recommendation', 'milestone' |
| title | text | Short headline |
| body | text | Full coaching message |
| priority | integer | Display order |
| is_read | boolean | Has the user seen it |
| generated_at | timestamptz | When AI produced it |
| created_at | timestamptz | When stored |

### water_logs
Simple hydration tracking.

| Column | Type | Description |
|--------|------|-------------|
| id | uuid (PK) | Log identifier |
| user_id | uuid (FK → users) | Owner |
| amount_ml | integer | Water consumed |
| logged_at | timestamptz | When consumed |

---

## AI Processing Pipeline — Detailed Flow

When a user captures a meal photo, the following sequence executes:

**Step 1 — Client-side image preparation.** The Flutter app captures the photo, compresses it to 1024x1024 JPEG at 85% quality, and uploads it to Supabase Storage in the user's meal photos bucket. The upload returns a storage path.

**Step 2 — Edge Function invocation.** The Flutter app calls a Supabase Edge Function (`process-meal-photo`) with the storage path and meal metadata (meal type, time of day). The Edge Function retrieves a signed URL for the image from Supabase Storage.

**Step 3 — Food recognition.** The Edge Function sends the image to the food recognition service (Google Cloud Vision API in MVP, Vertex AI custom model later). The service returns a list of identified food items with bounding boxes and confidence scores. Example response: `[{name: "grilled chicken breast", confidence: 0.92, bounds: {...}}, {name: "white rice", confidence: 0.88, bounds: {...}}, {name: "steamed broccoli", confidence: 0.95, bounds: {...}}]`.

**Step 4 — Nutritional lookup.** The Edge Function fuzzy-matches each identified food item against the foods table in PostgreSQL using trigram similarity search (`pg_trgm` extension). For each matched food, it retrieves the per-100g nutritional values.

**Step 5 — Portion estimation.** The Edge Function applies portion estimation logic. In the MVP, this uses default serving sizes from the foods table combined with the confidence-weighted bounds from the food recognition response. A large bounding box relative to the plate suggests a larger portion. The system errs toward overestimation because underestimation of calories is more harmful to the user's goals.

**Step 6 — Response assembly.** The Edge Function assembles the complete meal estimate and returns it to the Flutter client: a list of food items with names, estimated quantities, and nutritional values. The client displays this for user review and confirmation.

**Step 7 — User confirmation.** The user reviews, optionally adjusts portions using the slider interface, and taps confirm. The Flutter app writes the meal and meal_items records to Supabase via the REST API. The confirmed data — including whether the user adjusted the estimates — is logged for model improvement.

**Step 8 — Known meal detection.** A PostgreSQL database trigger or scheduled function checks whether this confirmed meal matches an existing known_meal pattern for the user. If the combination of food items and approximate quantities has been logged three or more times, a known_meal record is created or updated.

The entire pipeline from photo capture to confirmed log should complete in under eight seconds in normal network conditions, with the target being under five seconds.

---

## Offline Strategy

Tavera must function in low-connectivity environments because people eat in places with poor signal: basements, restaurants with concrete walls, airplanes, and rural areas. The offline strategy has three tiers.

**Tier 1 — Known meal logging.** Known meals with cached nutritional data can be logged entirely offline. The meal is written to the local Drift (SQLite) database with a pending sync flag. When connectivity returns, a background sync uploads the meal to Supabase.

**Tier 2 — Manual quick-add.** Users can manually enter a meal name and estimated calories offline. These entries are stored locally and synced when online. No AI processing occurs.

**Tier 3 — Photo queue.** Users can capture a meal photo offline. The photo is stored locally, and processing is deferred. When connectivity returns, the photo is uploaded and processed through the normal AI pipeline. The user receives a notification to confirm the AI's estimates.

The local SQLite database (via Drift) maintains a complete copy of the user's last 30 days of meals, all known meals, and cached foods for offline access. The Supabase Dart client handles conflict resolution using server timestamps — in case of conflict, the most recent write wins.

---

## Security Architecture

**Authentication.** All authentication flows through Supabase Auth. JWT tokens are stored in Flutter's secure storage (`flutter_secure_storage` package, which uses Keychain on iOS and EncryptedSharedPreferences on Android). Tokens are refreshed automatically by the Supabase client. No credentials are ever stored in plain text.

**Row-Level Security.** Every database table has RLS policies that restrict access to the authenticated user's own data. The policies reference `auth.uid()` and are enforced server-side by PostgreSQL, meaning even a compromised client cannot access another user's data.

**Data Encryption.** All data in transit uses TLS 1.3. Supabase encrypts data at rest on its managed PostgreSQL instances. Meal photos in Supabase Storage are stored in private buckets accessible only via signed URLs generated by the Edge Functions.

**API Keys.** The Supabase anon key (public) is used by the Flutter client for authenticated requests only — it provides no access to data without a valid JWT token due to RLS. Service role keys are used only within Edge Functions and never exposed to the client.

**Third-Party API Keys.** Google Cloud Vision API keys, OpenAI API keys, and other service credentials are stored as Supabase Edge Function secrets, never in the Flutter client or version control.

**GDPR and Data Privacy.** Users can export all their data (meals, photos, profile) and delete their account entirely through in-app settings. Account deletion triggers a cascade that removes all user data from the database and storage within 30 days. A separate PRIVACY.md document will detail the complete privacy policy.

---

## Hosting and Distribution

### App Distribution

**Google Play Store.** Published under a Google Play Developer account ($25 one-time registration fee). The app targets Android 10+ (API 29+) to cover approximately 95% of active Android devices. App bundles (.aab) are used for distribution to reduce download size.

**Apple App Store.** Published under an Apple Developer Program account ($99/year). The app requires iOS 15+ to use modern SwiftUI bridge components and HealthKit APIs. Apple Sign-In must be offered alongside other authentication methods per App Store guidelines.

**App Store Optimisation (ASO).** Both store listings require: a compelling icon (camera lens merged with a plate/food visual), screenshots showing the camera-to-calorie flow in under 5 screens, a short video preview demonstrating the speed of photo logging, and keyword-optimised descriptions targeting terms like "calorie tracker," "food photo log," "nutrition AI," and "macro tracker."

### Backend Hosting

**Supabase.** The recommended approach is to start on Supabase's hosted Pro plan ($25/month) which includes 8GB database, 250GB bandwidth, 100GB storage, and 500K Edge Function invocations. As the user base grows beyond approximately 10,000 active users, upgrade to the Team plan ($599/month) for higher limits and priority support. Supabase's infrastructure runs on AWS.

**Google Cloud.** The AI processing services (Cloud Vision, Vertex AI) run on Google Cloud Platform. A dedicated project with budget alerts is configured to prevent unexpected cost overruns during early testing. The estimated cost for food recognition API calls is approximately $1.50 per 1,000 images at Google's current pricing.

**Alternative Self-Hosting Path.** If Supabase costs become prohibitive at scale (100K+ users), the architecture supports migration to a self-hosted Supabase instance on a cloud VM (DigitalOcean, Hetzner, or Railway) or a complete backend rewrite in a framework like Rails or Django. The Flutter client's use of Dio with a configurable base URL means the migration requires changing one configuration value on the client side.

---

## Development Environment Setup

### Prerequisites

Every developer working on Tavera needs the following installed and configured:

**Flutter SDK** — Version 3.22 or later. Install via the official Flutter installation guide for your operating system. Run `flutter doctor` to verify all dependencies including Xcode (macOS), Android Studio, and Chrome.

**Dart SDK** — Bundled with Flutter. Ensure Dart 3.4+ for modern language features including patterns, records, and sealed classes used throughout the codebase.

**Android Studio** — Required for Android emulator and build tools. Install the Android SDK, at minimum API 29 (Android 10) through API 34 (Android 14). Configure an Android Virtual Device (AVD) for testing.

**Xcode** (macOS only) — Required for iOS builds and simulator. Version 15+ for iOS 17 SDK support. Configure a development team in Xcode for device testing.

**Supabase CLI** — Install via `npm install -g supabase` or Homebrew on macOS. Used for local development, database migrations, and Edge Function development. Run `supabase init` to initialise the project and `supabase start` to run a local Supabase instance with PostgreSQL, Auth, Storage, and Edge Functions.

**Node.js 20+** — Required for Supabase CLI and Edge Function development tooling.

**Deno** — Required for writing and testing Supabase Edge Functions locally. Install via `curl -fsSL https://deno.land/install.sh | sh`.

**Google Cloud CLI** — Required for configuring Cloud Vision API access and managing Vertex AI models. Install via `gcloud` installer, authenticate with `gcloud auth login`, and enable the Vision API on your project.

**Git** — Version control. The repository should be hosted on GitHub with branch protection on `main`.

### Project Initialisation

The Flutter project is created with: `flutter create --org com.tavera --project-name tavera tavera_app`. The Supabase project is initialised with `supabase init` inside the project root, creating a `supabase/` directory with migrations, seed files, and Edge Function directories.

Environment variables are managed via a `.env` file (gitignored) with the following keys:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
GOOGLE_CLOUD_VISION_API_KEY=your-key
OPENAI_API_KEY=your-key
REVENUECAT_API_KEY=your-key
SENTRY_DSN=your-dsn
POSTHOG_API_KEY=your-key
RESEND_API_KEY=your-key
```

The Flutter app reads these via the `flutter_dotenv` package for development and build-time `--dart-define` flags for production builds.

---

## Key Flutter Packages (Complete List for Phase 1-3)

| Package | Purpose | Phase |
|---------|---------|-------|
| supabase_flutter | Supabase client (auth, db, storage, realtime) | 1 |
| riverpod / riverpod_annotation | State management | 1 |
| go_router | Navigation and deep linking | 1 |
| dio | HTTP client for custom API calls | 1 |
| camera | Direct camera control for meal capture | 1 |
| image_picker | Gallery fallback for meal photos | 1 |
| image | Client-side image compression | 1 |
| mobile_scanner | Barcode scanning for packaged foods | 1 |
| flutter_dotenv | Environment variable management | 1 |
| flutter_secure_storage | Secure credential storage | 1 |
| hive / hive_flutter | Lightweight local key-value cache | 1 |
| drift / sqlite3_flutter_libs | Structured local database for offline | 1 |
| firebase_messaging / firebase_core | Push notifications via FCM | 1 |
| cached_network_image | Efficient meal photo loading in history | 1 |
| fl_chart | Calorie and macro progress charts | 1 |
| sentry_flutter | Crash reporting and error tracking | 1 |
| purchases_flutter | RevenueCat SDK for subscriptions | 2 |
| posthog_flutter | Product analytics and feature flags | 2 |
| health | Apple HealthKit and Google Health Connect | 3 |
| share_plus | Share meal summaries or reports | 3 |
| flutter_local_notifications | Local notification scheduling | 1 |
| shimmer | Loading state animations | 1 |
| freezed / json_serializable | Immutable data classes and JSON codegen | 1 |

---

## Folder Structure (Flutter Project)

```
tavera_app/
├── lib/
│   ├── main.dart                      # App entry point
│   ├── app.dart                       # MaterialApp configuration
│   ├── router.dart                    # GoRouter route definitions
│   ├── theme/
│   │   ├── app_theme.dart             # ThemeData and color scheme
│   │   └── typography.dart            # Text styles
│   ├── core/
│   │   ├── constants.dart             # App-wide constants
│   │   ├── exceptions.dart            # Custom exception types
│   │   ├── extensions/                # Dart extension methods
│   │   └── utils/                     # Shared utilities
│   ├── config/
│   │   ├── env.dart                   # Environment variable access
│   │   └── supabase_config.dart       # Supabase client initialisation
│   ├── data/
│   │   ├── models/                    # Freezed data classes
│   │   │   ├── user_model.dart
│   │   │   ├── meal_model.dart
│   │   │   ├── meal_item_model.dart
│   │   │   ├── food_model.dart
│   │   │   ├── known_meal_model.dart
│   │   │   └── coaching_insight_model.dart
│   │   ├── repositories/              # Data access layer
│   │   │   ├── auth_repository.dart
│   │   │   ├── meal_repository.dart
│   │   │   ├── food_repository.dart
│   │   │   ├── coaching_repository.dart
│   │   │   └── user_repository.dart
│   │   ├── services/                  # External service wrappers
│   │   │   ├── ai_service.dart        # Food recognition API calls
│   │   │   ├── push_service.dart      # FCM configuration
│   │   │   ├── analytics_service.dart # PostHog events
│   │   │   └── subscription_service.dart # RevenueCat
│   │   └── local/                     # Local database (Drift)
│   │       ├── database.dart
│   │       └── tables/
│   ├── providers/                     # Riverpod providers
│   │   ├── auth_providers.dart
│   │   ├── meal_providers.dart
│   │   ├── dashboard_providers.dart
│   │   └── coaching_providers.dart
│   └── ui/
│       ├── screens/
│       │   ├── onboarding/
│       │   ├── camera/                # Camera capture screen
│       │   ├── meal_review/           # AI results review and confirm
│       │   ├── dashboard/             # Daily calorie and macro view
│       │   ├── history/               # Past meal feed
│       │   ├── insights/              # Coaching insights screen
│       │   ├── settings/              # Profile, goals, subscription
│       │   └── paywall/               # Premium upgrade screen
│       ├── widgets/                   # Shared reusable widgets
│       │   ├── calorie_ring.dart
│       │   ├── macro_bar.dart
│       │   ├── meal_card.dart
│       │   ├── portion_slider.dart
│       │   └── known_meal_chip.dart
│       └── shared/                    # Shared layouts, dialogs
├── supabase/
│   ├── migrations/                    # Database migration SQL files
│   ├── seed.sql                       # USDA food data import
│   └── functions/                     # Edge Functions
│       ├── process-meal-photo/
│       ├── generate-coaching/
│       ├── schedule-notifications/
│       └── webhook-revenuecat/
├── test/                              # Unit and widget tests
├── integration_test/                  # Integration tests
├── assets/                            # Images, fonts, animations
├── .env                               # Local environment (gitignored)
├── .env.example                       # Template for environment variables
├── pubspec.yaml                       # Flutter dependencies
├── analysis_options.yaml              # Dart linting rules
└── README.md                          # Setup and contribution guide
```

---

## Scaling Considerations

**0–1,000 users:** Supabase Pro plan handles everything. Edge Function cold starts are the main performance concern. Keep the food recognition API call under the Edge Function's 60-second timeout by setting reasonable image size limits.

**1,000–10,000 users:** The food database grows large enough that full-text search performance matters. Add PostgreSQL GIN indexes on the foods table `name` column with `pg_trgm`. Consider caching the top 1,000 most-logged foods in a materialised view refreshed hourly.

**10,000–50,000 users:** Evaluate whether Supabase's Team plan is cost-effective versus a self-hosted alternative. The AI processing costs become significant. Implement client-side caching of food recognition results for previously photographed meals to reduce API calls.

**50,000+ users:** Consider training a custom food recognition model on the accumulated meal photo dataset (with user consent). This reduces per-inference costs dramatically compared to Google Cloud Vision API and improves accuracy on the specific types of meals Tavera's users eat. At this scale, a dedicated ML engineer is needed.

---

*This document should be read alongside CONCEPT.md, ROADMAP.md, PRICING.md, and the root README.md.*
