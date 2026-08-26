const CACHE = "gaylemon-public-v1";
const SHELL = ["/", "/offline.html", "/informations", "/assets/styles.css", "/assets/app.js", "/assets/favicon.svg", "/site.webmanifest"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))).then(() => self.clients.claim()));
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
