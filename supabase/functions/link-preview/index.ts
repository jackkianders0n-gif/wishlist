// link-preview — Supabase Edge Function
// POST { url: "https://..." }            -> one preview
// POST { urls: ["https://...", ...] }    -> up to 20 previews (for "Check prices")
//
// Returns per link:
// { ok, url, finalUrl, store, title, image, price, currency, blocked, status, sources, ms, error? }
//
// Members only: the caller must be signed in and listed in wl_members.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
const TIMEOUT_MS = 12000;
const MAX_BYTES = 4_000_000;
const MAX_BATCH = 20;
const CONCURRENCY = 4;

// ---------- URL cleaning ----------

const TRACKING_PARAM =
  /^(utm_.*|gclid|gclsrc|gbraid|wbraid|gad_.*|fbclid|msclkid|mcid|_\$ja|cmpid|hv.*|tag|linkcode|ref|ref_|psc|th|smid|deeplink|gpdp|mc_.*|srsltid|ascsubtag|camp|creative|creativeasin|linkid|qid|sr|keywords|crid|sprefix|dib|dib_tag|content-id|pd_rd_.*|pf_rd_.*)$/i;

export function cleanUrl(raw: string): URL {
  const u = new URL(raw.trim());
  u.hash = "";
  const host = u.hostname.replace(/^www\./, "");

  // Amazon: reduce to /dp/ASIN
  if (/^amazon\.[a-z.]+$/.test(host)) {
    const m = u.pathname.match(/\/(?:dp|gp\/product|gp\/aw\/d|exec\/obidos\/asin)\/([A-Z0-9]{10})/i);
    if (m) return new URL(`https://${u.hostname}/dp/${m[1].toUpperCase()}`);
  }
  // Argos: reduce to /product/ID
  if (host === "argos.co.uk") {
    const m = u.pathname.match(/\/product\/(\d+)/);
    if (m) return new URL(`https://www.argos.co.uk/product/${m[1]}`);
  }
  for (const key of [...u.searchParams.keys()]) {
    if (TRACKING_PARAM.test(key)) u.searchParams.delete(key);
  }
  return u;
}

// ---------- SSRF guard ----------

function assertPublicUrl(u: URL) {
  if (u.protocol !== "https:" && u.protocol !== "http:") throw new Error("Only http(s) links");
  if (u.port && u.port !== "80" && u.port !== "443") throw new Error("Non-standard port");
  if (u.username || u.password) throw new Error("Credentials in URL");
  const h = u.hostname.toLowerCase();
  if (
    h === "localhost" ||
    h.endsWith(".localhost") ||
    h.endsWith(".local") ||
    h.endsWith(".internal") ||
    h.endsWith(".lan") ||
    !h.includes(".") ||
    /^[\d.]+$/.test(h) || // IPv4 literal
    h.includes(":") || // IPv6 literal
    h.startsWith("[")
  ) {
    throw new Error("Host not allowed");
  }
}

async function fetchPage(start: URL): Promise<{ res: Response; finalUrl: URL; body: string }> {
  let url = start;
  for (let hop = 0; hop < 6; hop++) {
    assertPublicUrl(url);
    const res = await fetch(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: {
        "User-Agent": UA,
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-GB,en;q=0.9",
        "Cache-Control": "no-cache",
        "Upgrade-Insecure-Requests": "1",
        "Sec-Fetch-Dest": "document",
        "Sec-Fetch-Mode": "navigate",
        "Sec-Fetch-Site": "none",
      },
    });
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      await res.body?.cancel();
      url = new URL(res.headers.get("location")!, url);
      continue;
    }
    const len = Number(res.headers.get("content-length") || 0);
    if (len > MAX_BYTES) {
      await res.body?.cancel();
      throw new Error("Page too large");
    }
    const body = (await res.text()).slice(0, MAX_BYTES);
    return { res, finalUrl: url, body };
  }
  throw new Error("Too many redirects");
}

// ---------- parsing helpers ----------

