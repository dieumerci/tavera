// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── generate-meal-plan ───────────────────────────────────────────────────────
//
// Generates a personalised 7-day meal plan + grocery list for a premium user.
// Requires at least 7 days of meal logs to personalise effectively.
//
// POST body (full week):
//   { user_id: string, week_start: string (YYYY-MM-DD) }
//
// POST body (single day regeneration):
//   { user_id: string, week_start: string, day_index: number (0=Mon…6=Sun) }
//
// When day_index is provided: regenerates only that day's meals and merges
// them back into the existing plan without touching the other 6 days.
//
// Returns: { meal_plan: MealPlan, grocery_list: GroceryList }
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

const SINGLE_DAY_PROMPT = `You are a professional dietitian regenerating meals for ONE specific day.
Return ONLY a valid JSON object — no markdown fences, no explanation.

JSON structure:
{
  "day_index": number,
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

Rules:
- Return exactly the day_index requested
- Calories for the day must be within 10% of the user's calorie_target
- Include 3 meals + 1 optional snack
- Do NOT repeat meals from the existing_meals context provided
- Keep prep times realistic: ≤ 15 min for breakfast/snack, ≤ 30 min for lunch/dinner`;

const GROCERY_PROMPT = `Extract a deduplicated grocery list from the meal plan.
Group items by: produce, protein, dairy, grains, pantry, condiments, beverages, frozen, other.
Consolidate quantities where possible (e.g. "chicken breast 700g" covers multiple days).`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { user_id, week_start, day_index } = body as {
      user_id: string;
      week_start: string;
      day_index?: number;
    };

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

    // ── 2. Eating patterns (inline — avoids extra HTTP hop) ──────────────────
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

    const calorieTarget = profile?.calorie_goal ?? 2000;
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY not set");

    // ── Branch: single-day regeneration ─────────────────────────────────────
    if (day_index !== undefined) {
      return await _regenerateDay({
        supabase, user_id, week_start, day_index,
        calorieTarget, topFoods, profile, geminiKey,
        corsHeaders,
      });
    }

    // ── 3. Build prompt (full week) ──────────────────────────────────────────
    const userContext = `
User: ${profile?.name ?? "there"}
Calorie target: ${calorieTarget} kcal/day
Body stats: ${profile?.weight_kg ? `${profile.weight_kg}kg` : "unknown"} | ${profile?.height_cm ? `${profile.height_cm}cm` : "unknown"} | ${profile?.age ?? "unknown"} yo | ${profile?.sex ?? "unknown"}
Frequently eaten foods (incorporate where suitable): ${topFoods.join(", ") || "none yet"}
Week of: ${week_start}
`.trim();

    // ── 4. Call Gemini ───────────────────────────────────────────────────────
    const rawContent = await _callGemini(
      geminiKey,
      "gemini-2.0-flash-001",
      MEAL_PLAN_PROMPT + "\n\n" + GROCERY_PROMPT + "\n\n" + userContext,
      { temperature: 0.5, maxOutputTokens: 3000 }
    );
    const planData = JSON.parse(_cleanJson(rawContent));

    // ── 5. Upsert meal_plan ───────────────────────────────────────────────────
    const { data: mealPlan, error: planErr } = await supabase
      .from("meal_plans")
      .upsert(
        {
          user_id, week_start,
          calorie_target: calorieTarget,
          days: planData.days ?? [],
          ai_notes: planData.ai_notes ?? null,
        },
        { onConflict: "user_id,week_start" }
      )
      .select()
      .single();

    if (planErr) throw new Error(planErr.message);

    // ── 6. Build and upsert grocery_list ─────────────────────────────────────
    const groceryItems = (planData.grocery_items ?? []).map(
      (item: { name: string; quantity: string; category: string; used_in_meals?: string[] },
       index: number) => ({
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
        { user_id, meal_plan_id: mealPlan.id, week_start, items: groceryItems, is_shared: false },
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

// ─── Single-day regeneration helper ──────────────────────────────────────────
//
// Fetches the existing plan, asks GPT for one fresh day, merges it in,
// and updates the `days` JSONB column in-place.
// The grocery list is NOT regenerated — grocery items for a single day are
// too granular to meaningfully diff; users can edit the list manually.
// ─────────────────────────────────────────────────────────────────────────────

async function _regenerateDay(opts: {
  supabase: ReturnType<typeof createClient>;
  user_id: string;
  week_start: string;
  day_index: number;
  calorieTarget: number;
  topFoods: string[];
  profile: Record<string, unknown> | null;
  geminiKey: string;
  corsHeaders: Record<string, string>;
}): Promise<Response> {
  const {
    supabase, user_id, week_start, day_index,
    calorieTarget, topFoods, profile, geminiKey, corsHeaders,
  } = opts;

  const DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

  // Load the existing plan so we can surface existing meal names to GPT.
  const { data: existingPlan, error: planErr } = await supabase
    .from("meal_plans")
    .select("id, days")
    .eq("user_id", user_id)
    .eq("week_start", week_start)
    .maybeSingle();

  if (planErr) throw new Error(planErr.message);
  if (!existingPlan) throw new Error("No existing plan found — generate the full week first.");

  // Collect meal names from all other days to avoid repeats.
  const existingDays: Array<{ day_index: number; meals: Array<{ name: string }> }> =
    existingPlan.days ?? [];
  const otherMealNames = existingDays
    .filter((d) => d.day_index !== day_index)
    .flatMap((d) => d.meals.map((m) => m.name))
    .filter(Boolean);

  const userContext = `
User: ${profile?.name ?? "there"}
Calorie target: ${calorieTarget} kcal/day
Day to regenerate: ${DAY_NAMES[day_index] ?? `Day ${day_index}`} (day_index: ${day_index})
Frequently eaten foods (incorporate where suitable): ${topFoods.join(", ") || "none yet"}
Already used in other days of the week (do not repeat): ${otherMealNames.slice(0, 20).join(", ") || "none"}
`.trim();

  const rawContent = await _callGemini(
    geminiKey,
    "gemini-2.0-flash-001",
    SINGLE_DAY_PROMPT + "\n\n" + userContext,
    { temperature: 0.7, maxOutputTokens: 800 }
  );
  const newDay = JSON.parse(_cleanJson(rawContent));

  // Merge the new day into the existing days array.
  const mergedDays = existingDays.filter((d) => d.day_index !== day_index);
  mergedDays.push({ day_index, meals: newDay.meals ?? [] });
  mergedDays.sort((a, b) => a.day_index - b.day_index);

  const { data: updatedPlan, error: updateErr } = await supabase
    .from("meal_plans")
    .update({ days: mergedDays })
    .eq("id", existingPlan.id)
    .select()
    .single();

  if (updateErr) throw new Error(updateErr.message);

  // Return the updated plan; grocery_list is unchanged (client reloads both).
  const { data: groceryList } = await supabase
    .from("grocery_lists")
    .select()
    .eq("meal_plan_id", existingPlan.id)
    .maybeSingle();

  return new Response(
    JSON.stringify({ meal_plan: updatedPlan, grocery_list: groceryList ?? null }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ─── Gemini helpers (text-only) ───────────────────────────────────────────────

async function _callGemini(
  apiKey: string,
  model: string,
  prompt: string,
  config: { temperature: number; maxOutputTokens: number }
): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: config,
      }),
    }
  );
  if (!res.ok) {
    throw new Error(`Gemini API error (${res.status}): ${await res.text()}`);
  }
  const json = await res.json();
  const text: string = json.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  if (!text) throw new Error("Empty response from Gemini");
  return text;
}

function _cleanJson(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}
