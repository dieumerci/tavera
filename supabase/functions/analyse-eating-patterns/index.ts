// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── analyse-eating-patterns ─────────────────────────────────────────────────
//
// Deep-analyses 30 days of a user's meal logs to extract:
//   - Frequently eaten foods (known meal memory candidates)
//   - Macro distribution trends
//   - Time-of-day eating patterns
//   - Calorie consistency score (0–100)
//
// This output feeds both the `generate-meal-plan` function (personalisation)
// and the `known_meals` table upsert logic.
//
// POST body: { user_id: string }
// Returns:   { patterns: EatingPatterns }
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface EatingPatterns {
  userId: string;
  analysedDays: number;
  avgDailyCalories: number;
  avgProteinG: number;
  avgCarbsG: number;
  avgFatG: number;
  calorieConsistencyScore: number; // 0–100 (100 = same calories every day)
  topFoods: Array<{ name: string; frequency: number; avgCalories: number }>;
  peakMealHour: number; // 0–23 (hour of day with most meals)
  daysLogged: number;
  mealsPerDay: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id } = await req.json();

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "user_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── 1. Fetch last 30 days of logs ────────────────────────────────────────
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const { data: logs, error: logsErr } = await supabase
      .from("meal_logs")
      .select("logged_at, total_calories, total_protein, total_carbs, total_fat, items")
      .eq("user_id", user_id)
      .gte("logged_at", thirtyDaysAgo.toISOString())
      .order("logged_at");

    if (logsErr) throw new Error(logsErr.message);
    if (!logs?.length) {
      return new Response(
        JSON.stringify({
          patterns: {
            userId: user_id,
            analysedDays: 0,
            avgDailyCalories: 0,
            avgProteinG: 0,
            avgCarbsG: 0,
            avgFatG: 0,
            calorieConsistencyScore: 0,
            topFoods: [],
            peakMealHour: 12,
            daysLogged: 0,
            mealsPerDay: 0,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Aggregate daily totals ────────────────────────────────────────────
    const dailyMap = new Map<string, { calories: number; protein: number; carbs: number; fat: number }>();
    const hourCounts = new Array(24).fill(0);
    const foodFreq = new Map<string, { count: number; totalCalories: number }>();

    for (const log of logs) {
      const date = log.logged_at.split("T")[0];
      const hour = new Date(log.logged_at).getUTCHours();

      const day = dailyMap.get(date) ?? { calories: 0, protein: 0, carbs: 0, fat: 0 };
      day.calories += log.total_calories ?? 0;
      day.protein += log.total_protein ?? 0;
      day.carbs += log.total_carbs ?? 0;
      day.fat += log.total_fat ?? 0;
      dailyMap.set(date, day);
      hourCounts[hour] += 1;

      // Extract food names from items JSONB
      if (Array.isArray(log.items)) {
        for (const item of log.items) {
          const name = (item.name as string ?? "").toLowerCase().trim();
          if (!name) continue;
          const existing = foodFreq.get(name) ?? { count: 0, totalCalories: 0 };
          existing.count += 1;
          existing.totalCalories += item.calories ?? 0;
          foodFreq.set(name, existing);
        }
      }
    }

    const days = Array.from(dailyMap.values());
    const daysLogged = days.length;
    const totalCalories = days.reduce((s, d) => s + d.calories, 0);
    const avgDailyCalories = Math.round(totalCalories / daysLogged);
    const avgProteinG = Math.round(days.reduce((s, d) => s + d.protein, 0) / daysLogged);
    const avgCarbsG = Math.round(days.reduce((s, d) => s + d.carbs, 0) / daysLogged);
    const avgFatG = Math.round(days.reduce((s, d) => s + d.fat, 0) / daysLogged);

    // Consistency score: lower std dev → higher score.
    const variance = days.reduce((s, d) => s + Math.pow(d.calories - avgDailyCalories, 2), 0) / daysLogged;
    const stdDev = Math.sqrt(variance);
    const calorieConsistencyScore = Math.max(0, Math.round(100 - (stdDev / avgDailyCalories) * 100));

    // Peak meal hour
    const peakMealHour = hourCounts.indexOf(Math.max(...hourCounts));

    // Top 10 foods by frequency
    const topFoods = Array.from(foodFreq.entries())
      .map(([name, { count, totalCalories: tc }]) => ({
        name,
        frequency: count,
        avgCalories: Math.round(tc / count),
      }))
      .sort((a, b) => b.frequency - a.frequency)
      .slice(0, 10);

    const patterns: EatingPatterns = {
      userId: user_id,
      analysedDays: 30,
      avgDailyCalories,
      avgProteinG,
      avgCarbsG,
      avgFatG,
      calorieConsistencyScore,
      topFoods,
      peakMealHour,
      daysLogged,
      mealsPerDay: Math.round((logs.length / daysLogged) * 10) / 10,
    };

    return new Response(
      JSON.stringify({ patterns }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("analyse-eating-patterns error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
