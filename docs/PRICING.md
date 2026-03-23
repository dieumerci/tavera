# TAVERA — Pricing & Monetisation Strategy

**Document Version:** 1.0  
**Last Updated:** March 23, 2026  
**Status:** Pre-Development  
**Author:** Dee (Founder)

---

## Monetisation Philosophy

Tavera is funded entirely by user subscriptions. There are no advertisements, no data sales, no affiliate commissions on food products, and no sponsored content within the app. This decision is non-negotiable and foundational to the product's trust relationship with users.

Users share deeply personal data with Tavera: what they eat, when they eat, how much they weigh, and what their health goals are. Any monetisation model that creates incentive misalignment — where the company profits from something other than the user's success — would erode the trust required for long-term retention. Subscription alignment means Tavera only succeeds when users find the product valuable enough to keep paying, which means every product decision must serve the user's outcomes.

The freemium model is chosen over a paid-only model because calorie tracking apps require habit formation before users recognise value. A user who downloads Tavera must experience the speed advantage of camera-first logging before they encounter any payment request. The free tier exists to build the habit. The premium tier exists to deepen the value.

---

## Pricing Structure

### Free Tier — "Tavera Basic"

The free tier provides enough functionality to demonstrate Tavera's core value proposition — that photo-based calorie logging is dramatically faster than manual database search — while creating clear, felt limitations that motivate upgrading.

**What is included in the free tier:**

Camera-based meal logging is available, limited to three photo logs per day. This limit is chosen deliberately: three logs covers breakfast, lunch, and dinner for a single day, allowing the user to experience the full daily flow. However, snacks, second portions, drinks, and any additional logging requires premium. The limit is generous enough that users do not feel punished, but restrictive enough that active trackers feel constrained within the first week.

Daily calorie tracking is available. The user sees their total calories consumed against their daily target. This is the minimum viable dashboard that makes tracking useful.

Manual quick-add is unlimited. Users can always type in a meal name and estimated calories. This ensures the free tier is never completely blocked, even after the photo limit is reached.

Barcode scanning is available for packaged foods, limited to five scans per day. Barcode data is factual and not a premium differentiator — gating it entirely would feel adversarial.

Seven-day meal history is available. Free users can see the last seven days of logged meals. Older history is stored but hidden behind the paywall. This creates a "loss aversion" dynamic: the user knows their data exists but cannot access it without upgrading.

Basic push notification reminders at meal times are included.

**What is excluded from the free tier:**

Macronutrient breakdown (protein, carbs, fat) is premium-only. Free users see only total calories. This is one of the most effective conversion drivers because users who care enough to track calories almost always want to see their macros, and the data is already captured — it is simply hidden.

Adaptive meal memory (known meal pre-filling) is premium-only. Free users must use the camera or manual entry every time. Premium users experience the app getting faster over time. This creates a widening experience gap between free and premium.

AI coaching insights are premium-only. Free users see a blurred preview of their weekly insights with an upgrade prompt. The preview shows that insights exist and are personalised, creating curiosity and FOMO.

Unlimited photo logging is premium-only. Free users are capped at three per day.

Meal history beyond seven days is premium-only.

Data export (CSV) is premium-only.

Restaurant menu scanning is premium-only (Phase 3).

Wearable integration is premium-only (Phase 3).

Meal planning is premium-only (Phase 4).

### Premium Tier — "Tavera Premium"

**Monthly plan:** $9.99 per month. No trial. Immediate access to all premium features.

**Annual plan:** $69.99 per year (effective $5.83 per month, a 42% discount over monthly). Includes a 7-day free trial. The trial auto-converts to a paid annual subscription unless cancelled.

The annual plan is the primary conversion target. Research from RevenueCat and Adapty consistently shows that annual plans produce higher lifetime value, better retention at second renewal, and stronger overall revenue per user in the health and fitness category. Health and fitness is one of the only app categories where annual plans outperform weekly plans, because users set long-term goals (lose 10kg, build muscle, maintain weight) that align with annual commitment psychology.

