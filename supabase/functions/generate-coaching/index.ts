// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── generate-coaching ────────────────────────────────────────────────────────
//
// Generates weekly AI coaching insights for a user based on their last 7 days
// of meal logs. Two call modes:
//
// 1. Per-user (Flutter app, premium users):
//    POST { user_id: string, week_start: string (YYYY-MM-DD) }
//    Returns { insights: CoachingInsight[] }
//
// 2. Batch / cron (pg_cron weekly trigger):
//    POST { trigger: "weekly_cron" }
//    Fetches all users who have ≥ 3 days of logs in the current week
//    and generates insights for each. Returns { processed: number }.
//
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
  totalFiber: number | null;
  totalFat: number | null;
  mealCount: number;
}

// ─── Batch cron handler ───────────────────────────────────────────────────────
// Called with { trigger: "weekly_cron" }. Finds all users who logged meals on
// at least 3 distinct days in the current week and generates coaching insights
// for each. Errors for individual users are logged but do not abort the batch.
async function handleWeeklyCron(geminiKey: string): Promise<Response> {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // Derive the Monday of the current week (UTC).
  const now = new Date();
  const dayOfWeek = now.getUTCDay(); // 0 = Sunday
  const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
  const monday = new Date(now);
  monday.setUTCDate(now.getUTCDate() - daysToMonday);
  monday.setUTCHours(0, 0, 0, 0);
  const weekStart = monday.toISOString().split("T")[0];
  const weekEndTs = new Date(monday);
  weekEndTs.setUTCDate(monday.getUTCDate() + 6);
  weekEndTs.setUTCHours(23, 59, 59, 999);

  // Find users with ≥ 3 distinct log days this week.
  const { data: rows, error } = await supabase
    .from("meal_logs")
    .select("user_id, logged_at")
    .gte("logged_at", monday.toISOString())
    .lte("logged_at", weekEndTs.toISOString());

  if (error) {
    console.error("generate-coaching cron: failed to fetch logs", error.message);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Group distinct days by user.
  const userDays = new Map<string, Set<string>>();
  for (const row of rows ?? []) {
    const day = (row.logged_at as string).split("T")[0];
    if (!userDays.has(row.user_id)) userDays.set(row.user_id, new Set());
    userDays.get(row.user_id)!.add(day);
  }

  const eligibleUsers = [...userDays.entries()]
    .filter(([, days]) => days.size >= 3)
    .map(([uid]) => uid);

  let processed = 0;
  for (const userId of eligibleUsers) {
    try {
      await generateInsightsForUser(supabase, geminiKey, userId, weekStart);
      processed++;
    } catch (err) {
      // Log individual failures but continue the batch.
      console.error(`generate-coaching cron: failed for user ${userId}:`,
        err instanceof Error ? err.message : String(err));
    }
  }

  console.log(`generate-coaching cron: processed ${processed}/${eligibleUsers.length} users for week ${weekStart}`);
  return new Response(
    JSON.stringify({ processed, week_start: weekStart }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY not set");

    // Batch cron mode.
    if (body.trigger === "weekly_cron") {
      return handleWeeklyCron(geminiKey);
    }

    const { user_id, week_start } = body;

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

    const upserted = await generateInsightsForUser(supabase, geminiKey, user_id, week_start);
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

// ─── Per-user insight generation ─────────────────────────────────────────────
// Shared by the single-user API path and the weekly cron batch runner.
// Returns the upserted insight rows.
// deno-lint-ignore no-explicit-any
async function generateInsightsForUser(supabase: any, geminiKey: string, userId: string, weekStart: string) {
  // ── 1. Fetch the week's meal logs ──────────────────────────────────────────
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekEnd.getDate() + 6);

  const { data: logs, error: logsError } = await supabase
    .from("meal_logs")
    .select("logged_at, total_calories, total_protein, total_carbs, total_fat, total_fiber")
    .eq("user_id", userId)
    .gte("logged_at", weekStart)
    .lte("logged_at", weekEnd.toISOString().split("T")[0] + "T23:59:59Z")
    .order("logged_at");

  if (logsError) throw new Error(logsError.message);

  // ── 2. Fetch user's profile ────────────────────────────────────────────────
  const { data: profile } = await supabase
    .from("profiles")
    .select("calorie_goal, name, net_carbs_mode")
    .eq("id", userId)
    .single();

  const calorieGoal  = profile?.calorie_goal  ?? 2000;
  const userName     = profile?.name           ?? "there";
  const netCarbsMode = profile?.net_carbs_mode ?? false;

  // ── 3. Build daily summary ─────────────────────────────────────────────────
  const dailyMap = new Map<string, MealLogSummary>();
  for (const log of logs ?? []) {
    const date = log.logged_at.split("T")[0];
    const existing = dailyMap.get(date);
    if (existing) {
      existing.totalCalories += log.total_calories;
      existing.mealCount += 1;
      if (log.total_protein) existing.totalProtein = (existing.totalProtein ?? 0) + log.total_protein;
      if (log.total_carbs)   existing.totalCarbs   = (existing.totalCarbs   ?? 0) + log.total_carbs;
      if (log.total_fiber)   existing.totalFiber   = (existing.totalFiber   ?? 0) + log.total_fiber;
      if (log.total_fat)     existing.totalFat     = (existing.totalFat     ?? 0) + log.total_fat;
    } else {
      dailyMap.set(date, {
        date,
        totalCalories: log.total_calories,
        totalProtein:  log.total_protein,
        totalCarbs:    log.total_carbs,
        totalFiber:    log.total_fiber ?? null,
        totalFat:      log.total_fat,
        mealCount: 1,
      });
    }
  }

  const dailySummaries = Array.from(dailyMap.values());
  const daysLogged   = dailySummaries.length;
  const avgCalories  = daysLogged > 0
    ? Math.round(dailySummaries.reduce((s, d) => s + d.totalCalories, 0) / daysLogged)
    : 0;

  // ── 4. Compose the prompt context ──────────────────────────────────────────
  const carbLabel  = netCarbsMode ? "Net C" : "C";
  const summaryText = dailySummaries.map((d) => {
    const carbValue = netCarbsMode
      ? Math.max(0, (d.totalCarbs ?? 0) - (d.totalFiber ?? 0))
      : (d.totalCarbs ?? null);
    return `${d.date}: ${d.totalCalories} kcal, P:${d.totalProtein?.toFixed(0) ?? "?"}g ${carbLabel}:${carbValue?.toFixed(0) ?? "?"}g F:${d.totalFat?.toFixed(0) ?? "?"}g (${d.mealCount} meals)`;
  }).join("\n");

  const contextText = `
User: ${userName}
Week of: ${weekStart}
Calorie goal: ${calorieGoal} kcal/day
Carb display: ${netCarbsMode ? "net carbs (total carbs minus dietary fibre)" : "total carbs"}
Days with logs: ${daysLogged}/7
Average daily calories: ${avgCalories} kcal

Daily breakdown:
${summaryText || "(no logs this week)"}
`.trim();

  // ── 5. Call Gemini ─────────────────────────────────────────────────────────
  // gemini-2.0-flash-002 balances quality and cost for coaching text.
  const rawContent = await _callGemini(
    geminiKey,
    "gemini-2.0-flash-002",
    INSIGHT_PROMPT + "\n\n" + contextText,
    { temperature: 0.7, maxOutputTokens: 600 }
  );
  const insightArray = JSON.parse(_cleanJson(rawContent));
  if (!Array.isArray(insightArray)) throw new Error("Gemini response was not a JSON array");

  // ── 6. Upsert insights ─────────────────────────────────────────────────────
  const rows = insightArray.map((i: { category: string; headline: string; body: string }) => ({
    user_id:    userId,
    week_start: weekStart,
    headline:   i.headline,
    body:       i.body,
    category:   i.category,
    is_read:    false,
  }));

  const { data: upserted, error: upsertError } = await supabase
    .from("coaching_insights")
    .upsert(rows, { onConflict: "user_id,week_start,category" })
    .select();

  if (upsertError) throw new Error(upsertError.message);
  return upserted;
}

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
