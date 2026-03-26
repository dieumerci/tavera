# TAVERA — App Concept Document

**Document Version:** 1.2
**Last Updated:** March 25, 2026
**Status:** Phase 1 Complete · Phase 2 In Progress
**Author:** Dee (Founder)

---

## What Is Tavera?

Tavera is a mobile-first AI-powered nutrition tracking application that replaces the tedious, manual process of calorie and macro logging with a camera-first experience. The user points their phone at a meal, the app's AI identifies the food on the plate, estimates portion sizes, and returns calorie and macronutrient data in under five seconds. The user confirms with a single tap, and the meal is logged.

That is the surface interaction. Underneath, Tavera is a behaviour change product disguised as a tracking tool. The app learns from every meal the user logs, building a personal food profile that reduces logging friction over time. Frequent meals are pre-filled. Patterns are surfaced as coaching insights. Weekly summaries tell the user something actionable about their eating habits, not just what they ate but what they should consider changing and why.

Tavera exists because calorie tracking works but people quit. Research consistently shows that 70% of users abandon nutrition tracking apps within two weeks. The reason is not that tracking is ineffective — it is that tracking is exhausting. Searching through databases of thousands of foods, estimating serving sizes, manually entering every ingredient of a home-cooked meal — the cognitive load is unsustainable for most people. Tavera eliminates that load. The camera does the work. The AI does the estimation. The user does one tap.

The name Tavera draws inspiration from the Italian word "tavola" meaning table — the place where meals happen, where families gather, where the relationship with food lives. It positions the product as warm, human, and food-positive rather than clinical, punitive, or diet-obsessed. This is intentional. The brand exists in opposition to apps that make users feel guilty about eating. Tavera helps users understand what they eat so they can make better choices, not fewer choices.

---

## The Problem Tavera Solves

The global nutrition tracking market is valued at over $4 billion in 2026 and growing at roughly 9% annually. MyFitnessPal, the incumbent, has over 200 million registered users. Health and fitness apps collectively generated over $6 billion in mobile revenue in 2025. The market is proven, the willingness to pay is demonstrated, and the behaviour (tracking food to manage weight or health) is deeply embedded in consumer culture.

Yet the category has a catastrophic retention problem. The core user experience of manually searching a food database, selecting portion sizes, and repeating this process three to five times per day for weeks or months is fundamentally unsustainable for most humans. Power users persist, but the vast majority of downloaders churn within days.

This is the problem Tavera solves. Not "how do I count calories" — that problem is solved. The problem is "how do I keep counting calories without it consuming my life." Tavera's answer is to make the act of logging so fast and so effortless that it stops feeling like a chore and starts feeling like a two-second habit, no more burdensome than checking the time on your phone.

The secondary problem Tavera solves is the insight gap. Most nutrition apps show users what they ate. Very few tell users what to do about it. A pie chart showing that 45% of your calories came from carbohydrates is data, not insight. Tavera's coaching layer translates tracking data into personalised, actionable recommendations. "You consistently skip protein at breakfast. Adding a single egg would put you on target for the entire day." That is an insight. That changes behaviour.

---

## Who Is Tavera For?

Tavera's primary audience is health-conscious adults aged 25 to 45 who have attempted calorie tracking before and either succeeded but found it tedious, or abandoned it because the friction was too high. This audience already understands the value of tracking. They do not need to be educated on why it matters. They need a tool that respects their time.

Within this primary audience, several segments stand out as particularly high-value:

**The MyFitnessPal Dropout.** This user downloaded MyFitnessPal, used it enthusiastically for one to three weeks, then stopped because manual logging became overwhelming. They still want to track. They just need a faster way. Tavera is built for this person.

**The GLP-1 Medication User.** Users on Ozempic, Wegovy, Mounjaro, and similar medications represent a large, growing, and extremely motivated segment. These users are medically required to track protein intake carefully during weight loss. They are willing to pay premium prices for tools that support their treatment. Tavera's protein-aware coaching layer is directly relevant to their needs.

**The Fitness-Aware Professional.** This user goes to the gym three to five times per week, understands macros, and wants to optimise their nutrition for performance or body composition goals. They currently use MyFitnessPal or Cronometer and tolerate the friction because they are highly motivated. Tavera offers them the same data with dramatically less effort.

