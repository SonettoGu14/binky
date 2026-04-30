// Netlify Edge: serve homepage.md when the client prefers text/markdown (RFC-style negotiation).
export default async (request, context) => {
  const url = new URL(request.url);
  if (url.pathname !== "/" && url.pathname !== "") {
    return context.next();
  }
  if (!prefersMarkdown(request.headers.get("accept"))) {
    return context.next();
  }

  const mdRes = await fetch(new URL("/homepage.md", request.url));
  if (!mdRes.ok) {
    return context.next();
  }

  const text = await mdRes.text();
  const tokens = String(Math.max(1, Math.round(text.length / 4)));

  const link =
    '</.well-known/api-catalog>; rel="api-catalog", ' +
    '</llms.txt>; rel="describedby", ' +
    '</openapi.yaml>; rel="service-desc", ' +
    '</homepage.md>; rel="alternate"; type="text/markdown"';

  return new Response(text, {
    status: 200,
    headers: {
      "content-type": "text/markdown; charset=utf-8",
      "x-markdown-tokens": tokens,
      "cache-control": "public, max-age=300",
      Link: link,
    },
  });
};

function prefersMarkdown(accept) {
  if (!accept) return false;
  const parts = accept.split(",");
  for (const raw of parts) {
    const segments = raw.trim().split(";").map((s) => s.trim());
    const type = segments[0]?.toLowerCase();
    if (type !== "text/markdown") continue;
    let q = 1;
    for (let i = 1; i < segments.length; i++) {
      const seg = segments[i];
      const eq = seg.indexOf("=");
      const k = eq >= 0 ? seg.slice(0, eq).trim().toLowerCase() : seg.toLowerCase();
      const v = eq >= 0 ? seg.slice(eq + 1).trim() : "";
      if (k === "q") {
        const n = parseFloat(v);
        if (!Number.isNaN(n)) q = n;
      }
    }
    if (q > 0) return true;
  }
  return false;
}
