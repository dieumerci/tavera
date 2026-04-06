// @ts-ignore
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// ─── identify-product ──────────────────────────────────────────────────────
//
// Extracts structured product information from a food/beverage label image
// using Gemini 1.5 Flash vision. Called by the Flutter client when barcode
// lookup fails and the user opts to scan the product label for OCR fallback.
//
// POST body:
//   { image_base64: string, mime_type: string }
//
// Returns:
//   {
//     brand:        string | null,   // manufacturer name
//     product_name: string | null,   // variant / flavor
//     size_ml:      number | null,   // liquid volume in ml
//     size_g:       number | null,   // net weight in grams
//     barcode:      string | null    // printed barcode digits if visible
//   }
//
// The Dart client uses these fields to query the local products table:
//   - If barcode is non-null → try identifyByBarcode(barcode) first
//   - Otherwise → identifyByText(product_name, brand, size_ml)
// ─────────────────────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const LABEL_EXTRACTION_PROMPT = `You are a product label scanner. Extract product information from this food or beverage label image.

Return ONLY a valid JSON object — no markdown fences, no explanation, no trailing text.

JSON structure:
{
  "brand": "string (manufacturer/brand name, e.g. 'Sanpellegrino', 'Coca-Cola') or null",
  "product_name": "string (product variant or flavor, e.g. 'Melograno & Arancia', 'Zero Sugar') or null",
  "size_ml": number (liquid volume in millilitres if visible on label, e.g. 330) or null,
  "size_g": number (net weight in grams if visible on label) or null,
  "barcode": "string (barcode digits printed as human-readable text below the barcode symbol) or null"
}

Rules:
- Extract only what you can clearly read from the label
- brand is the manufacturer name only (not the product variant)
- product_name is the variant or flavour — not the brand name
- Prefer size_ml for drinks, size_g for solid foods
- If barcode digits are printed as text on the label, include them in barcode
- Return null for any field you cannot determine with confidence`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_base64, mime_type } = (await req.json()) as {
      image_base64: string;
      mime_type: string;
    };

    if (!image_base64 || !mime_type) {
      return new Response(
        JSON.stringify({ error: "image_base64 and mime_type are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) throw new Error("GEMINI_API_KEY not set");

    const rawContent = await _callGeminiVision(geminiKey, {
      prompt: LABEL_EXTRACTION_PROMPT,
      imageBase64: image_base64,
      mimeType: mime_type,
    });

    let extracted: unknown;
    try {
      extracted = JSON.parse(_cleanJson(rawContent));
    } catch {
      throw new Error(
        `Could not parse Gemini response as JSON: ${rawContent}`
      );
    }

    return new Response(JSON.stringify(extracted), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[identify-product]", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ─── Gemini helpers ───────────────────────────────────────────────────────────

async function _callGeminiVision(
  apiKey: string,
  opts: { prompt: string; imageBase64: string; mimeType: string }
): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: opts.prompt },
              {
                inlineData: {
                  mimeType: opts.mimeType,
                  data: opts.imageBase64,
                },
              },
            ],
          },
        ],
        generationConfig: { temperature: 0.1, maxOutputTokens: 256 },
      }),
    }
  );

  if (!res.ok) {
    throw new Error(`Gemini API error (${res.status}): ${await res.text()}`);
  }

  const json = await res.json();
  const text: string =
    json.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
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
