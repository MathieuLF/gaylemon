import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const portalRoot = new URL("../", import.meta.url);

async function portalFile(path) {
  return readFile(new URL(path, portalRoot), "utf8");
}

async function portalSha256(path) {
  const bytes = await readFile(new URL(path, portalRoot));
  return createHash("sha256").update(bytes).digest("hex");
}

function extractFunction(source, name) {
  const asyncSignature = `async function ${name}`;
  const syncSignature = `function ${name}`;
  const asyncStart = source.indexOf(asyncSignature);
  const start = asyncStart >= 0 ? asyncStart : source.indexOf(syncSignature);
  assert.notEqual(start, -1, `${name} doit exister`);
  let parameterDepth = 0;
  let parametersOpened = false;
  let bodyStart = -1;
  for (let index = source.indexOf("(", start); index < source.length; index += 1) {
    if (source[index] === "(") {
      parameterDepth += 1;
      parametersOpened = true;
    } else if (source[index] === ")") {
      parameterDepth -= 1;
      if (parametersOpened && parameterDepth === 0) {
        bodyStart = source.indexOf("{", index + 1);
        break;
      }
    }
  }
  assert.notEqual(bodyStart, -1, `${name} doit avoir un corps`);
  let depth = 0;
  let opened = false;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === "{") {
      depth += 1;
      opened = true;
    } else if (source[index] === "}") {
      depth -= 1;
      if (opened && depth === 0) {
        return Function(`"use strict"; return (${source.slice(start, index + 1)});`)();
      }
    }
  }
  throw new Error(`${name} est incomplète`);
}

