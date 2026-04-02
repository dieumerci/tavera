// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// verify_jwt: false — auth enforced at the Supabase Storage layer.
// This function fetches the image, base64-encodes it, and sends it to
// Google Gemini 1.5 Flash for food recognition. No JWT check needed here.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Gemini 1.5 Flash: chosen for cost (~66× cheaper than GPT-4o) while
// delivering comparable food-recognition accuracy for well-lit meal photos.
const GEMINI_MODEL = "gemini-2.0-flash-002";

const SYSTEM_PROMPT = `You are a precise nutrition analyst. When given a meal image, identify every visible food item and return accurate calorie and macro estimates.

Return ONLY a valid JSON object — no markdown fences, no explanation, no trailing text.

JSON structure:
{
  "items": [
    {
      "name": "string (common food name)",
      "portion_size": number,
      "portion_unit": "g | ml | piece | cup | slice | tbsp",
      "calories": number (integer),
      "protein": number (grams, 1dp),
      "carbs": number (grams, 1dp),
      "fiber": number (grams, 1dp),
      "fat": number (grams, 1dp),
      "fiber_g": number (grams, 1dp — dietary fibre only),
      "confidence": number (0.0–1.0, your certainty about identification)
    }
  ],
  "total_calories": number,
  "total_protein": number,
  "total_carbs": number,
  "total_fat": number,
  "total_fiber": number
}

Rules:
- Use realistic portion sizes based on visual estimation
- Calories and macros must be internally consistent (calories ≈ protein*4 + carbs*4 + fat*9)
- fiber_g must be ≤ carbs for the same item (fibre is a subset of carbohydrates)
- If you cannot identify food at all, return: {"items":[],"total_calories":0,"total_protein":0,"total_carbs":0,"total_fat":0,"total_fiber":0}
- Do not invent items you cannot see`;

// ─── Gemini helper ────────────────────────────────────────────────────────────
// Sends a multimodal request (text + optional inlineData image) to Gemini.
// Retries up to 3 times on 429 (rate limit) with exponential backoff.
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

    // 429 = rate limit — back off and retry.
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

// ─── Base64 image encoder ─────────────────────────────────────────────────────
// Gemini's inlineData requires base64. Supabase Storage serves HTTPS URLs,
// not gs:// URIs, so we fetch the bytes here and encode them.
// Chunked to avoid btoa() stack overflow on images up to ~1MB.
async function fetchImageAsBase64(url: string): Promise<{ base64: string; mimeType: string }> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Failed to fetch image (${res.status}): ${url}`);

  const mimeType = res.headers.get("content-type") ?? "image/jpeg";
  const buffer = await res.arrayBuffer();
  const bytes = new Uint8Array(buffer);

  let binary = "";
  const chunkSize = 8192;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }

  return { base64: btoa(binary), mimeType };
}

// ─── Strip markdown fences ────────────────────────────────────────────────────
function cleanJson(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_url } = await req.json();

    if (!image_url || typeof image_url !== "string") {
      return new Response(
        JSON.stringify({ error: "image_url (string) is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY environment variable not set");

    // Fetch the image from Supabase Storage and encode it for Gemini.
    const { base64, mimeType } = await fetchImageAsBase64(image_url);

    const rawContent = await callGemini(
      geminiKey,
      [
        { text: SYSTEM_PROMPT },
        { inlineData: { mimeType, data: base64 } },
      ],
      { temperature: 0.1, maxOutputTokens: 1200 }
    );

    let parsed: unknown;
    try {
      parsed = JSON.parse(cleanJson(rawContent));
    } catch {
      throw new Error(`Could not parse Gemini response as JSON: ${rawContent}`);
    }

    return new Response(JSON.stringify(parsed), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[analyse-meal]", message);

    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