**The Busy Parent.** This user cares about nutrition but has zero spare time for manual food logging. They eat the same meals frequently, cook for a family, and need a tool that learns their routine and makes tracking invisible. Tavera's adaptive meal memory is designed for this user.

Tavera's secondary audience includes dietitians and nutritionists who want their clients to use a tracking tool that is simple enough to maintain compliance, and corporate wellness programs looking for a nutrition tracking benefit to offer employees.

---

## How Tavera Works — The Core User Experience

The experience begins when the user opens the app at mealtime. The **Dashboard** is the default home screen — showing today's calorie progress ring, macro bars, and the user's logged meals for the day. This gives the user immediate context: "Here's where you are. Here's what you've eaten." Food capture is one tap away.

To log a meal, the user taps the **+ button** in the centre of the bottom navigation bar. A sheet appears with four options: Take a Photo, Upload from Gallery, Scan Barcode, or Quick Add. Most users tap "Take a Photo," which opens the camera. They point at their plate and tap capture. The image is sent to Tavera's food recognition AI, which identifies individual food items, estimates portions, and returns a calorie and macronutrient breakdown in under five seconds.

The result appears as an editable card: "Grilled chicken breast (approx 150g) — 248 kcal, 46g protein, 0g carbs, 5g fat." Below it, other items on the plate are listed. The user reviews, adjusts any estimates with a portion slider, and taps confirm. The meal is logged. The Dashboard ring updates in real time.

**Important: Steps / activity tracking is explicitly out of scope.** Tavera focuses exclusively on nutrition. Calorie burn from exercise is not tracked, and step-count integration is not planned.

Over time, the app builds a personal food library. If the user eats oatmeal with banana every weekday morning, Tavera recognises this pattern and pre-fills the meal at 7am with a single confirmation tap required. The camera is bypassed entirely for known meals. This adaptive learning is the core retention mechanism — the app gets faster and easier to use with every meal logged, creating increasing switching costs.

Beyond logging, the Dashboard provides a real-time view of calorie progress, macronutrient balance, and hydration. A weekly insights screen delivers one to three coaching observations: patterns detected, recommendations offered, and progress acknowledged. These insights are generated by AI analysis of the user's logged meals and are personalised to their specific eating patterns, not generic nutrition advice.

The user also receives push notifications at their typical meal times, gently reminding them to log. These notifications are smart — they only fire if the user has not already logged a meal in the expected window, and they stop appearing for meals the user consistently skips.

---

## What Makes Tavera Different

The calorie tracking market is crowded. MyFitnessPal, Cronometer, Lose It, Yazio, Lifesum, Noom, MacroFactor, and dozens of smaller apps compete for the same users. Tavera's differentiation is not a single feature but a product philosophy: every design decision optimises for logging speed and long-term retention over data completeness.

Most nutrition apps are designed by and for data maximalists. They offer 84 micronutrient fields, custom macro ratios, integration with seventeen wearables, and databases of fourteen million foods. This appeals to power users but overwhelms everyone else. Tavera deliberately constrains the initial experience to the minimum data that drives behaviour change: calories, protein, carbohydrates, and fat. Micronutrients are available in premium but never forced on the user.

The camera-first interaction model is not unique — Cal AI, Lose It's Snap It feature, and others have photo logging. But in most competing products, photo logging is a feature within a database-search-first app. In Tavera, the camera IS the app. The database search exists as a fallback, not the primary flow. This distinction matters because it shapes the entire UX hierarchy, onboarding flow, and user expectation.

The adaptive meal memory — learning frequent meals and pre-filling them — exists in no major competitor at the level Tavera intends to implement it. MyFitnessPal has a "recent meals" list. Tavera builds a predictive model of the user's eating patterns: what they eat, when they eat it, how often, and in what combinations. The goal is to reduce average logging time from twelve seconds per meal in week one to three seconds per meal by week four.

The coaching layer, powered by AI analysis of longitudinal eating data, differentiates Tavera from pure tracking tools. Cronometer gives you micronutrient data but no interpretation. MyFitnessPal shows you a calorie graph but no recommendations. Noom offers coaching but charges $59/month and relies on human coaches. Tavera provides AI coaching at consumer pricing, with insights that are specific to your data, not generic nutrition tips.

---

## The Business Model

