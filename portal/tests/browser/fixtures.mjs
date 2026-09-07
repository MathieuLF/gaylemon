import { readFileSync } from "node:fs";

// Only tracked examples are read. Never serve a developer's real portal/data files.
const date = "2026-09-05";
const timestamp = `${date}T16:00:00Z`;
const example = (name) => JSON.parse(readFileSync(new URL(`../../data/${name}.example.json`, import.meta.url), "utf8"));
const normalize = (value) => {
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalize(item)]));
  if (typeof value === "string" && value.startsWith("assets/game/")) return "assets/favicon.svg";
  if (typeof value === "string" && /^2026-\d\d-\d\dT/.test(value)) return timestamp;
  return value;
};
const snapshot = normalize(example("public-save-snapshot"));
const names = ["Aurore", "Basile", "Citron des montagnes", "Dune", "Églantine", "Fuchsia", "Givre", "Horizon"];
snapshot.players = names.map((name, index) => {
  const player = structuredClone(snapshot.players[0]);
  player.name = name;
  player.level = 18 + index;
  player.position = { mapX: index * 30, mapY: index * 25, leftPercent: 20 + index * 7, topPercent: 25 + index * 5 };
  player.pals.collection = Array.from({ length: 24 }, (_, i) => ({
    ...player.pals.collection[0], name: `Compagnon ${i + 1}`, icon: "assets/favicon.svg",
    container: i < 5 ? "party" : "palbox", level: 17,
    experienceProgress: { percent: i * 4, nextLevel: 18, remaining: 1000 - i * 20 },
  }));
  player.pals.total = 24;
  return player;
});
snapshot.summary = { ...snapshot.summary, players: names.length, pals: names.length * 24 };
const index = normalize(example("public-save-index"));
index.players = snapshot.players.map(({ character, inventory, ...player }) => ({ ...player, pals: { ...player.pals, collection: undefined } }));
index.summary = snapshot.summary;
const stats = normalize(example("public-stats"));
stats.players = names.map((name, i) => ({ ...stats.players[0], name, isOnline: i < 2, level: 18 + i, totalOnlineSeconds: 1800 + i * 600 }));
const bases = normalize(example("public-save-bases"));
bases.bases[0].players = [names[0]];
const uptime = normalize(example("public-uptime"));
uptime.monitors[0].uptime24h = null;
Object.assign(uptime.summary, { uptime24hAverage: null, uptimeLast24h: null, unavailableSecondsLast24h: null });
const documents = new Map([
  ["public-save-index", index], ["public-save-snapshot", snapshot], ["public-stats", stats],
  ["public-save-bases", bases], ["public-save-diagnostics", normalize(example("public-save-diagnostics"))],
  ["public-metrics", normalize(example("public-metrics"))], ["public-uptime", uptime],
]);
const events = Array.from({ length: 18 }, (_, i) => ({
  key: `fixture-${i}`, id: 18 - i, occurredAt: `${date}T${String(16 - Math.floor(i / 3)).padStart(2, "0")}:00:00Z`,
  type: ["craft", "production", "capture"][i % 3], player: names[i % 3],
  title: ["Fabrication terminée", "Ressources produites", "Pal capturé"][i % 3],
  message: "Une nouvelle étape pour les explorateurs.", source: "save", confidence: "confirmed",
  details: { quantity: 3, itemName: "Bois", palName: "Lamball", types: [["craft", "production", "capture"][i % 3]] },
}));

export function publicFixture(url) {
  const path = url.pathname.replace(/^\/saisons\/saison-2026/, "");
  if (path === "/api/public/events/v1") {
    let selected = !url.searchParams.has("date") || url.searchParams.get("date") === date ? events : [];
    for (const key of ["type", "player"]) if (url.searchParams.get(key)) selected = selected.filter((event) => event[key] === url.searchParams.get(key));
    if (url.searchParams.get("search")) selected = selected.filter((event) => JSON.stringify(event).toLowerCase().includes(url.searchParams.get("search").toLowerCase()));
    const offset = Number(url.searchParams.get("offset") || 0);
    const limit = Number(url.searchParams.get("limit") || 6);
    return { ok: true, schemaVersion: 1, source: "postgresql", revision: "fixture-events", updatedAt: timestamp, observedAt: timestamp,
      freshness: "current", sourceStatus: "available", lagSeconds: 0, date: url.searchParams.get("date"), offset, limit, total: selected.length,
      events: selected.slice(offset, offset + limit), facets: { types: ["craft", "production", "capture"], players: names.slice(0, 3) },
      summary: { totalEvents: events.length, firstAt: events.at(-1).occurredAt, lastAt: events[0].occurredAt },
    };
  }
  const slug = path.match(/^\/data\/players\/(.+)\.json$/)?.[1];
  if (slug) {
    const player = snapshot.players.find((row) => row.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-") === slug);
    return { ...index, players: undefined, player };
  }
  const name = path.match(/^\/data\/(.+)\.json$/)?.[1];
  if (documents.has(name)) {
    const value = structuredClone(documents.get(name));
    // A changing observation lets browser tests exercise the real polling path.
    if (name === "public-stats") value.updatedAt = new Date().toISOString();
    return value;
  }
  if (path.includes("/data/") || path.endsWith("/public-events-channel.json")) return { ok: false, status: "documented-but-unavailable", updatedAt: timestamp };
}