function decode(s: string): string {
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&quot;/g, '"')
    .replace(/&apos;|&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .replace(/&pound;/g, "£")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function metaTags(html: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const tag of html.match(/<meta\s[^>]*>/gi) ?? []) {
    const attrs: Record<string, string> = {};
    for (const m of tag.matchAll(/([a-zA-Z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
      attrs[m[1].toLowerCase()] = m[2] ?? m[3] ?? "";
    }
    const key = (attrs.property || attrs.name || attrs.itemprop || "").toLowerCase();
    if (key && attrs.content && !out.has(key)) out.set(key, decode(attrs.content));
  }
  return out;
}

type Product = { name?: string; image?: string; price?: number; currency?: string };

function jsonLdProduct(html: string): Product | null {
  const blocks = html.matchAll(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi);
  const stack: unknown[] = [];
  for (const b of blocks) {
    try {
      stack.push(JSON.parse(b[1].trim()));
    } catch { /* ignore broken blocks */ }
  }
  while (stack.length) {
    const node = stack.shift();
    if (Array.isArray(node)) {
      stack.push(...node);
      continue;
    }
    if (!node || typeof node !== "object") continue;
    const o = node as Record<string, unknown>;
    if (o["@graph"]) stack.push(o["@graph"]);
    const type = o["@type"];
    const isProduct = type === "Product" || (Array.isArray(type) && type.includes("Product"));
    if (!isProduct) continue;

    const img = o.image;
    const image = typeof img === "string"
      ? img
      : Array.isArray(img)
      ? (typeof img[0] === "string" ? img[0] : (img[0] as Record<string, string>)?.url)
      : (img as Record<string, string>)?.url;

    let offers = o.offers as unknown;
    if (Array.isArray(offers)) offers = offers[0];
    const off = (offers ?? {}) as Record<string, unknown>;
    const spec = (Array.isArray(off.priceSpecification) ? off.priceSpecification[0] : off.priceSpecification) as
      | Record<string, unknown>
      | undefined;
    const rawPrice = off.price ?? off.lowPrice ?? spec?.price;
    const price = rawPrice != null ? parseFloat(String(rawPrice).replace(/[^\d.]/g, "")) : undefined;

    return {
      name: typeof o.name === "string" ? decode(o.name) : undefined,
      image,
      price: Number.isFinite(price) ? price : undefined,
      currency: (off.priceCurrency ?? spec?.priceCurrency) as string | undefined,
    };
  }
  return null;
}

function amazonProduct(html: string): Product {
  const title = html.match(/id="productTitle"[^>]*>([\s\S]*?)<\/span>/i)?.[1];
  const image = html.match(/data-old-hires="(https:[^"]+)"/i)?.[1] ??
    html.match(/"hiRes":"(https:[^"]+)"/i)?.[1] ??
    html.match(/id="landingImage"[^>]*src="(https:[^"]+)"/i)?.[1];

  let price: number | undefined;
  const coreIdx = html.search(/id="corePrice(?:Display_desktop)?_(?:feature_)?div"|id="corePrice_desktop"|id="apex_desktop"/i);
  const near = coreIdx >= 0 ? html.slice(coreIdx, coreIdx + 8000) : "";
  const m = near.match(/class="a-offscreen">\s*£\s*([\d,]+\.\d{2})/) ??
    html.match(/"priceAmount":\s*([\d.]+)/);
  if (m) price = parseFloat(m[1].replace(/,/g, ""));

  return { name: title ? decode(title) : undefined, image, price, currency: price ? "GBP" : undefined };
}

// Only flag a block when the page is a challenge/denial page, not just served by a CDN.
function detectBlock(status: number, html: string, hasProduct: boolean): string | null {
  if (/Robot Check|\/errors\/validateCaptcha|To discuss automated access to Amazon data/i.test(html)) return "amazon-captcha";
  if (/<title>\s*Access Denied\s*<\/title>/i.test(html)) return "akamai";
  if (/<title>\s*Just a moment\.\.\.\s*<\/title>/i.test(html)) return "cloudflare";
  if (hasProduct && status < 400) return null;
  if (/_Incapsula_/i.test(html)) return "incapsula";
  if (/px-captcha/i.test(html)) return "perimeterx";
  if (status >= 400) return `http-${status}`;
  return null;
}

// ---------- one link ----------