Tavera operates on a freemium subscription model. The free tier provides enough functionality to demonstrate value and build habit, while the premium tier unlocks the intelligence and coaching features that drive long-term retention and justify ongoing payment.

The pricing and tier structure is detailed in the separate Pricing Document (PRICING.md), but the philosophical approach is as follows: free users should be able to track meals by photo and see their daily calorie total. They should experience the speed advantage over manual logging. They should understand that Tavera is meaningfully faster. But they should also feel the absence of the intelligence layer — the coaching insights, the adaptive meal memory, the macro tracking, and the weekly summaries — strongly enough that upgrading feels like an obvious decision, not a grudging one.

Tavera will never show advertisements. The product is funded entirely by subscriptions. This is a deliberate trust decision: users are sharing intimate data about what they eat every day, and advertising-funded models create incentive misalignment between the product and the user. Subscription alignment means Tavera succeeds only when users find enough value to keep paying, which means the product must actually work.

---

## The Long-Term Vision

Tavera begins as a calorie tracking app. It becomes a personal nutrition intelligence platform.

**Year 1 — Core logging and retention.** The product is focused entirely on logging speed, accuracy, and habit formation. Dashboard-first UX. Camera-powered food capture. Smart notifications. Coaching insights. The goal is to prove that fast, frictionless logging retains users longer than database-search-first logging, and to build a data asset of meal photos and nutritional estimates that improves the AI model over time.

**Phase 2 expansion — Two high-value retention layers:**

*Social Accountability Challenges.* Users can create or join group nutrition and health challenges with friends — e.g. "7-Day Protein Challenge" or "No Sugar Week." The AI tracks each participant's progress, sends personalised motivating notifications throughout the challenge, generates a leaderboard showing progress and ranking, and auto-creates visual infographics summarising the user's journey when a challenge ends. Users can share achievements on social media. This feature is intentionally positioned as a retention, motivation, and virality layer: challenges keep users logging on days they might otherwise skip, and social sharing brings new users into the product organically.

*AI Meal Planner with Grocery Integration.* After a user has tracked meals for at least one week, the AI generates a personalised weekly meal plan based on their eating patterns, nutritional gaps, goals, and behaviour trends. The plan automatically produces a grocery list with exact quantities, grouped by category. The architecture is designed from the start to support integration with grocery delivery services (Instacart, Amazon Fresh) as a Phase 3 feature. This is positioned as a strong value-add that deepens product utility, creates daily engagement beyond logging, and provides a natural future premium monetisation opportunity.

**Year 2 — Meal planning maturity and professional layer.** Tavera expands into mature meal planning: multi-week plans, accountability partnerships, GLP-1 medication tracking mode, and recipe URL import. The professional layer opens to dietitians and nutritionists — viewing client logs in real time and providing guided coaching creates a B2B revenue stream.

**Year 3 — Data moat and custom AI.** The compounding data advantage becomes the product's primary defensibility. Millions of meal photos and user-confirmed nutritional estimates enable a custom food recognition model that outperforms general-purpose vision APIs for food specifically. Grocery delivery integrations, corporate wellness programmes, and API partnerships extend the product surface.

The long-term defensibility of Tavera is its data moat. Every meal logged improves the AI's food recognition accuracy. Every challenge completed contributes behavioural data that improves the motivational notification system. Every meal plan generated and followed feeds back into the personalisation engine. This compounding advantage becomes harder for competitors to replicate over time.

---

## Core Values

**Speed over completeness.** A fast, approximate log that the user actually makes is infinitely more valuable than a precise log they abandon. Tavera optimises for the former.

**Coaching over data.** Showing users what they ate is a feature. Telling users what to do about it is a product. Tavera is a coaching product that uses tracking as its data input.

**Warmth over judgment.** Tavera never shames users for what they eat. A 3,000-calorie day is logged with the same neutral tone as a 1,500-calorie day. The app helps users understand their patterns without moralising about their choices.

**Mobile-native, not mobile-adapted.** Every feature is designed for the phone first. If a feature would work better on a desktop dashboard, it does not belong in Tavera's MVP. The phone camera, push notifications, on-the-go interactions, and quick check-ins are the product surface.

---

*This document should be read alongside ARCHITECTURE.md, ROADMAP.md, and PRICING.md for the complete product and technical specification.*
