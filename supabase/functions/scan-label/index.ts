// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// @ts-ignore
import { createClient } from "jsr:@supabase/supabase-js@2";

// scan-label — Nutrition Facts label reader
//
// Accepts a base64-encoded image of a nutrition facts panel.
// Uses Gemini vision to read the printed values directly (not estimate).
// Returns a single FoodItem-compatible JSON object.
//
// Called by the Flutter client after the user photographs or selects a
// nutrition label. The image is sent as base64 to avoid a Storage upload
// round-trip (labels don't need to be persisted).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const GEMINI_MODEL = "gemini-2.0-flash-002";

const SYSTEM_PROMPT = `You are a nutrition label reader. Extract the nutrition information exactly as printed on the label.

Return ONLY a valid JSON object — no markdown fences, no explanation.

JSON structure:
{
  "name": "string (product name from label, or generic description)",
  "portion_size": number (serving size number from label),
  "portion_unit": "g | ml | piece | cup | slice | tbsp",
  "calories": number (integer — from 'Calories' or 'Energy' row, per serving),
  "protein": number (grams, from 'Protein' row),
  "carbs": number (grams, from 'Total Carbohydrate' or 'Carbohydrates' row),
  "fiber": number (grams, from 'Dietary Fiber' row — 0 if not listed),
  "fat": number (grams, from 'Total Fat' row),
  "confidence": number (0.0–1.0, how clearly the label is readable)
}

Rules:
- Read values exactly as printed — do not estimate or adjust
- Use per-serving values, not per-100g (unless only per-100g is available)
- If the label is unreadable or not a nutrition facts panel, return:
  {"name":"Unknown","portion_size":0,"portion_unit":"g","calories":0,"protein":0,"carbs":0,"fiber":0,"fat":0,"confidence":0}
- fiber must be ≤ carbs (fiber is a subset of carbohydrates)`;

// ─── Gemini helper ────────────────────────────────────────────────────────────

async function callGemini(
  apiKey: string,
  parts: Array<{ text?: string; inlineData?: { mimeType: string; data: string } }>,
  config: { temperature: number; maxOutputTokens: number }
): Promise<string> {
  const body = JSON.stringify({
    contents: [{ parts }],
    generationConfig: config,
  });

  const maxAttempts = 3;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body }
    );

    if (res.status === 429 && attempt < maxAttempts - 1) {
      await new Promise((r) => setTimeout(r, (attempt + 1) * 2000));
      continue;
    }

    if (!res.ok) {
      throw new Error(`Gemini API error (${res.status}): ${await res.text()}`);
    }

    const json = await res.json();
    const text: string = json.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    if (!text) throw new Error("Empty response from Gemini");
    return text;
  }

  throw new Error("Gemini rate limit: all retries exhausted");
}

// ─── Strip markdown fences ────────────────────────────────────────────────────

function cleanJson(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

// ─── Anonymised AI request logger ────────────────────────────────────────────

function logAiRequest(success: boolean, latencyMs: number, errorCode?: string): void {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return;

  const supabase = createClient(supabaseUrl, serviceKey);
  supabase.from("ai_request_logs").insert({
    function_name: "scan-label",
    model: GEMINI_MODEL,
    latency_ms: latencyMs,
    success,
    error_code: errorCode ?? null,
  }).then(() => {}).catch(() => {});
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const t0 = Date.now();

  try {
    const { image_base64, mime_type } = await req.json();

    if (!image_base64 || typeof image_base64 !== "string") {
      return new Response(
        JSON.stringify({ error: "image_base64 (string) is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY environment variable not set");

    const mimeType = (typeof mime_type === "string" && mime_type) ? mime_type : "image/jpeg";

    const rawContent = await callGemini(
      geminiKey,
      [
        { text: SYSTEM_PROMPT },
        { inlineData: { mimeType, data: image_base64 } },
      ],
      { temperature: 0.0, maxOutputTokens: 512 }
    );

    let parsed: unknown;
    try {
      parsed = JSON.parse(cleanJson(rawContent));
    } catch {
      throw new Error(`Could not parse Gemini response as JSON: ${rawContent}`);
    }

    logAiRequest(true, Date.now() - t0);

    return new Response(JSON.stringify(parsed), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[scan-label]", message);
    logAiRequest(false, Date.now() - t0, message.slice(0, 80));

    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
