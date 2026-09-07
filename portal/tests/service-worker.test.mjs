import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const source = await readFile(new URL("../sw.js", import.meta.url), "utf8");
const origin = "https://portal.example";
class LocalRequest extends Request {
  constructor(input, options) { super(typeof input === "string" ? new URL(input, origin) : input, options); }
}

function worker({ release = "one", storage = new Map() } = {}) {
  const listeners = new Map();
  const state = { offline: false, failWrite: false, failOpen: false, body: "network" };
  const key = (input) => new URL(typeof input === "string" ? input : input.url, origin).href;
  const caches = {
    async open(name) {
      if (state.failOpen) throw new Error("storage-disabled");
      if (!storage.has(name)) storage.set(name, new Map());
      const entries = storage.get(name);
      return {
        async match(input) { return entries.get(key(input))?.clone(); },
        async put(input, response) {
          if (state.failWrite) throw new Error("quota-exceeded");
          entries.set(key(input), response.clone());
        },
        async delete(input) { return entries.delete(key(input)); },
        async keys() { return [...entries.keys()].map((url) => new LocalRequest(url)); },
      };
    },
    async keys() { return [...storage.keys()]; },
    async delete(name) { return storage.delete(name); },
  };
  vm.runInNewContext(source.replaceAll("__GAYLEMON_ASSET_RELEASE__", release).replaceAll("__GAYLEMON_STYLES__", "/assets/styles.css").replaceAll("__GAYLEMON_APP__", "/assets/app.js"), {
    self: { location: { origin }, addEventListener: (name, fn) => listeners.set(name, fn), skipWaiting: async () => {}, clients: { claim: async () => {} } },
    Request: LocalRequest, Response, URL, caches,
    fetch: async () => { if (state.offline) throw new Error("offline"); return new Response(state.body); },
  });
  async function dispatch(name, request) {
    const work = [];
    let result;
    listeners.get(name)({ request, waitUntil: (promise) => work.push(promise), respondWith: (promise) => { result = promise; } });
    const response = await result;
    await Promise.all(work);
    return response;
  }
  return { state, storage, dispatch, fetch: (path, options) => dispatch("fetch", new LocalRequest(path, options)) };
}

test("offline reads preserve date, page and season identities", async () => {
  const sw = worker();
  for (const [path, body] of [["/api/public/events/v1?date=2026-09-05&page=1", "today"], ["/api/public/events/v1?date=2026-09-04&page=1", "yesterday"], ["/saisons/archive/data/public-stats.json", "archive"]]) {
    sw.state.body = body;
    await sw.fetch(path);
  }
  sw.state.offline = true;
  assert.equal(await (await sw.fetch("/api/public/events/v1?date=2026-09-05&page=1")).text(), "today");
  assert.equal(await (await sw.fetch("/api/public/events/v1?date=2026-09-04&page=1")).text(), "yesterday");
  assert.equal((await sw.fetch("/api/public/events/v1?date=2026-09-05&page=2")).status, 503);
  assert.equal(await (await sw.fetch("/saisons/archive/data/public-stats.json")).text(), "archive");
  assert.equal((await sw.fetch("/data/public-stats.json")).status, 503);
});

test("storage errors never discard a successful network response", async () => {
  for (const failure of ["failWrite", "failOpen"]) {
    const sw = worker();
    sw.state[failure] = true;
    const response = await sw.fetch("/data/public-stats.json");
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "network");
    sw.state.offline = true;
    assert.equal((await sw.fetch("/data/public-stats.json")).status, 503);
  }
});

test("concurrent writes respect the entry budget and preserve the shell", async () => {
  const sw = worker();
  await sw.dispatch("install");
  await Promise.all(Array.from({ length: 80 }, (_, i) => sw.fetch(`/api/public/events/v1?page=${i}`)));
  assert.equal(sw.storage.get("gaylemon-public-one-runtime").size, 64);
  assert.ok(sw.storage.get("gaylemon-public-one").has(`${origin}/offline.html`));
  sw.state.offline = true;
  assert.equal((await sw.fetch("/api/public/events/v1?page=0")).status, 503);
  assert.equal((await sw.fetch("/api/public/events/v1?page=79")).status, 200);
});

test("the byte budget evicts oldest responses and ignores oversized bodies", async () => {
  const sw = worker();
  sw.state.body = "x".repeat(8 * 1024 * 1024);
  for (let i = 0; i < 4; i++) await sw.fetch(`/data/page-${i}.json`);
  assert.equal(sw.storage.get("gaylemon-public-one-runtime").size, 3);
  sw.state.body += "x";
  assert.equal((await sw.fetch("/data/oversize.json")).status, 200);
  assert.equal(sw.storage.get("gaylemon-public-one-runtime").size, 3);
});

test("current release wins, one prior release survives activation", async () => {
  const first = worker();
  await first.dispatch("install");
  first.state.body = "old";
  await first.fetch("/data/shared.json");
  const second = worker({ release: "two", storage: first.storage });
  await second.dispatch("install");
  second.state.body = "current";
  await second.fetch("/data/shared.json");
  second.state.offline = true;
  assert.equal(await (await second.fetch("/data/shared.json")).text(), "current");
  const third = worker({ release: "three", storage: first.storage });
  await third.dispatch("install");
  await third.dispatch("activate");
  assert.ok(!third.storage.has("gaylemon-public-one"));
  assert.ok(!third.storage.has("gaylemon-public-one-runtime"));
  assert.ok(third.storage.has("gaylemon-public-two"));
});

test("private, foreign and non-GET requests bypass the service worker", async () => {
  const sw = worker();
  for (const path of ["/ops", "/ops/api/snapshot", "/api/agent/poll", "/api/ingest/batches", "https://other.example/data/test.json"]) assert.equal(await sw.fetch(path), undefined);
  assert.equal(await sw.fetch("/data/public-stats.json", { method: "POST" }), undefined);
  assert.equal(sw.storage.size, 0);
});
