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
    // Paginated in batches of 1000 to handle heavy users with many images.
    // Distinguishes "bucket doesn't exist" (skip) from real errors (record).
    for (const bucket of ["meals", "avatars"]) {
      let offset = 0;
      const pageSize = 1000;
      while (true) {
        const { data: files, error: listError } = await admin.storage
          .from(bucket)
          .list(uid, { limit: pageSize, offset });

        if (listError) {
          // Bucket doesn't exist → not an error; anything else → record it.
          if (!listError.message.includes("not found") &&
              !listError.message.includes("does not exist")) {
            errors.push(`storage.${bucket}.list: ${listError.message}`);
          }
          break; // Stop pagination for this bucket.
        }

        if (!files || files.length === 0) break; // No more files.

        const paths = files.map((f: { name: string }) => `${uid}/${f.name}`);
        const { error: removeError } = await admin.storage
          .from(bucket)
          .remove(paths);
        if (removeError) {
          errors.push(`storage.${bucket}.remove: ${removeError.message}`);
          break; // Don't keep paginating if removal is failing.
        }

        if (files.length < pageSize) break; // Last page — done.
        offset += pageSize;
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
      // All user data is deleted but the auth.users row could not be removed.
      // Return success: false so the client does NOT navigate away — instead
      // it should show the error and instruct the user to contact support.
      // The orphaned auth row means this email remains registered; allowing
      // silent sign-out here would let the user sign back in without a profile,
      // causing undefined behaviour across the whole app.
      return new Response(
        JSON.stringify({
          success: false,
          errors,
          hint: "Your account data has been deleted but the authentication " +
            "record could not be removed. Please contact support — do not " +
            "attempt to create a new account with the same email address.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
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
