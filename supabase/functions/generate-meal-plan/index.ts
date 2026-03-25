// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── generate-meal-plan ───────────────────────────────────────────────────────
//
// Generates a personalised 7-day meal plan + grocery list for a premium user.
// Requires at least 7 days of meal logs to personalise effectively.
//
// POST body:
//   {
//     user_id:    string,
//     week_start: string (YYYY-MM-DD, Monday of the target week)
//   }
//
// Returns: { meal_plan: MealPlan, grocery_list: GroceryList }
//
// Flow:
//   1. Fetch user profile (calorie goal, macros preference if stored)
//   2. Call analyse-eating-patterns internally for personalisation context
//   3. Build GPT-4o prompt with context + preferences
//   4. Parse structured JSON response (7 days × 3–4 meals)
//   5. Derive grocery list from ingredients mentioned in meals
//   6. Upsert both meal_plan and grocery_list rows
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MEAL_PLAN_PROMPT = `You are a professional dietitian creating a personalised 7-day meal plan.
Return ONLY a valid JSON object — no markdown fences, no explanation.

JSON structure:
{
  "ai_notes": "string (≤ 300 chars, friendly overview of the plan strategy)",
  "days": [
    {
      "day_index": 0,
      "meals": [
        {
          "slot": "breakfast" | "lunch" | "dinner" | "snack",
          "name": "string",
          "description": "string (≤ 120 chars, key ingredients + prep method)",
          "calories": number,
          "protein_g": number,
          "carbs_g": number,
          "fat_g": number,
          "prep_minutes": number
        }
      ]
    }
  ],
  "grocery_items": [
    {
      "name": "string",
      "quantity": "string (e.g. '200g', '2 pieces', '1 cup')",
      "category": "produce" | "protein" | "dairy" | "grains" | "pantry" | "condiments" | "beverages" | "frozen" | "other",
      "used_in_meals": ["string"]
    }
  ]
}

Rules:
- day_index 0 = Monday, 6 = Sunday
- Calories per day must be within 10% of the user's calorie_target
- Include 3 meals + 1 optional snack per day
- Vary meals across the week — do not repeat the same dinner twice
- Base suggestions on the user's eating history (top foods) when provided
- Grocery list should consolidate ingredients across all 7 days
- Keep prep times realistic: ≤ 15 min for breakfast/snack, ≤ 30 min for lunch/dinner`;

const GROCERY_PROMPT = `Extract a deduplicated grocery list from the meal plan.
Group items by: produce, protein, dairy, grains, pantry, condiments, beverages, frozen, other.
Consolidate quantities where possible (e.g. "chicken breast 700g" covers multiple days).`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, week_start } = await req.json();

    if (!user_id || !week_start) {
      return new Response(
        JSON.stringify({ error: "user_id and week_start are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── 1. User profile ──────────────────────────────────────────────────────
    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("calorie_goal, name, weight_kg, height_cm, age, sex")
      .eq("id", user_id)
      .single();

    if (profileErr) throw new Error(profileErr.message);

    // ── 2. Eating patterns (internal call) ───────────────────────────────────
    // Reuse the logic inline (avoids an extra HTTP hop to the other function).
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const { data: logs } = await supabase
      .from("meal_logs")
      .select("items")
      .eq("user_id", user_id)
      .gte("logged_at", thirtyDaysAgo.toISOString());

    const foodFreq = new Map<string, number>();
    for (const log of logs ?? []) {
      if (Array.isArray(log.items)) {
        for (const item of log.items) {
          const name = (item.name as string ?? "").toLowerCase().trim();
          if (name) foodFreq.set(name, (foodFreq.get(name) ?? 0) + 1);
        }
      }
    }
    const topFoods = Array.from(foodFreq.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([name]) => name);

    // ── 3. Build GPT prompt ──────────────────────────────────────────────────
    const calorieTarget = profile?.calorie_goal ?? 2000;
    const userContext = `
User: ${profile?.name ?? "there"}
Calorie target: ${calorieTarget} kcal/day
Body stats: ${profile?.weight_kg ? `${profile.weight_kg}kg` : "unknown"} | ${profile?.height_cm ? `${profile.height_cm}cm` : "unknown"} | ${profile?.age ?? "unknown"} yo | ${profile?.sex ?? "unknown"}
Frequently eaten foods (incorporate where suitable): ${topFoods.join(", ") || "none yet"}
Week of: ${week_start}
`.trim();

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) throw new Error("OPENAI_API_KEY not set");

    // ── 4. Call GPT-4o ───────────────────────────────────────────────────────
    const gptResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o",
        max_tokens: 3000,
        temperature: 0.5,
        messages: [
          { role: "system", content: MEAL_PLAN_PROMPT + "\n\n" + GROCERY_PROMPT },
          { role: "user", content: userContext },
        ],
      }),
    });

    if (!gptResponse.ok) {
      throw new Error(`OpenAI error ${gptResponse.status}: ${await gptResponse.text()}`);
    }

    const gptJson = await gptResponse.json();
    const rawContent = gptJson.choices[0].message.content.trim();
    const planData = JSON.parse(rawContent);

    // ── 5. Upsert meal_plan ───────────────────────────────────────────────────
    const { data: mealPlan, error: planErr } = await supabase
      .from("meal_plans")
      .upsert(
        {
          user_id,
          week_start,
          calorie_target: calorieTarget,
          days: planData.days ?? [],
          ai_notes: planData.ai_notes ?? null,
        },
        { onConflict: "user_id,week_start" }
      )
      .select()
      .single();

    if (planErr) throw new Error(planErr.message);

    // ── 6. Build and upsert grocery_list ────────────────────────────────────
    const groceryItems = (planData.grocery_items ?? []).map(
      (item: {
        name: string;
        quantity: string;
        category: string;
        used_in_meals?: string[];
      }, index: number) => ({
        id: `item_${index}`,
        name: item.name,
        quantity: item.quantity,
        category: item.category,
        is_checked: false,
        used_in_meals: item.used_in_meals ?? [],
      })
    );

    const { data: groceryList, error: groceryErr } = await supabase
      .from("grocery_lists")
      .upsert(
        {
          user_id,
          meal_plan_id: mealPlan.id,
          week_start,
          items: groceryItems,
          is_shared: false,
        },
        { onConflict: "user_id,meal_plan_id" }
      )
      .select()
      .single();

    if (groceryErr) throw new Error(groceryErr.message);

    return new Response(
      JSON.stringify({ meal_plan: mealPlan, grocery_list: groceryList }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("generate-meal-plan error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
