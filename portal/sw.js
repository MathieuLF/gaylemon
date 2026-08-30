const CACHE_PREFIX = "gaylemon-public-";
// Cache lookups preserve the exact request identity; query parameters are never ignored.
const CACHE = CACHE_PREFIX + "__GAYLEMON_ASSET_RELEASE__";
const CACHE_META = CACHE_PREFIX + "meta";
const CACHE_META_KEY = "/__gaylemon-cache-releases__";
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
    const keep = new Set([CACHE_META, ...releases.slice(0, 2)]);
    const keys = await caches.keys();
    await Promise.all(keys.filter((key) => key.startsWith(CACHE_PREFIX) && !keep.has(key)).map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin || url.pathname.startsWith("/ops") || url.pathname.startsWith("/api/agent") || url.pathname.startsWith("/api/ingest")) return;
  event.respondWith((async () => {
    try {
      const response = await fetch(request);
      if (response.ok && (request.mode === "navigate" || url.pathname.startsWith("/assets/") || url.pathname.startsWith("/data/") || url.pathname.startsWith("/saisons/") || url.pathname.startsWith("/api/public/"))) {
        const cache = await caches.open(CACHE);
        await cache.put(request, response.clone());
      }
      return response;
    } catch {
      const cached = await caches.match(request);
      if (cached) return cached;
      if (request.mode === "navigate") return caches.match("/offline.html");
      return new Response(JSON.stringify({ ok: false, error: "offline" }), { status: 503, headers: { "Content-Type": "application/json; charset=utf-8" } });
    }
  })());
});
