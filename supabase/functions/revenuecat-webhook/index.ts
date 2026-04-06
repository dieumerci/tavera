// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── revenuecat-webhook ───────────────────────────────────────────────────────
//
// Receives subscription lifecycle events from RevenueCat and keeps the
// profiles.subscription_tier column in sync with the live entitlement.
//
// This DB column is the FALLBACK used by SubscriptionService when the
// RevenueCat SDK is unavailable (cold start, no network). The live
// entitlement check via the SDK always takes precedence in the app.
//
// Setup (one-time):
//   1. RevenueCat Dashboard → Project Settings → Integrations → Webhooks
//   2. Add webhook URL: https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook
//   3. Copy the Authorization header value RevenueCat generates
//   4. Add it as a Supabase secret: REVENUECAT_WEBHOOK_SECRET
//      supabase secrets set REVENUECAT_WEBHOOK_SECRET=<value>
//
// RevenueCat sends the user's app_user_id as the Supabase UUID
// (set when calling Purchases.logIn(userId) in RevenueCatService.identify()).
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// RevenueCat event types that indicate an active premium subscription.
const ACTIVE_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_SUBSCRIPTION_PURCHASE",
  "TRANSFER",             // subscriber transferred to this app user
]);

// RevenueCat event types that indicate the subscription has lapsed or ended.
const INACTIVE_EVENTS = new Set([
  "CANCELLATION",
  "EXPIRATION",
  "BILLING_ISSUE",
  "SUBSCRIBER_ALIAS",     // safe to treat as inactive until next renewal
]);

type SubscriptionTier = "free" | "premium";

function resolveNewTier(eventType: string, currentTier: SubscriptionTier): SubscriptionTier {
  if (ACTIVE_EVENTS.has(eventType)) return "premium";
  if (INACTIVE_EVENTS.has(eventType)) return "free";
  // Unknown event — preserve current tier; RevenueCat SDK is authoritative.
  return currentTier;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── 1. Verify webhook authenticity ────────────────────────────────────────
  // RevenueCat signs webhooks with an Authorization header value that you
  // set in their dashboard. Compare it to the secret stored in Supabase.
  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (webhookSecret) {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (authHeader !== webhookSecret) {
      console.warn("revenuecat-webhook: invalid Authorization header — rejected");
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  }

  try {
    const body = await req.json();

    // RevenueCat wraps the payload in an "event" object.
    const event = body?.event ?? body;
    const eventType: string = event?.type ?? "";
    const appUserId: string = event?.app_user_id ?? "";
    const aliases: string[] = event?.aliases ?? [];

    if (!appUserId) {
      return new Response(
        JSON.stringify({ error: "app_user_id missing from webhook payload" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // ── 2. Resolve the Supabase user ID ────────────────────────────────────
    // The app calls Purchases.logIn(supabaseUserId) so app_user_id IS the
    // Supabase UUID. RevenueCat may also send alias IDs — check them all.
    const candidateIds = [appUserId, ...aliases].filter(
      (id) => /^[0-9a-f-]{36}$/.test(id) // basic UUID format guard
    );

    if (!candidateIds.length) {
      console.warn(`revenuecat-webhook: no UUID-shaped IDs found in event for user ${appUserId}`);
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 3. Fetch current tier for the primary user ─────────────────────────
    const { data: profile } = await supabase
      .from("profiles")
      .select("id, subscription_tier")
      .eq("id", candidateIds[0])
      .single();

    const currentTier: SubscriptionTier =
      (profile?.subscription_tier as SubscriptionTier) ?? "free";
    const newTier = resolveNewTier(eventType, currentTier);

    // ── 4. Update all matching profiles ───────────────────────────────────
    if (newTier !== currentTier) {
      const { error: updateError } = await supabase
        .from("profiles")
        .update({ subscription_tier: newTier })
        .in("id", candidateIds);

      if (updateError) throw new Error(updateError.message);

      console.log(
        `revenuecat-webhook: ${eventType} → tier ${currentTier} → ${newTier} for user ${candidateIds[0]}`
      );
    } else {
      console.log(
        `revenuecat-webhook: ${eventType} — tier unchanged (${currentTier}) for user ${candidateIds[0]}`
      );
    }

    return new Response(
      JSON.stringify({ ok: true, event_type: eventType, new_tier: newTier }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("revenuecat-webhook error:", message);
    // Return 200 to prevent RevenueCat from retrying on server errors.
    // Log the failure internally instead.
    return new Response(
      JSON.stringify({ ok: false, error: message }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
