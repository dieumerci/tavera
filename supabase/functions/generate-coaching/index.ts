// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── generate-coaching ────────────────────────────────────────────────────────
//
// Generates weekly AI coaching insights for a user based on their last 7 days
// of meal logs. Called from the Flutter app (premium users only) or via a
// scheduled cron trigger in Supabase.
//
// POST body: { user_id: string, week_start: string (YYYY-MM-DD) }
//
// Returns: { insights: CoachingInsight[] }
//
// The function fetches the user's meal logs for the given week, builds a
// nutrition summary, sends it to GPT-4o, parses the structured response,
// and upserts the insights into coaching_insights.
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const INSIGHT_PROMPT = `You are an expert dietitian and fitness coach. You will be given a user's meal log summary for the past week.
Analyse the data and generate actionable, encouraging coaching insights.

Return ONLY a valid JSON array — no markdown fences, no extra text.

Each insight object:
{
  "category": "calories" | "macros" | "consistency" | "hydration" | "general",
  "headline": "string (≤ 80 chars, specific and actionable)",
  "body": "string (≤ 250 chars, warm encouraging tone, concrete advice)"
}

Rules:
- Generate 2–4 insights covering different categories
- Be specific: reference actual numbers from the data
- Tone: supportive coach, not a lecture
- Focus on patterns and trends, not single days
- If data is sparse (< 4 log days), acknowledge it and give gentle encouragement`;

interface MealLogSummary {
  date: string;
  totalCalories: number;
  totalProtein: number | null;
  totalCarbs: number | null;
  totalFat: number | null;
  mealCount: number;
}

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

    // ── 1. Fetch the week's meal logs ────────────────────────────────────────
    const weekEnd = new Date(week_start);
    weekEnd.setDate(weekEnd.getDate() + 6);

    const { data: logs, error: logsError } = await supabase
      .from("meal_logs")
      .select("logged_at, total_calories, total_protein, total_carbs, total_fat")
      .eq("user_id", user_id)
      .gte("logged_at", week_start)
      .lte("logged_at", weekEnd.toISOString().split("T")[0] + "T23:59:59Z")
      .order("logged_at");

    if (logsError) throw new Error(logsError.message);

    // ── 2. Fetch user's calorie goal ─────────────────────────────────────────
    const { data: profile } = await supabase
      .from("profiles")
      .select("calorie_goal, name")
      .eq("id", user_id)
      .single();

    const calorieGoal = profile?.calorie_goal ?? 2000;
    const userName = profile?.name ?? "there";

    // ── 3. Build daily summary ───────────────────────────────────────────────
    const dailyMap = new Map<string, MealLogSummary>();
    for (const log of logs ?? []) {
      const date = log.logged_at.split("T")[0];
      const existing = dailyMap.get(date);
      if (existing) {
        existing.totalCalories += log.total_calories;
        existing.mealCount += 1;
        if (log.total_protein) existing.totalProtein = (existing.totalProtein ?? 0) + log.total_protein;
        if (log.total_carbs) existing.totalCarbs = (existing.totalCarbs ?? 0) + log.total_carbs;
        if (log.total_fat) existing.totalFat = (existing.totalFat ?? 0) + log.total_fat;
      } else {
        dailyMap.set(date, {
          date,
          totalCalories: log.total_calories,
          totalProtein: log.total_protein,
          totalCarbs: log.total_carbs,
          totalFat: log.total_fat,
          mealCount: 1,
        });
      }
    }

    const dailySummaries = Array.from(dailyMap.values());
    const daysLogged = dailySummaries.length;
    const avgCalories = daysLogged > 0
      ? Math.round(dailySummaries.reduce((s, d) => s + d.totalCalories, 0) / daysLogged)
      : 0;

    // ── 4. Compose the prompt context ────────────────────────────────────────
    const summaryText = dailySummaries.map((d) =>
      `${d.date}: ${d.totalCalories} kcal, P:${d.totalProtein?.toFixed(0) ?? "?"}g C:${d.totalCarbs?.toFixed(0) ?? "?"}g F:${d.totalFat?.toFixed(0) ?? "?"}g (${d.mealCount} meals)`
    ).join("\n");

    const contextText = `
User: ${userName}
Week of: ${week_start}
Calorie goal: ${calorieGoal} kcal/day
Days with logs: ${daysLogged}/7
Average daily calories: ${avgCalories} kcal

Daily breakdown:
${summaryText || "(no logs this week)"}
`.trim();

    // ── 5. Call Gemini 1.5 Pro ───────────────────────────────────────────────
    // Pro model used here (vs Flash elsewhere) because coaching insight quality
    // directly affects premium retention — a weak insight drives cancellations.
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY not set");

    const rawContent = await _callGemini(
      geminiKey,
      "gemini-1.5-pro",
      INSIGHT_PROMPT + "\n\n" + contextText,
      { temperature: 0.7, maxOutputTokens: 600 }
    );
    const insightArray = JSON.parse(_cleanJson(rawContent));

    if (!Array.isArray(insightArray)) {
      throw new Error("Gemini response was not a JSON array");
    }

    // ── 6. Upsert insights into DB ───────────────────────────────────────────
    const rows = insightArray.map((i: {
      category: string;
      headline: string;
      body: string;
    }) => ({
      user_id,
      week_start,
      headline: i.headline,
      body: i.body,
      category: i.category,
      is_read: false,
    }));

    const { data: upserted, error: upsertError } = await supabase
      .from("coaching_insights")
      .upsert(rows, { onConflict: "user_id,week_start,category" })
      .select();

    if (upsertError) throw new Error(upsertError.message);

    return new Response(
      JSON.stringify({ insights: upserted }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("generate-coaching error:", message);
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
