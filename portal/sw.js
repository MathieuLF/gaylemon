const CACHE_PREFIX = "gaylemon-public-";
// Cache lookups preserve the exact request identity; query parameters are never ignored.
const CACHE = CACHE_PREFIX + "__GAYLEMON_ASSET_RELEASE__";
const CACHE_META = CACHE_PREFIX + "meta";
const CACHE_META_KEY = "/__gaylemon-cache-releases__";
const RUNTIME = CACHE + "-runtime";
const MAX_RUNTIME_ENTRIES = 64;
const MAX_RUNTIME_BYTES = 24 * 1024 * 1024;
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
let runtimeSizes;
let cacheWrites = Promise.resolve();
const SHELL = ["/", "/offline.html", "/informations", "/confidentialite", "__GAYLEMON_STYLES__", "__GAYLEMON_APP__", "/assets/favicon.svg", "/site.webmanifest"];

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.all(SHELL.map(async (url) => {
      const request = new Request(url, { cache: "reload", credentials: "same-origin" });
      const response = await fetch(request);
      if (!response.ok) throw new Error(`precache ${url}`);
      await cache.put(request, response);
    }));
    const meta = await caches.open(CACHE_META);
    const prior = await meta.match(CACHE_META_KEY);
    let releases = [];
    if (prior) {
      try { releases = await prior.json(); } catch { releases = []; }
    }
    releases = [CACHE, ...releases.filter((name) => name !== CACHE && name !== CACHE_META)].slice(0, 2);
    await meta.put(CACHE_META_KEY, new Response(JSON.stringify(releases), { headers: { "Content-Type": "application/json" } }));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const meta = await caches.open(CACHE_META);
    const stored = await meta.match(CACHE_META_KEY);
    let releases = [CACHE];
    if (stored) {
      try { releases = await stored.json(); } catch { releases = [CACHE]; }
    }
    const keep = new Set([CACHE_META, ...releases.slice(0, 2).flatMap((name) => [name, name + "-runtime"])]);
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith(CACHE_PREFIX) && !keep.has(key)).map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

// Serialize writes so concurrent refreshes cannot exceed the storage budget.
async function storeResponse(request, response) {
  const url = new URL(request.url);
  if (!url.search && SHELL.includes(url.pathname)) {
    await (await caches.open(CACHE)).put(request, response);
    return;
  }
  const bytes = (await response.clone().arrayBuffer()).byteLength;
  if (bytes > MAX_RESPONSE_BYTES) return;
  const cache = await caches.open(RUNTIME);
  if (!runtimeSizes) {
    const entries = await Promise.all((await cache.keys()).map(async (key) => {
      const stored = await cache.match(key);
      return [key.url, (await stored.arrayBuffer()).byteLength];
    }));
    runtimeSizes = new Map(entries);
  }
  runtimeSizes.delete(request.url);
  let total = [...runtimeSizes.values()].reduce((sum, size) => sum + size, 0);
  while (runtimeSizes.size && (runtimeSizes.size >= MAX_RUNTIME_ENTRIES || total + bytes > MAX_RUNTIME_BYTES)) {
    const [oldest, size] = runtimeSizes.entries().next().value;
    await cache.delete(oldest);
    runtimeSizes.delete(oldest);
    total -= size;
  }
  await cache.put(request, response);
  runtimeSizes.set(request.url, bytes);
}

async function cachedResponse(request) {
  const meta = await caches.open(CACHE_META);
  let releases = [CACHE];
  try {
    const stored = await meta.match(CACHE_META_KEY);
    if (stored) releases = [CACHE, ...(await stored.json()).filter((name) => name !== CACHE)].slice(0, 2);
  } catch { /* The current release remains usable if metadata is unavailable. */ }
  for (const release of releases) {
    for (const name of [release + "-runtime", release]) {
      const cached = await (await caches.open(name)).match(request);
      if (cached) return cached;
    }
  }
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin || url.pathname.startsWith("/ops") || url.pathname.startsWith("/api/agent") || url.pathname.startsWith("/api/ingest")) return;
  event.respondWith((async () => {
    try {
      const response = await fetch(request);
      if (response.ok && (request.mode === "navigate" || url.pathname.startsWith("/assets/") || url.pathname.startsWith("/data/") || url.pathname.startsWith("/saisons/") || url.pathname.startsWith("/api/public/"))) {
        const copy = response.clone();
        cacheWrites = cacheWrites.then(() => storeResponse(request, copy)).catch(() => {
          runtimeSizes = undefined;
        });
        event.waitUntil(cacheWrites);
      }
      return response;
    } catch {
      try {
        const cached = await cachedResponse(request);
        if (cached) return cached;
        if (request.mode === "navigate") {
          const offline = await cachedResponse("/offline.html");
          if (offline) return offline;
        }
      } catch { /* Storage may also be unavailable while offline. */ }
      return new Response(JSON.stringify({ ok: false, error: "offline" }), { status: 503, headers: { "Content-Type": "application/json; charset=utf-8" } });
    }
  })());
});
