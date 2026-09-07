import assert from "node:assert/strict";
import test from "node:test";
import { createJsonReader } from "../src/shared/data.js";

test("refreshes keep stable request URLs without losing query parameters", async () => {
  const previous = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (url, options) => {
    requests.push([url, options.cache]);
    return new Response('{"ok":true}');
  };
  try {
    let season = "";
    const readJson = createJsonReader(() => season);
    await readJson("data/public-stats.json");
    await readJson("data/public-stats.json");
    await readJson("api/public/events/v1?date=2026-09-05&offset=6", { revalidate: true });
    season = "/saisons/ete";
    await readJson("data/public-stats.json");
    await readJson("data/shard.json", { immutable: true });
    assert.deepEqual(requests, [
      ["/data/public-stats.json", "no-store"], ["/data/public-stats.json", "no-store"],
      ["/api/public/events/v1?date=2026-09-05&offset=6", "no-cache"],
      ["/saisons/ete/data/public-stats.json", "no-store"], ["/saisons/ete/data/shard.json", "force-cache"],
    ]);
  } finally { globalThis.fetch = previous; }
});

test("cached or fetched JSON still requires the expected integrity digest", async () => {
  const previousFetch = globalThis.fetch;
  const previousWindow = globalThis.window;
  globalThis.window = { crypto: globalThis.crypto };
  globalThis.fetch = async () => new Response('{"ok":true}');
  try {
    const readJson = createJsonReader(() => "");
    const digest = Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode('{"ok":true}'))).toString("hex");
    assert.deepEqual(await readJson("data/shard.json", { expectedSha256: digest }), { ok: true });
    await assert.rejects(readJson("data/shard.json", { expectedSha256: "0".repeat(64) }), /sha256-mismatch/);
  } finally { globalThis.fetch = previousFetch; globalThis.window = previousWindow; }
});