async function preview(raw: string) {
  const t0 = Date.now();
  const result: Record<string, unknown> = {
    ok: false,
    input: raw,
    url: null,
    finalUrl: null,
    store: null,
    title: null,
    image: null,
    price: null,
    currency: null,
    blocked: null,
    status: null,
    sources: {},
  };
  try {
    const url = cleanUrl(raw);
    result.url = url.toString();
    result.store = url.hostname.replace(/^www\./, "");

    const { res, finalUrl, body } = await fetchPage(url);
    result.status = res.status;
    result.finalUrl = finalUrl.toString();

    const meta = metaTags(body);
    const ld = jsonLdProduct(body);
    const isAmazon = /(^|\.)amazon\.[a-z.]+$/.test(finalUrl.hostname);
    const amz = isAmazon ? amazonProduct(body) : null;
    const src: Record<string, string> = {};

    const pick = <T>(pairs: [T | undefined | null | "", string][]): T | null => {
      for (const [v, s] of pairs) {
        if (v != null && v !== "" && !(typeof v === "number" && !Number.isFinite(v))) {
          src[pickKey] = s;
          return v as T;
        }
      }
      return null;
    };
    let pickKey = "title";
    result.title = pick<string>([
      [amz?.name, "amazon"],
      [ld?.name, "json-ld"],
      [meta.get("og:title"), "og"],
      [meta.get("twitter:title"), "twitter"],
      [body.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ? decode(body.match(/<title[^>]*>([\s\S]*?)<\/title>/i)![1]) : null, "title-tag"],
    ]);
    pickKey = "image";
    const img = pick<string>([
      [amz?.image, "amazon"],
      [ld?.image, "json-ld"],
      [meta.get("og:image"), "og"],
      [meta.get("og:image:secure_url"), "og"],
      [meta.get("twitter:image"), "twitter"],
    ]);
    result.image = img ? new URL(img, finalUrl).toString() : null;
    pickKey = "price";
    const metaPrice = meta.get("product:price:amount") ?? meta.get("og:price:amount") ?? meta.get("price");
    result.price = pick<number>([
      [ld?.price, "json-ld"],
      [amz?.price, "amazon"],
      [metaPrice ? parseFloat(metaPrice.replace(/[^\d.]/g, "")) : null, "meta"],
    ]);
    result.currency = ld?.currency ?? amz?.currency ?? meta.get("product:price:currency") ??
      meta.get("og:price:currency") ?? (result.price != null ? "GBP" : null);
    result.sources = src;

    const hasProduct = !!(ld?.name || amz?.name || meta.get("og:title") || meta.get("og:image"));
    result.blocked = detectBlock(res.status, body, hasProduct);
    if (result.blocked) {
      // Don't pass a denial page's "Access Denied" title etc. through as product data
      Object.assign(result, { title: null, image: null, price: null, currency: null, sources: {} });
    }
    result.ok = !result.blocked && !!result.title && !!result.image;
  } catch (e) {
    result.error = e instanceof Error ? e.message : String(e);
  }
  result.ms = Date.now() - t0;
  return result;
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      out[idx] = await fn(items[idx]);
    }
  });
  await Promise.all(workers);
  return out;
}

// ---------- handler ----------

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// Only signed-in wishlist members (wl_members) may use this. Asks the database with the
// caller's own token, so row-level security and wl_is_member() decide — same as the app.
// For a temporary test with the anon key only, set the secret ALLOW_ANON_TEST=true.
async function isMember(req: Request): Promise<boolean> {
  if (Deno.env.get("ALLOW_ANON_TEST") === "true") return true;
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return false;
  try {
    const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/rest/v1/rpc/wl_is_member`, {
      method: "POST",
      headers: {
        Authorization: auth,
        apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    return r.ok && (await r.json()) === true;
  } catch {
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!(await isMember(req))) return json({ error: "Wishlist members only" }, 401);

  let body: { url?: string; urls?: string[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Send JSON: { url } or { urls: [] }" }, 400);
  }

  if (Array.isArray(body.urls)) {
    const urls = body.urls.filter((u) => typeof u === "string").slice(0, MAX_BATCH);
    return json({ results: await mapLimit(urls, CONCURRENCY, preview) });
  }
  if (typeof body.url === "string") return json(await preview(body.url));
  return json({ error: "Send JSON: { url } or { urls: [] }" }, 400);
});
