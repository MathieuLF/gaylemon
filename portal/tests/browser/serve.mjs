import { createReadStream, existsSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize } from "node:path";

const root = normalize(join(import.meta.dirname, "../.."));
const pages = new Map([["/", "index.html"], ["/resume", "resume.html"], ["/classements", "classements.html"], ["/carte", "carte.html"], ["/terminal", "terminal.html"], ["/informations", "informations.html"]]);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml", ".woff2": "font/woff2" };
createServer((request, response) => {
  const url = new URL(request.url, "http://127.0.0.1:4179");
  if (url.pathname === "/version") return json(response, { version: "2026.08.26.1", commit: "0123456789abcdef", channel: "test" });
  if (url.pathname === "/api/public/site-state/v1") {
    const archived = url.searchParams.get("season") === "saison-2026";
    return json(response, { mode: archived ? "archived" : "active", readOnly: archived, polling: !archived, season: { id: "season-2026", slug: "saison-2026", title: "Saison 2026", state: archived ? "archived" : "active", archivedAt: archived ? "2026-08-26T12:00:00Z" : null } });
  }
  if (url.pathname.endsWith("/api/public/events/v1") || url.pathname === "/api/public/events/v1") return json(response, { ok: true, schemaVersion: 1, source: "postgresql", revision: "empty", updatedAt: "2026-08-26T12:00:00Z", observedAt: "2026-08-26T12:00:00Z", freshness: "current", sourceStatus: "available", lagSeconds: 0, offset: 0, limit: 6, total: 0, events: [], facets: { types: [], players: [] }, summary: {} });
  if (url.pathname.includes("/data/") || url.pathname.endsWith("/public-events-channel.json")) return json(response, { ok: false, status: "documented-but-unavailable", updatedAt: "2026-08-26T12:00:00Z" });
  let pathname = url.pathname;
  const season = pathname.match(/^\/saisons\/saison-2026(\/.*)?$/);
  if (season) pathname = season[1] || "/";
  const page = pages.get(pathname.replace(/\/$/, "") || "/");
  let target = page ? join(root, page) : join(root, pathname.replace(/^\//, ""));
  target = normalize(target);
  if (!target.startsWith(root) || !existsSync(target)) { response.writeHead(404); response.end("not found"); return; }
  response.writeHead(200, { "Content-Type": types[extname(target)] || "application/octet-stream", "Cache-Control": "no-cache" });
  createReadStream(target).pipe(response);
}).listen(4179, "127.0.0.1");

function json(response, value) {
  response.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  response.end(JSON.stringify(value));
}