test("le terminal active v6 avant le repli v5 et valide chaque génération", async () => {
  const app = await portalFile("assets/app.js");
  const preferredLoader = app.slice(
    app.indexOf("async function loadTerminalEventsPreferred"),
    app.indexOf("async function loadHomeEchoes") > app.indexOf("async function loadTerminalEventsPreferred")
      ? app.indexOf("async function loadHomeEchoes")
      : app.indexOf("function primaryEventRevision"),
  );

  assert.match(app, /data\/public-events-manifest-v6\.json/);
  assert.match(app, /data\/public-events-v6\/\$\{generationId\}\/head\.json/);
  assert.match(app, /mixed-v6-generation/);
  assert.match(app, /mixed-v6-day-generation/);
  assert.match(app, /mixed-v6-daily-generation/);
  assert.match(app, /captureV6State/);
  assert.match(app, /restoreV6State/);
  assert.match(app, /stale: true/);
  assert.match(preferredLoader, /loadTerminalEventsV6/);
  assert.match(preferredLoader, /loadEventsIndex/);
  assert.doesNotMatch(preferredLoader, /loadEvents\(/);
});

test("les fragments et bilans v6 restent liés au generationId actif", async () => {
  const app = await portalFile("assets/app.js");
  const orderRank = extractFunction(app, "publicEventOrderRank");
  const sortEvents = extractFunction(app, "sortEventsNewestFirst");

  assert.match(app, /eventDayCache/);
  assert.match(app, /dailyV6Cache/);
  assert.match(app, /entry\.dailyPath/);
  assert.match(app, /public-daily\/\$\{generationId\}\/\$\{dateKey\}\.json/);
  assert.match(app, /String\(head \? payload\.baseGenerationId : payload\.generationId\)/);
  assert.match(app, /expectedSha256: manifest\.head\.sha256/);
  assert.match(app, /eventDayCache\.clear\(\)/);
  assert.match(app, /dailyV6Cache\.clear\(\)/);
  assert.match(app, /days\.length !== rawDays\.length/);
  assert.doesNotMatch(app, /\|\| !days\.length \|\|/);
  assert.equal(orderRank({ type: "leave", source: "journal" }), 0);
  assert.equal(orderRank({ type: "capture", source: "save" }), 1);
  assert.equal(orderRank({ type: "reconnect", source: "players" }), 2);
  globalThis.parseDate = (value) => new Date(value);
  globalThis.publicEventOrderRank = orderRank;
  try {
    const sameTime = "2026-07-18T10:00:00-04:00";
    const orderedIds = sortEvents([
      { id: 2, occurredAt: sameTime, type: "join", source: "journal" },
      { id: 4, occurredAt: sameTime, type: "capture", source: "save" },
      { id: 1, occurredAt: sameTime, type: "leave", source: "players" },
      { id: 9, occurredAt: sameTime, type: "capture", source: "save" },
      { id: 5, occurredAt: "2026-07-18T10:01:00-04:00", type: "capture", source: "save" },
    ], { canonical: true }).map((event) => event.id);
    assert.deepEqual(orderedIds, [5, 1, 9, 4, 2]);
  } finally {
    delete globalThis.parseDate;
    delete globalThis.publicEventOrderRank;
  }
  assert.match(app, /publicEventOrderRank\(left\) - publicEventOrderRank\(right\)/);
  assert.match(app, /sortEventsNewestFirst\(\[\.\.\.byKey\.values\(\)\], \{ canonical: true \}\)/);
});

test("le repli v5 remplace la queue froide couverte par le récent canonique", async () => {
  const app = await portalFile("assets/app.js");
  const replacementWindow = extractFunction(app, "v5TailReplacementWindow");
  const mergePagedTail = extractFunction(app, "mergeV5PagedTailEvents");
  const mergePayloads = extractFunction(app, "mergeEventPayloads");
  const occurredAt = "2026-07-18T10:01:00-04:00";
  const olderAt = "2026-07-18T09:50:00-04:00";
  const base = {
    version: 5,
    schemaVersion: 5,
    projectionRevision: 20,
    revision: "5:cold:20",
    updatedAt: occurredAt,
    summary: { events: 2, totalEvents: 2 },
    events: [
      { key: "raw-craft", id: 401, occurredAt, type: "craft", source: "save" },
      { key: "older", id: 390, occurredAt: olderAt, type: "server", source: "journal" },
    ],
  };
  const recent = {
    version: 5,
    schemaVersion: 5,
    projectionRevision: 21,
    revision: "5:recent:21",
    updatedAt: "2026-07-18T10:03:00-04:00",
    recent: true,
    summary: { events: 3, totalEvents: 3 },
    projectionWindow: {
      mode: "replace-tail",
      replaceFrom: "2026-07-18T10:00:00-04:00",
      complete: true,
      fromProjectionRevision: 20,
      throughProjectionRevision: 21,
    },
    events: [
      { key: "new-server", id: 403, occurredAt: "2026-07-18T10:03:00-04:00", type: "server", source: "journal" },
      { key: "grouped-craft", id: 402, occurredAt: "2026-07-18T10:02:00-04:00", type: "craft", source: "save", details: { aggregatedEvents: 2 } },
      { key: "older", id: 390, occurredAt: olderAt, type: "server", source: "journal" },
    ],
  };

  const globals = {
    parseDate: (value) => value ? new Date(value) : null,
    dedupeSessionFallbackEvents: (events) => [...(Array.isArray(events) ? events : [])],
    eventIdentity: (event) => event?.key ? `key:${event.key}` : `${event?.source || "event"}:${event?.id ?? ""}`,
    sortEventsNewestFirst: (events) => [...events].sort((left, right) => (
      new Date(right.occurredAt) - new Date(left.occurredAt) || Number(right.id || 0) - Number(left.id || 0)
    )),
    primaryEventRevision: (payload) => payload?.recent ? "" : String(payload?.sourceRevision || payload?.revision || "").split("+")[0],
    recentEventRevision: (payload) => payload?.recent ? String(payload?.revision || "") : "",
    latestDateValue: (...values) => values.map((value) => value ? new Date(value) : null).filter(Boolean).sort((left, right) => right - left)[0] || null,
    v5TailReplacementWindow: replacementWindow,
  };
  Object.assign(globalThis, globals);
  try {
    const merged = mergePayloads(base, recent);
    assert.deepEqual(merged.events.map((event) => event.id), [403, 402, 390]);
    assert.equal(merged.events.some((event) => event.key === "raw-craft"), false);
    assert.equal(merged.summary.totalEvents, 3);
    assert.equal(merged.projectionRevision, 21);

    const rebuiltHead = mergePagedTail(base.events, base, recent);
    assert.deepEqual(rebuiltHead.map((event) => event.id), [403, 402, 390]);
    assert.deepEqual(rebuiltHead.slice(0, 2).map((event) => event.id), [403, 402]);

    const olderColdBase = { ...base, projectionRevision: 19 };
    const olderCold = mergePayloads(olderColdBase, recent);
    assert.equal(olderCold.events.some((event) => event.key === "raw-craft"), false);
    assert.equal(replacementWindow(olderColdBase, recent).fullyCovered, false);

    const futureBase = { ...base, projectionRevision: 22 };
    const future = mergePayloads(futureBase, recent);
    assert.equal(future.events.some((event) => event.key === "raw-craft"), true);
  } finally {
    Object.keys(globals).forEach((name) => delete globalThis[name]);
  }

  assert.match(app, /loadEventsRecent\(true, \{ snapshotOnly: true \}\)/);
  assert.match(app, /sourceStart === 0[\s\S]*mergeV5PagedTailEvents/);
});

test("le sondage v6 passe par le petit pointeur actif et les manifestes immuables", async () => {
  const app = await portalFile("assets/app.js");
  const loader = app.slice(
    app.indexOf("async function fetchEventsV6Candidate"),
    app.indexOf("function commitEventsV6Candidate"),
  );

  assert.match(loader, /data\/public-events-head-v6\.json/);
  assert.match(loader, /pointer\.manifest\.path/);
  assert.match(loader, /expectedSha256: pointer\.manifest\.sha256/);
  assert.match(loader, /unchanged: true/);
  assert.match(loader, /mixed-v6-active-pointer/);
});

test("le canal public active v6 et conserve v5 comme repli temporaire", async () => {
  const [app, channel] = await Promise.all([
    portalFile("assets/app.js"),
    portalFile("public-events-channel.json").then(JSON.parse),
  ]);
  const loader = app.slice(
    app.indexOf("async function fetchEventsV6Candidate"),
    app.indexOf("function commitEventsV6Candidate"),
  );

  assert.deepEqual(channel, {
    schemaVersion: 1,
    activeContract: "v6",
    candidateContract: "v6",
  });
  assert.match(app, /async function loadEventsContractChannel/);
  assert.match(loader, /loadEventsContractChannel\(force\)/);
  assert.match(loader, /preferredContract !== "v6"/);
  assert.ok(loader.indexOf("loadEventsContractChannel") < loader.indexOf("public-events-head-v6.json"));
});

test("un fragment manquant ou invalide ne peut pas adopter le nouveau manifeste", async () => {
  const app = await portalFile("assets/app.js");
  const stageAndCommit = extractFunction(app, "stageAndCommitV6Candidate");
  const candidate = { ok: true, generationId: "nouvelle-generation" };
  let commits = 0;
  const commit = () => {
    commits += 1;
    return { ok: true };
  };

  await assert.rejects(
    () => stageAndCommit(candidate, async () => { throw new Error("HTTP 404"); }, commit),
    /HTTP 404/,
  );
  await assert.rejects(
    () => stageAndCommit(candidate, async () => { throw new Error("sha256-mismatch"); }, commit),
    /sha256-mismatch/,
  );
  assert.equal(commits, 0);

  const terminalLoader = app.slice(
    app.indexOf("async function loadTerminalEventsV6"),
    app.indexOf("async function selectEventDate"),
  );
  assert.ok(terminalLoader.indexOf("fetchEventsV6Candidate") < terminalLoader.indexOf("stageAndCommitV6Candidate"));
  assert.match(terminalLoader, /v6HeadAsTerminalPayload/);
  assert.doesNotMatch(terminalLoader, /loadEventDayV6/);
  assert.doesNotMatch(terminalLoader, /loadEventsV6State/);
});

test("le compteur de nouveautés distingue un total exact d’une tête saturée", async () => {
  const app = await portalFile("assets/app.js");
  const summarize = extractFunction(app, "terminalUnseenSummary");
  const head = {
    events: [105, 104, 103, 102, 101].map((id) => ({ id })),
    cursor: { minId: 1, maxId: 999 },
    windowCursor: { minId: 101, maxId: 105 },
    counts: { totalEchoes: 200 },
    hasMore: true,
  };

  assert.deepEqual(summarize(head, 90, null), { count: 5, displayCount: "5+", saturated: true });
  assert.deepEqual(summarize(head, 90, 190), { count: 10, displayCount: "10", saturated: false });
  assert.deepEqual(summarize(head, 103, null), { count: 2, displayCount: "2", saturated: false });
  assert.deepEqual(summarize({ ...head, hasMore: undefined }, 90, null), { count: 5, displayCount: "5", saturated: false });
});

test("les exemples v6 distinguent le pointeur actif de la tête immuable", async () => {
  const [manifest, pointer, head, day, daily] = await Promise.all([
    portalFile("data/public-events-manifest-v6.example.json").then(JSON.parse),
    portalFile("data/public-events-head-v6.example.json").then(JSON.parse),
    portalFile("data/public-events-generation-head-v6.example.json").then(JSON.parse),
    portalFile("data/public-events-day-v6.example.json").then(JSON.parse),
    portalFile("data/public-daily-v6.example.json").then(JSON.parse),
  ]);
  const entry = manifest.days[0];

  assert.equal(pointer.baseGenerationId, manifest.generationId);
  assert.equal(pointer.manifest.path, `data/public-events-v6/${manifest.generationId}/manifest.json`);
  assert.equal(pointer.manifest.sha256.replace(/^sha256:/, ""), await portalSha256("data/public-events-manifest-v6.example.json"));
  assert.equal(pointer.head.path, manifest.head.path);
  assert.equal(pointer.head.sha256, manifest.head.sha256);
  assert.equal(head.baseGenerationId, manifest.generationId);
  assert.equal(head.verifiedEchoes.length, 2);
  assert.equal(head.counts.totalEchoes, 2);
  assert.equal(head.hasMore, false);
  assert.deepEqual(head.cursor, manifest.cursor);
  assert.deepEqual(head.windowCursor, { minId: 41, maxId: 42 });
  assert.equal(manifest.head.path, `data/public-events-v6/${manifest.generationId}/head.json`);
  assert.equal(manifest.head.sha256.replace(/^sha256:/, ""), await portalSha256("data/public-events-generation-head-v6.example.json"));
  assert.equal(day.generationId, entry.fragmentGenerationId);
  assert.equal(daily.generationId, entry.dailyGenerationId);
  assert.match(entry.sha256, /^[a-f0-9]{64}$/);
  assert.match(entry.dailySha256, /^[a-f0-9]{64}$/);
  assert.equal(entry.sha256, await portalSha256("data/public-events-day-v6.example.json"));
  assert.equal(entry.dailySha256, await portalSha256("data/public-daily-v6.example.json"));
  assert.equal(daily.digest.hourly.length, 24);
});

test("les parcours publics exposent les nouveaux contrôles accessibles", async () => {
  const [index, terminal, resume, carte, app, styles] = await Promise.all([
    portalFile("index.html"),
    portalFile("terminal.html"),
    portalFile("resume.html"),
    portalFile("carte.html"),
    portalFile("assets/app.js"),
    portalFile("assets/styles.css"),
  ]);

  assert.match(index, /id="home-latest-echoes"/);
  assert.match(index, /Les échos les plus récents/);
  assert.doesNotMatch(index, /derniers échos vérifiés/i);
  assert.match(index, /id="player-visibility-toggle"/);
  assert.match(index, /aria-modal="true"/);
  assert.match(index, /id="expedition-export"[^>]+data-player-export/);
  assert.doesNotMatch(terminal, /id="event-date"/);
  assert.doesNotMatch(terminal, /id="event-date-today"/);
  assert.doesNotMatch(terminal, /Journée/);
  assert.match(terminal, /id="event-unseen"/);
  assert.match(terminal, /aria-live="off"/);
  assert.match(resume, /id="daily-today"/);
  assert.match(carte, /id="map-activity-toggle"/);
  assert.match(carte, /id="map-storage-toggle"/);
  assert.match(carte, /id="map-alert-toggle"/);
  assert.match(carte, /id="map-companion-toggle"/);
  assert.match(app, /data-update-announcer/);
  assert.match(app, /source-freshness/);
  assert.match(app, /assets\/icons\/clock-3\.svg/);
  assert.match(app, /<span class="visually-hidden">Fraîcheur des données<\/span>/);
  assert.match(app, /role="tooltip"/);
  assert.doesNotMatch(app, /<\/ul>\s*<small>\$\{escapeHtml\(updatedText\)\}<\/small>/);
  assert.match(app, /registerPayloadDataUpdate\("catalog", manifest\)/);
  assert.match(app, /Rattaché à la guilde/);
  assert.doesNotMatch(app, /Attribution déduite/);
  assert.match(app, /settings: \{ label: "Règles du monde"/);
  assert.match(app, /presenceAvailable: false/);
  assert.doesNotMatch(app, /params\.get\("jour"\) \?\? saved\.day/);
  assert.doesNotMatch(app, /params\.set\("jour"/);
  assert.match(app, /CommonDropItem3D/);
  assert.match(app, /data\/public-catalogs-manifest\.json/);
  assert.match(app, /mixed-catalog-generation/);
  assert.match(app, /data-load-breeding/);
  assert.doesNotMatch(app, /profile-export-shortcut/);
  assert.doesNotMatch(app, /expeditionShortcuts\.addEventListener\("click"[\s\S]{0,220}\[data-player-export\]/);
  assert.match(app, /schema: "gaylemon-player-analysis"/);
  assert.match(app, /schemaVersion: 2/);
  assert.match(app, /objectKeys: "sorted-recursively"/);
  assert.match(app, /rawPublicFields/);
  assert.match(app, /globalMapPoiMeta/);
  assert.match(app, /dailyConsolidatedPalFinds/);
  assert.match(app, /data: \{/);
  assert.match(app, /player: cloneExportValue\(player\)/);
  assert.match(app, /activity: cloneExportValue\(activity\)/);
  assert.match(app, /sections: cloneExportValue\(player\?\.inventory \|\| \[\]\)/);
  assert.match(app, /relations: \{/);
  assert.match(app, /analysisGuide: \{/);
  assert.match(app, /function v6NavigableDates/);
  assert.match(app, /contentHash: `empty:\$\{dateKey\}`/);
  assert.match(app, /v6DateCanBeOpened/);
  assert.match(app, /const terminalV6EchoLimit = 6/);
  assert.match(app, /terminalHead: true/);
  assert.match(app, /async function loadFullTerminalEventsV6/);
  assert.match(app, /async function renderPagedTerminalEventsV6/);
  assert.match(app, /nouveaux échos depuis ta dernière visite/);
  assert.match(terminal, /event-pagination--top/);
  assert.match(styles, /site-header__players-tooltip[\s\S]*?max-height:\s*none;[\s\S]*?overflow:\s*visible;/);
  assert.match(styles, /site-header__players-tooltip ul[\s\S]*?grid-template-columns:\s*repeat\(2,/);
  assert.match(styles, /home-echoes__list[\s\S]*?gap:\s*10px;/);
  assert.match(styles, /home-echoes__list \.event-line,[\s\S]*?border:\s*1px solid[\s\S]*?border-radius:\s*18px;/);
  assert.match(styles, /global-poi-marker/);
  assert.match(styles, /daily-tangible-card\.is-active/);
});

test("l'accueil affiche les cinq échos réellement les plus récents", async () => {
  const app = await portalFile("assets/app.js");
  const renderer = app.slice(
    app.indexOf("function renderHomeLatestEchoes"),
    app.indexOf("function currentV6MaxCursor"),
  );

  assert.match(renderer, /payload\?\.events/);
  assert.match(renderer, /slice\(0, 5\)/);
  assert.doesNotMatch(renderer, /verifiedEchoes/);
  assert.doesNotMatch(renderer, /confidence\s*===\s*["']confirmed["']/);
  assert.doesNotMatch(renderer, /vérifié|confirmé/i);
  assert.match(renderer, /mis à jour/);
});

test("les événements compilés rendent explicitement leur fenêtre de cinq minutes", async () => {
  const app = await portalFile("assets/app.js");
  const minutes = extractFunction(app, "eventAggregationWindowMinutes");
  globalThis.eventAggregationWindowMinutes = minutes;
  try {
    const label = extractFunction(app, "eventAggregationWindowLabel");
    const headline = extractFunction(app, "eventAggregationHeadline");
    const groupedCraft = { type: "craft", details: { windowMinutes: 5 } };
    const groupedProduction = { type: "production", details: { windowMinutes: 5 } };
    assert.equal(minutes(groupedCraft), 5);
    assert.equal(label(groupedCraft), "5 min");
    assert.equal(headline(groupedCraft, "Fabrications compilées"), "Fabrications regroupées sur 5 min");
    assert.equal(headline(groupedProduction, "Stocks compilés"), "Productions regroupées sur 5 min");
    assert.equal(headline({ type: "boss", details: {} }, "Boss vaincu"), "Boss vaincu");
  } finally {
    delete globalThis.eventAggregationWindowMinutes;
  }
  assert.match(app, /event-line__window/);
  assert.match(app, /Activité regroupée sur \$\{windowMinutes\} min/);
  assert.match(app, /<time datetime="\$\{escapeHtml\(event\.occurredAt\)\}"><strong>\$\{escapeHtml\(timestamp\.time\)\}<\/strong><span>\$\{escapeHtml\(timestamp\.date\)\}<\/span><\/time>/);
});

test("la fraîcheur traduit les états publics sans effacer la dernière donnée utile", async () => {
  const app = await portalFile("assets/app.js");
  const state = extractFunction(app, "sourceHealthState");
  const statsRenderer = app.slice(app.indexOf("function renderStats"), app.indexOf("function playerInitials"));

  assert.equal(state("available", "current"), "available");
  assert.equal(state("documented-but-unavailable", "current"), "delayed");
  assert.equal(state("available", "stale"), "delayed");
  assert.equal(state("transient-error", "stale"), "error");
  assert.doesNotMatch(statsRenderer, /statsSnapshot = null/);
  assert.match(statsRenderer, /provenance\.sourceStatus/);
  assert.match(app, /source-freshness__value/);
});

test("les snapshots publics refusent les mélanges de générations", async () => {
  const app = await portalFile("assets/app.js");
  const generationId = extractFunction(app, "publicSaveGenerationId");
  globalThis.publicSaveGenerationId = generationId;
  try {
    const isValid = extractFunction(app, "saveGenerationIsValid");
    const current = { ok: true, generationId: "save-20260718-223618-aa4365e5f03e7599" };
    const previousBases = { ok: true, generationId: "save-generation-precedente", bases: [{ name: "Base précédente" }] };
    const previousDiagnostics = { ok: true, generationId: "save-generation-precedente", parse: { status: "ok" } };
    const previousFull = { ok: true, generationId: "save-generation-precedente", players: [{ name: "Aventurière" }] };
    assert.equal(generationId(current), current.generationId);
    assert.equal(generationId({ ok: true, generationId: "../../invalide" }), "");
    assert.equal(isValid(current, current.generationId), true);
    assert.equal(isValid(current, "save-autre-generation"), false);
    assert.equal(isValid({ ok: true }, current.generationId), false);

    globalThis.saveGenerationIsValid = isValid;
    globalThis.saveSnapshot = current;
    globalThis.activeSaveGenerationId = extractFunction(app, "activeSaveGenerationId");
    globalThis.basesSnapshot = previousBases;
    globalThis.saveDiagnosticsSnapshot = previousDiagnostics;
    globalThis.fullSaveSnapshot = previousFull;
    const currentBases = extractFunction(app, "currentBasesSnapshot");
    const currentDiagnostics = extractFunction(app, "currentSaveDiagnosticsSnapshot");
    const currentFull = extractFunction(app, "currentFullSaveSnapshot");
    assert.equal(currentBases(), null);
    assert.equal(currentDiagnostics(), null);
    assert.equal(currentFull(), null);
    assert.strictEqual(globalThis.basesSnapshot, previousBases);
    assert.strictEqual(globalThis.saveDiagnosticsSnapshot, previousDiagnostics);
    assert.strictEqual(globalThis.fullSaveSnapshot, previousFull);
  } finally {
    [
      "publicSaveGenerationId",
      "saveGenerationIsValid",
      "saveSnapshot",
      "activeSaveGenerationId",
      "basesSnapshot",
      "saveDiagnosticsSnapshot",
      "fullSaveSnapshot",
    ].forEach((name) => delete globalThis[name]);
  }

  const saveLoader = app.slice(app.indexOf("async function loadSaveSnapshot"), app.indexOf("async function loadSaveDiagnostics"));
  const diagnosticsLoader = app.slice(app.indexOf("async function loadSaveDiagnostics"), app.indexOf("async function loadBases"));
  const basesLoader = app.slice(app.indexOf("async function loadBases"), app.indexOf("function setupLazyBaseData"));
  const fullSnapshotLoader = app.slice(app.indexOf("async function ensureFullSaveSnapshot"), app.indexOf("function hydratePlayerCatalogData"));

  assert.doesNotMatch(saveLoader, /basesSnapshot = null/);
  assert.doesNotMatch(saveLoader, /saveDiagnosticsSnapshot = null/);
  assert.doesNotMatch(saveLoader, /fullSaveSnapshot = null/);
  assert.doesNotMatch(saveLoader, /playerSnapshotCache\.clear/);
  assert.match(diagnosticsLoader, /assertActiveSaveGeneration\(payload, "diagnostics", generationId\)/);
  assert.match(basesLoader, /assertActiveSaveGeneration\(payload, "bases", generationId\)/);
  assert.match(fullSnapshotLoader, /assertActiveSaveGeneration\(payload, "snapshot", generationId\)/);
  assert.match(fullSnapshotLoader, /assertActiveSaveGeneration\(payload, "player", revision\)/);
  assert.match(fullSnapshotLoader, /const promiseKey = `\$\{revision\}:\$\{slug\}`/);
  assert.match(app, /mixed-save-generation:\$\{source\}/);
  assert.match(app, /basesGenerationRequested \? loadBases\(true\)/);
  assert.match(app, /payload\?\.revision \|\| payload\?\.generationId \|\| payload\?\.updatedAt/);
});

test("la voie PowerShell conserve les mêmes états game-data que le collecteur principal", async () => {
  const script = await readFile(new URL("../../scripts/update-palworld-stats.ps1", import.meta.url), "utf8");

  assert.match(script, /function Test-GameDataUnsupportedError/);
  assert.match(script, /HTTP \(\?:400\|501\)/);
  assert.match(script, /gameDataStatus = "unsupported"/);
  assert.match(script, /gameDataStatus = "documented-but-unavailable"/);
  assert.match(script, /gameDataStatus = "transient-error"/);
});

test("toutes les pages chargent les ressources versionnées de la tranche", async () => {
  const pages = ["index.html", "terminal.html", "resume.html", "classements.html", "carte.html", "github.html"];
  for (const page of pages) {
    const html = await portalFile(page);
    assert.match(html, /styles\.css\?v=20260719\.2/);
    assert.match(html, /app\.js\?v=20260719\.2/);
  }
});
