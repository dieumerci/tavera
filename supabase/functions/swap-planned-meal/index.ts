// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── swap-planned-meal ────────────────────────────────────────────────────────
//
// Returns 3 alternative meals for a given slot in the user's meal plan.
// The caller selects one and calls generate-meal-plan?day_index= to swap it in,
// OR a direct PATCH if they just want to replace the slot client-side.
//
// POST body:
//   {
//     user_id:    string,
//     plan_id:    string,
//     day_index:  number   (0 = Monday, 6 = Sunday)
//     slot:       "breakfast" | "lunch" | "dinner" | "snack"
//     current_meal_name: string  (the meal to replace — GPT won't repeat it)
//   }
//
// Returns: { alternatives: PlannedMeal[] }  (length 3)
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SWAP_PROMPT = `You are a professional dietitian suggesting meal alternatives.
Return ONLY a valid JSON array of exactly 3 meals — no markdown fences, no explanation.

JSON structure:
[
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

Rules:
- Return exactly 3 alternatives — no more, no less
- None of the 3 may be the same as the current_meal or any meal already in the plan
- All 3 must match the requested slot
- Calories per meal must be within 15% of the target per-meal calorie budget
- Vary the alternatives meaningfully (different protein sources, cuisines, prep styles)
- Keep prep times realistic: ≤ 15 min for breakfast/snack, ≤ 30 min for lunch/dinner`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, plan_id, day_index, slot, current_meal_name } =
      (await req.json()) as {
        user_id: string;
        plan_id: string;
        day_index: number;
        slot: string;
        current_meal_name: string;
      };

    if (!user_id || !plan_id || day_index === undefined || !slot) {
      return new Response(
        JSON.stringify({ error: "user_id, plan_id, day_index, and slot are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── 1. User profile ──────────────────────────────────────────────────────
    const { data: profile } = await supabase
      .from("profiles")
      .select("calorie_goal, name")
      .eq("id", user_id)
      .single();

    const calorieTarget = (profile?.calorie_goal as number | undefined) ?? 2000;
    // Rough per-meal budget (3 meals + 1 snack, snack ~15% of total).
    const slotBudget = slot === "snack"
      ? Math.round(calorieTarget * 0.15)
      : Math.round((calorieTarget * 0.85) / 3);

    // ── 2. Fetch existing plan to exclude already-used meals ─────────────────
    const { data: plan } = await supabase
      .from("meal_plans")
      .select("days")
      .eq("id", plan_id)
      .maybeSingle();

    const existingMealNames: string[] = [];
    if (plan?.days) {
      for (const day of plan.days as Array<{ day_index: number; meals: Array<{ name: string }> }>) {
        for (const meal of day.meals) {
          if (meal.name) existingMealNames.push(meal.name);
        }
      }
    }

    // ── 3. Build prompt ──────────────────────────────────────────────────────
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY not set");

    const DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

    const userContext = `
User: ${profile?.name ?? "there"}
Calorie target: ${calorieTarget} kcal/day
Slot: ${slot} on ${DAY_NAMES[day_index] ?? `Day ${day_index}`}
Target calories for this slot: ~${slotBudget} kcal
Current meal to replace: ${current_meal_name || "unknown"}
Already in the plan this week (do not repeat): ${existingMealNames.slice(0, 30).join(", ") || "none"}
`.trim();

    // ── 4. Call Gemini ───────────────────────────────────────────────────────
    const rawContent = await _callGemini(
      geminiKey,
      "gemini-2.0-flash-002",
      SWAP_PROMPT + "\n\n" + userContext,
      { temperature: 0.8, maxOutputTokens: 800 }
    );
    const alternatives = JSON.parse(_cleanJson(rawContent));

    if (!Array.isArray(alternatives) || alternatives.length === 0) {
      throw new Error("Gemini returned no alternatives");
    }

    return new Response(
      JSON.stringify({ alternatives: alternatives.slice(0, 3) }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("swap-planned-meal error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// ─── Gemini helpers ───────────────────────────────────────────────────────────

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
