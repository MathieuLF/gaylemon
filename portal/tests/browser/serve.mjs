import { publicFixture } from "./fixtures.mjs";
import { createReadStream, existsSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize, sep } from "node:path";

const root = normalize(join(import.meta.dirname, "../.."));
const pages = new Map([["/", "index.html"], ["/resume", "resume.html"], ["/classements", "classements.html"], ["/carte", "carte.html"], ["/terminal", "terminal.html"], ["/github", "github.html"], ["/informations", "informations.html"], ["/confidentialite", "confidentialite.html"]]);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8", ".svg": "image/svg+xml", ".woff2": "font/woff2" };
const securityHeaders = { "Content-Security-Policy": "default-src 'self'; base-uri 'self'; object-src 'none'; form-action 'self'; frame-ancestors 'none'; img-src 'self' data:; style-src 'self'; style-src-attr 'unsafe-inline'; script-src 'self'; connect-src 'self'" };
createServer((request, response) => {
  const url = new URL(request.url, "http://127.0.0.1:4179");
  if (url.pathname === "/ops") {
    const source = readFileSync(join(root, "../internal/web/ops.go"), "utf8");
    const html = source.slice(source.indexOf("`<!doctype" ) + 1, source.lastIndexOf("`")).replaceAll("{{NONCE}}", "local-fixture");
    response.writeHead(200, { "Content-Type": types[".html"], "Content-Security-Policy": "default-src 'self'; style-src 'nonce-local-fixture'; script-src 'nonce-local-fixture'; connect-src 'self'" });
    response.end(html);
    return;
  }
  if (url.pathname === "/ops/api/snapshot") return json(response, { generatedAt: "2026-09-05T16:00:00Z", databaseBytes: 4096, agents: [], seasons: [], recentRuns: [], recentCommands: [] });
  if (url.pathname === "/api/version") return json(response, { schema: "suite.version.v1", application: "gaylemon", version: "1.0.0", commit: "0123456789abcdef0123456789abcdef01234567", builtAt: "2026-08-26T12:00:00Z" });
  if (url.pathname === "/api/public/site-state/v1") {
    const archived = url.searchParams.get("season") === "saison-2026";
    return json(response, { mode: archived ? "archived" : "active", readOnly: archived, polling: !archived, season: { id: "season-2026", slug: "saison-2026", title: "Saison 2026", state: archived ? "archived" : "active", archivedAt: archived ? "2026-08-26T12:00:00Z" : null } });
  }
  const fixture = publicFixture(url);
  if (fixture) return json(response, fixture);
  if (url.pathname === "/sw.js") {
    const worker = readFileSync(join(root, "sw.js"), "utf8").replaceAll("__GAYLEMON_ASSET_RELEASE__", "browser-fixture").replaceAll("__GAYLEMON_STYLES__", "/assets/styles.css").replaceAll("__GAYLEMON_APP__", "/assets/app.js");
    response.writeHead(200, { "Content-Type": types[".js"], "Cache-Control": "no-store", ...securityHeaders });
    response.end(worker);
    return;
  }
  let pathname = url.pathname;
  const season = pathname.match(/^\/saisons\/saison-2026(\/.*)?$/);
  if (season) pathname = season[1] || "/";
  const page = pages.get(pathname.replace(/\/$/, "") || "/");
  let target = page ? join(root, page) : join(root, pathname.replace(/^\//, ""));
  target = normalize(target);
  if (!target.startsWith(root + sep) || !existsSync(target)) { response.writeHead(404); response.end("not found"); return; }
  response.writeHead(200, { "Content-Type": types[extname(target)] || "application/octet-stream", "Cache-Control": "no-cache", ...securityHeaders });
  createReadStream(target).pipe(response);
}).listen(4179, "127.0.0.1");

function json(response, value) {
  response.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...securityHeaders });
  response.end(JSON.stringify(value));
}
