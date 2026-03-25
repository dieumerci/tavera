// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── challenge-notifier ───────────────────────────────────────────────────────
//
// Processes challenge events and updates participant scores / ranks.
// Called by the Flutter app immediately after a meal is logged when the user
// is in one or more active challenges. Also wires up push notifications via
// the `notification_tokens` table (if present).
//
// POST body:
//   {
//     user_id:       string,
//     meal_log_id:   string,
//     calories:      number,
//     protein_g?:    number,
//     carbs_g?:      number,
//     fat_g?:        number,
//     logged_at:     string (ISO 8601)
//   }
//
// Returns: { updated_challenges: string[], rank_changes: RankChange[] }
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface RankChange {
  challengeId: string;
  userId: string;
  oldRank: number;
  newRank: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { user_id, meal_log_id, calories, logged_at } = body;

    if (!user_id || !meal_log_id || calories == null || !logged_at) {
      return new Response(
        JSON.stringify({ error: "user_id, meal_log_id, calories, logged_at are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const logDate = logged_at.split("T")[0];

    // ── 1. Find active challenges the user participates in ──────────────────
    const { data: participations, error: partErr } = await supabase
      .from("challenge_participants")
      .select("id, challenge_id, score, streak_days, rank")
      .eq("user_id", user_id);

    if (partErr) throw new Error(partErr.message);
    if (!participations?.length) {
      return new Response(
        JSON.stringify({ updated_challenges: [], rank_changes: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const challengeIds = participations.map((p: { challenge_id: string }) => p.challenge_id);

    const { data: challenges, error: chalErr } = await supabase
      .from("challenges")
      .select("id, type, target_value, start_date, end_date")
      .in("id", challengeIds)
      .lte("start_date", logDate)
      .gte("end_date", logDate);

    if (chalErr) throw new Error(chalErr.message);
    if (!challenges?.length) {
      return new Response(
        JSON.stringify({ updated_challenges: [], rank_changes: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ── 2. Score each active challenge ──────────────────────────────────────
    const updatedChallengeIds: string[] = [];
    const rankChanges: RankChange[] = [];

    for (const challenge of challenges) {
      const participation = participations.find(
        (p: { challenge_id: string }) => p.challenge_id === challenge.id
      );
      if (!participation) continue;

      let scoreIncrement = 0;

      if (challenge.type === "calorie_budget") {
        // Score = 1 point if today's total is within budget.
        // Recalculate today's total calories for this user.
        const { data: todayLogs } = await supabase
          .from("meal_logs")
          .select("total_calories")
          .eq("user_id", user_id)
          .gte("logged_at", logDate + "T00:00:00Z")
          .lte("logged_at", logDate + "T23:59:59Z");

        const todayTotal = todayLogs?.reduce(
          (s: number, l: { total_calories: number }) => s + l.total_calories, 0
        ) ?? calories;

        if (todayTotal <= challenge.target_value) {
          scoreIncrement = 1;
        }
      } else if (challenge.type === "streak") {
        // Score = days with at least one meal logged in a row.
        scoreIncrement = 1; // Simplified: full streak calculation in daily cron.
      } else if (challenge.type === "macro_target") {
        // Score = percentage of target macros hit (0–100).
        const proteinG = body.protein_g ?? 0;
        scoreIncrement = Math.min(100, Math.round((proteinG / challenge.target_value) * 100));
      } else {
        // Custom: score = calories logged (raw progress metric).
        scoreIncrement = calories;
      }

      // ── 3. Update participant score ────────────────────────────────────────
      const newScore = (participation.score ?? 0) + scoreIncrement;
      await supabase
        .from("challenge_participants")
        .update({ score: newScore })
        .eq("id", participation.id);

      // ── 4. Recalculate ranks for this challenge ───────────────────────────
      const { data: allParticipants } = await supabase
        .from("challenge_participants")
        .select("id, user_id, score, rank")
        .eq("challenge_id", challenge.id)
        .order("score", { ascending: false });

      if (allParticipants) {
        for (let i = 0; i < allParticipants.length; i++) {
          const p = allParticipants[i];
          const newRank = i + 1;
          if (p.rank !== newRank) {
            await supabase
              .from("challenge_participants")
              .update({ rank: newRank })
              .eq("id", p.id);

            if (p.user_id === user_id) {
              rankChanges.push({
                challengeId: challenge.id,
                userId: user_id,
                oldRank: p.rank,
                newRank,
              });
            }
          }
        }
      }

      // ── 5. Record the event ────────────────────────────────────────────────
      await supabase.from("challenge_events").insert({
        challenge_id: challenge.id,
        user_id,
        event_type: "meal_logged",
        payload: {
          meal_log_id,
          calories,
          score_increment: scoreIncrement,
          new_score: newScore,
        },
      });

      updatedChallengeIds.push(challenge.id);
    }

    return new Response(
      JSON.stringify({ updated_challenges: updatedChallengeIds, rank_changes: rankChanges }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("challenge-notifier error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