The 7-day free trial on the annual plan is chosen because data from the Adapty State of In-App Subscriptions 2026 report shows that trials lasting 7 days have strong conversion rates in health and fitness without excessive freeloading. The trial-to-paid conversion rate benchmark for top health and fitness apps is 39.9% at median, with top performers reaching 68.3%.

The monthly plan exists without a trial because monthly subscribers are typically more exploratory and less committed. Offering a trial on the monthly plan leads to higher trial abuse and lower conversion. Users who want to "test" the app should use the annual trial.

**What premium includes (everything in free, plus):**

Unlimited photo logging (no daily cap), full macronutrient tracking (protein, carbs, fat displayed on dashboard and per meal), adaptive meal memory with one-tap known meal logging, weekly AI coaching insights personalised to the user's eating patterns, full meal history (unlimited days), data export to CSV, restaurant menu scanning (Phase 3), wearable data integration (Phase 3), meal planning and grocery lists (Phase 4), and priority support.

---

## Pricing Rationale

The $9.99/month price point is positioned deliberately within the health and fitness subscription range. MyFitnessPal Premium is $19.99/month. Noom is $59/month. Yazio is $11.99/month. Lose It Premium is $39.99/year. MacroFactor is $71.99/year.

At $9.99/month, Tavera is cheaper than MyFitnessPal and significantly cheaper than Noom, while offering a more modern, camera-first experience. The annual price of $69.99 positions it competitively against MacroFactor ($71.99) and Lose It ($39.99). The price is high enough to signal quality — research consistently shows that higher-priced apps convert trial users at higher rates because the download-to-trial audience is more intent-driven.

The price should not be lowered below $7.99/month. Lower pricing attracts price-sensitive users with lower retention and higher support costs. The target user — someone who has tried and abandoned MyFitnessPal and is willing to pay for a better experience — is not price-sensitive at this range.

---

## Regional Pricing

Apple and Google both support regional pricing tiers. Tavera should use localised pricing in key markets to maximise conversion without leaving money on the table in high-spending markets.

**Tier 1 (full price):** United States, Canada, United Kingdom, Australia, Western Europe (Germany, France, Netherlands, Switzerland, Nordic countries), Japan, South Korea.

**Tier 2 (approximately 30% discount):** Southern Europe (Spain, Italy, Portugal), Eastern Europe (Poland, Czech Republic, Romania), Middle East (UAE, Saudi Arabia), Singapore, Hong Kong.

**Tier 3 (approximately 50–60% discount):** Latin America (Brazil, Mexico, Argentina, Colombia), India, Southeast Asia (Indonesia, Philippines, Thailand, Vietnam), Turkey, South Africa, Nigeria, Egypt.

Adapty's pricing index data shows that users in the Netherlands pay 62% more than US users, while Turkish users pay 71% less. Regional pricing is not optional for a globally distributed app — it is a core revenue optimisation strategy.

In practice, this means the annual plan might be $69.99 in the US, €64.99 in Germany, R$179.99 in Brazil, ₹2,499 in India, and ₺349.99 in Turkey. Apple and Google handle currency conversion and local payment methods.

---

## Paywall Strategy

The paywall is the most important screen in the app from a business perspective. It must communicate value clearly, reduce anxiety about commitment, and present the pricing without feeling aggressive.

**When the paywall appears:**

The paywall is never shown during onboarding. The user must experience at least one successful camera-to-calorie log before seeing any payment request. First value, then ask.

The paywall appears when the user hits a free tier limit: fourth photo log attempt, first time tapping "macros" on the dashboard, first time scrolling past seven days in history, or when coaching insights are available but blurred. This "contextual paywall" approach converts better than a generic "upgrade" button because the user encounters the paywall at the exact moment they want the feature.

A "soft" paywall notification appears after the user's seventh day of active use (if they have not already upgraded). This is a non-blocking banner at the top of the dashboard that says something like: "You've logged 23 meals this week. Unlock coaching insights to see what your patterns reveal." It is dismissible and does not reappear for 7 days if dismissed.

**What the paywall shows:**

