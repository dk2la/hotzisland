// Pocket trial server.
//
// Remembers when the Trial started on each Mac, so that reinstalling the app
// or wiping its local data does not restart the Trial.
//
// Contract:
//   POST /trial   {"macId":"<64 lowercase hex chars>"}
//   200           {"trialStartedAt": <unix seconds>, "serverTime": <unix seconds>}
//
// Privacy: the only thing ever stored is the hashed Mac ID (KV key) and the
// Trial start date (KV value). Nothing is logged; no IP or headers are kept.

const MAX_BODY_BYTES = 1024;
const MAC_ID_PATTERN = /^[0-9a-f]{64}$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/trial") {
      return json({ error: "not_found" }, 404);
    }
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    }

    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_BODY_BYTES) {
      return json({ error: "payload_too_large" }, 413);
    }

    const body = await readBody(request, MAX_BODY_BYTES);
    if (body === null) {
      return json({ error: "payload_too_large" }, 413);
    }

    let payload;
    try {
      payload = JSON.parse(body);
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    const macId = payload !== null && typeof payload === "object" ? payload.macId : undefined;
    if (typeof macId !== "string" || !MAC_ID_PATTERN.test(macId)) {
      return json({ error: "invalid_mac_id" }, 400);
    }

    // The server's time goes back too: the app counts Trial days from it,
    // so a Mac with its clock set back gains nothing.
    const now = Math.floor(Date.now() / 1000);
    const stored = parseTimestamp(await env.TRIALS.get(macId));
    if (stored !== null) {
      return json({ trialStartedAt: stored, serverTime: now }, 200);
    }

    await env.TRIALS.put(macId, String(now));
    return json({ trialStartedAt: now, serverTime: now }, 200);
  },
};

// Reads the request body as text, giving up as soon as it exceeds `limit`
// bytes. Returns null when the body is too large.
async function readBody(request, limit) {
  if (!request.body) return "";

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

// A stored value is only trusted if it is a plain positive integer.
function parseTimestamp(value) {
  if (typeof value !== "string" || !/^[0-9]{1,15}$/.test(value)) return null;
  const seconds = Number(value);
  return seconds > 0 ? seconds : null;
}

function json(payload, status, extraHeaders = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}
