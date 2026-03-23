// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// verify_jwt: false — JWT validation is not required here.
// Auth is enforced at the storage layer (upload requires valid session).
// This function only calls OpenAI with a public image URL.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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
      "fat": number (grams, 1dp),
      "confidence": number (0.0–1.0, your certainty about identification)
    }
  ],
  "total_calories": number,
  "total_protein": number,
  "total_carbs": number,
  "total_fat": number
}

Rules:
- Use realistic portion sizes based on visual estimation
- Calories and macros must be internally consistent (calories ≈ protein*4 + carbs*4 + fat*9)
- If you cannot identify food at all, return: {"items":[],"total_calories":0,"total_protein":0,"total_carbs":0,"total_fat":0}
- Do not invent items you cannot see`;

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_url } = await req.json();

    if (!image_url || typeof image_url !== "string") {
      return new Response(
        JSON.stringify({ error: "image_url (string) is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      throw new Error("OPENAI_API_KEY environment variable not set");
    }

    const openaiRes = await fetch(
      "https://api.openai.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openaiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o",
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: SYSTEM_PROMPT },
                {
                  type: "image_url",
                  image_url: {
                    url: image_url,
                    detail: "high",
                  },
                },
              ],
            },
          ],
          max_tokens: 1200,
          temperature: 0.1, // Low temperature = consistent, factual output
        }),
      }
    );

    if (!openaiRes.ok) {
      const errBody = await openaiRes.text();
      throw new Error(`OpenAI API error (${openaiRes.status}): ${errBody}`);
    }

    const openaiData = await openaiRes.json();
    const rawContent: string = openaiData.choices?.[0]?.message?.content ?? "";

    if (!rawContent) {
      throw new Error("Empty response from OpenAI");
    }

    // Strip markdown code fences if the model wraps output despite instructions
    const cleaned = rawContent
      .replace(/^```json\s*/i, "")
      .replace(/^```\s*/i, "")
      .replace(/\s*```$/i, "")
      .trim();

    let parsed: unknown;
    try {
      parsed = JSON.parse(cleaned);
    } catch {
      throw new Error(`Could not parse OpenAI response as JSON: ${cleaned}`);
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