The paywall screen leads with the value, not the price. Three to four key benefits are shown with brief descriptions and visual icons: "See your full macros," "Known meals, one tap," "Weekly AI coaching," and "Unlimited photo logs." Below the benefits, the two pricing options are presented with the annual plan pre-selected and visually emphasised. The annual plan shows the effective monthly price ($5.83/mo) and the savings versus monthly ($50.89 saved per year). A "Start 7-Day Free Trial" button is the primary call to action for the annual plan. A secondary, smaller link shows "Or subscribe monthly at $9.99/mo."

Below the pricing, a brief reassurance line: "Cancel anytime. No questions asked." This reduces commitment anxiety.

**What the paywall does not do:**

It does not use countdown timers, fake urgency, dark patterns, or misleading language. It does not auto-subscribe without clear user action. It does not make the close button hard to find. It does not repeat after every app interaction. These tactics generate short-term revenue but destroy long-term trust and increase refund rates, which damage App Store ratings.

---

## Revenue Projections (Conservative)

These projections assume organic growth with minimal paid acquisition, typical for a solo-developer app in the first year.

**Month 1–3 (Beta + Launch):** 500 downloads, 5% trial start rate (25 trials), 40% trial conversion (10 paid users), approximately $70–100/month revenue.

**Month 4–6:** 2,000 cumulative downloads, 8% trial start rate as ASO improves, 10% of free users hit limits and see paywall. Approximately 80 paid users. Revenue: $500–800/month.

**Month 7–12:** 8,000 cumulative downloads. Word-of-mouth begins contributing. Approximately 400 paid users (mix of monthly and annual). Revenue: $2,500–4,000/month. At this point, the app is covering its own infrastructure costs and beginning to generate modest profit.

**Year 2:** With targeted content marketing, social media presence, and potential press coverage, 30,000–50,000 cumulative downloads is achievable. At 5–8% conversion to paid and reasonable retention, 1,500–3,000 paying subscribers generating $10,000–25,000/month is realistic. This is the point where Tavera becomes a viable full-time business.

These projections are deliberately conservative. The calorie tracking category has strong organic discovery in app stores because users actively search for these tools. A 4.7+ star rating with good reviews can drive significant organic downloads without paid acquisition spend.

---

## Future Revenue Streams (Phase 4–5)

**Professional tier ($29.99/month):** Dietitians and nutritionists who connect with clients through Tavera. Revenue scales with the number of professionals, not the number of clients (professionals pay, clients use their existing consumer subscription).

**Corporate wellness ($5–10/employee/month):** Employers offer Tavera Premium as a health benefit. Revenue is recurring, high-volume, and low-churn because it is billed to the employer, not the individual. A single corporate client with 500 employees generates $2,500–5,000/month.

**API licensing:** If Tavera's food recognition model reaches high accuracy through training on its proprietary meal photo dataset, the model can be licensed to other health and wellness apps that need food recognition but do not want to build it themselves.

These future revenue streams are documented for strategic planning but should not influence Phase 1–3 product decisions. Consumer subscription revenue must be proven first.

---

## Metrics to Track

The following metrics should be monitored weekly from launch onwards to evaluate pricing and monetisation performance:

**Trial start rate:** Percentage of free users who start a trial. Target: above 8%.

**Trial-to-paid conversion rate:** Percentage of trial users who convert to paid. Target: above 40% (category median is 39.9%).

**Monthly recurring revenue (MRR):** Total subscription revenue per month. The north star business metric.

**Average revenue per user (ARPU):** MRR divided by total active users (free and paid). Indicates monetisation efficiency.

**Subscriber retention at day 30:** Percentage of subscribers still active after 30 days. Target: above 70%.

**Annual plan renewal rate:** Percentage of annual subscribers who renew after 12 months. Target: above 50% (category benchmark for health and fitness is approximately 30%, so 50% would indicate strong product-market fit).

**Paywall view-to-trial rate:** Of users who see the paywall, what percentage starts a trial. This measures paywall effectiveness and should be A/B tested.

**Refund rate:** Percentage of subscriptions refunded. Should stay below 5%. High refund rates indicate misleading paywall copy or poor post-purchase experience.

---

*This document should be read alongside CONCEPT.md, ARCHITECTURE.md, ROADMAP.md, and the root README.md.*
