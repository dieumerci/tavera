// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// delete-account
// ──────────────
// Permanently deletes a user's account and all associated data.
//
// Auth: requires a valid user JWT (Authorization: Bearer <token>).
//       The user can only delete their own account.
//
// Deletion order (important):
//   1. Storage objects (meal images, avatars) — fail-open so a missing bucket
//      never blocks the rest of the pipeline.
//   2. DB rows  — `profiles` delete cascades to all child tables via FK ON DELETE CASCADE:
//      meal_logs, meal_items, known_meals, coaching_insights,
//      challenge_participants, challenge_events, meal_plans, grocery_lists.
//   3. auth.admin.deleteUser() — must be last; once the Auth row is gone the
//      JWT is invalidated and the client session ends automatically.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Authenticate the caller ────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Use the user's JWT to identify who is calling.
    const { createClient } = await import("jsr:@supabase/supabase-js@2");
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const uid = user.id;

    // Service-role client for privileged operations.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const errors: string[] = [];

    // ── 2. Delete Storage objects ─────────────────────────────────────────────
    // Meal images live under "meals/<user_id>/<filename>".
    // Avatars (future) under "avatars/<user_id>".
    // Fail-open: a missing bucket or empty folder is not an error.
    for (const bucket of ["meals", "avatars"]) {
      try {
        const { data: files } = await admin.storage
          .from(bucket)
          .list(uid, { limit: 1000 });
        if (files && files.length > 0) {
          const paths = files.map((f: { name: string }) => `${uid}/${f.name}`);
          const { error } = await admin.storage.from(bucket).remove(paths);
          if (error) {
            errors.push(`storage.${bucket}: ${error.message}`);
          }
        }
      } catch (_) {
        // Bucket doesn't exist yet — skip silently.
      }
    }

    // ── 3. Delete DB rows via profiles cascade ────────────────────────────────
    // All child tables (meal_logs, coaching_insights, challenge_participants,
    // meal_plans, grocery_lists, known_meals) have FK → profiles(id) ON DELETE CASCADE.
    const { error: profileError } = await admin
      .from("profiles")
      .delete()
      .eq("id", uid);
    if (profileError) {
      errors.push(`profiles: ${profileError.message}`);
      // If the profile delete failed, bail before invalidating the Auth row —
      // the user can retry. Returning a partial-failure response lets the
      // client distinguish "try again" from "done".
      return new Response(
        JSON.stringify({
          success: false,
          errors,
          hint: "Profile deletion failed — auth row preserved. Retry or contact support.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── 4. Delete the Auth user (irreversible) ────────────────────────────────
    const { error: authDeleteError } = await admin.auth.admin.deleteUser(uid);
    if (authDeleteError) {
      errors.push(`auth.deleteUser: ${authDeleteError.message}`);
      // DB data is already deleted at this point. Log the error but still
      // return success=true so the client clears its session — the orphaned
      // Auth row will be cleaned up by a periodic admin job or Supabase support.
      return new Response(
        JSON.stringify({
          success: true,
          warning: "Account data deleted but Auth row could not be removed. " +
            "Contact support if you experience issues signing up again.",
          errors,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
