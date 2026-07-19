const uptimeSummary = document.querySelector("#uptime-summary");
const uptimeBars = document.querySelector("#uptime-bars");
const playersList = document.querySelector("#players-list");
const headerPlayers = document.querySelector("#header-players");
const playersTooltip = document.querySelector("#players-tooltip");
const siteHeader = document.querySelector(".site-header");
const siteLastUpdated = document.querySelector("#site-last-updated");
const siteLastUpdatedFull = document.querySelector(".site-last-updated__full");
const siteLastUpdatedShort = document.querySelector(".site-last-updated__short");
const siteNavLinks = [...document.querySelectorAll("[data-section-link]")];
const nextUpdate = document.querySelector("#next-update");
const refreshProgress = document.querySelector("#refresh-progress");
const refreshStatus = document.querySelector(".site-header__refresh");
const saveState = document.querySelector("#save-state");
const saveSummary = document.querySelector("#save-summary");
const savePlayers = document.querySelector("#save-players");
const leaderboardDisclosure = document.querySelector("#classements");
const leaderboardSearch = document.querySelector("#leaderboard-search");
const leaderboardCategory = document.querySelector("#leaderboard-category");
const leaderboardPresence = document.querySelector("#leaderboard-presence");
const leaderboardResultCount = document.querySelector("#leaderboard-result-count");
const leaderboardPodium = document.querySelector("#leaderboard-podium");
const leaderboardHead = document.querySelector("#leaderboard-head");
const leaderboardBody = document.querySelector("#leaderboard-body");
const basesState = document.querySelector("#bases-state");
const baseGrid = document.querySelector("#base-grid");
const baseSearch = document.querySelector("#base-search");
const baseResultCount = document.querySelector("#base-result-count");
const stockTotal = document.querySelector("#stock-total");
const stockSearch = document.querySelector("#stock-search");
const stockCategory = document.querySelector("#stock-category");
const stockResultCount = document.querySelector("#stock-result-count");
const stockResults = document.querySelector("#stock-results");
const stockPagination = document.querySelector("#stock-pagination");
const stockSourceButtons = [...document.querySelectorAll("[data-stock-source]")];
const worldDataState = document.querySelector("#world-data-state");
const worldDataGrid = document.querySelector("#world-data-grid");
const eventsState = document.querySelector("#events-state");
const eventsDisclosure = document.querySelector("#evenements");
const eventSearch = document.querySelector("#event-search");
const eventTypeFilter = document.querySelector("#event-type-filter");
const eventPlayerFilter = document.querySelector("#event-player-filter");
const eventResultCount = document.querySelector("#event-result-count");
const eventStream = document.querySelector("#event-stream");
const eventPagination = document.querySelector("#event-pagination");
const eventControls = document.querySelector("#event-controls");
const eventSyncStatus = document.querySelector("#event-sync-status");
const eventDateNavigation = document.querySelector("#event-date-navigation");
const eventDateInput = document.querySelector("#event-date");
const eventDatePrevious = document.querySelector("#event-date-previous");
const eventDateNext = document.querySelector("#event-date-next");
const eventDateToday = document.querySelector("#event-date-today");
const eventUnseen = document.querySelector("#event-unseen");
const eventUnseenCount = document.querySelector("#event-unseen-count");
const homeLatestEchoes = document.querySelector("#home-latest-echoes");
const homeEchoesStatus = document.querySelector("#home-echoes-status");
const playerVisibilityToggle = document.querySelector("#player-visibility-toggle");
const dailyDateInput = document.querySelector("#daily-date");
const dailyPrevious = document.querySelector("#daily-previous");
const dailyNext = document.querySelector("#daily-next");
const dailyToday = document.querySelector("#daily-today");
const dailyStatus = document.querySelector("#daily-status");
const dailyUpdatedAt = document.querySelector("#daily-updated-at");
const dailyMetrics = document.querySelector("#daily-metrics");
const dailyBrief = document.querySelector("#daily-brief");
const dailyHourly = document.querySelector("#daily-hourly");
const dailyTypes = document.querySelector("#daily-types");
const dailyPlayers = document.querySelector("#daily-players");
const dailyHighlights = document.querySelector("#daily-highlights");
const globalPlayerMarkers = document.querySelector("#global-player-markers");
const globalPlayerLegend = document.querySelector("#global-player-legend");
const globalMapCaption = document.querySelector("#global-map-caption");
const globalMapLayout = document.querySelector(".archipelago-map-layout");
const globalMapFigure = document.querySelector(".archipelago-map");
const globalMapViewport = document.querySelector("#global-map-viewport");
const globalMapScene = document.querySelector("#global-map-scene");
const globalMapImage = globalMapScene?.querySelector("img[data-src]");
const globalMapZoom = document.querySelector("#global-map-zoom");
const mapPlayerToggle = document.querySelector("#map-player-toggle");
const mapBaseToggle = document.querySelector("#map-base-toggle");
const mapBaseCount = document.querySelector("#map-base-count");
const mapLegendToggle = document.querySelector("#map-legend-toggle");
const mapFullscreenToggle = document.querySelector("#map-fullscreen-toggle");
const mapDisclosure = document.querySelector("#carte");
const expeditionDialog = document.querySelector("#expedition-dialog");
const expeditionShell = document.querySelector(".expedition-dialog__shell");
const expeditionClose = document.querySelector("#expedition-close");
const expeditionBack = document.querySelector("#expedition-back");
const expeditionShare = document.querySelector("#expedition-share");
const expeditionPlayerName = document.querySelector("#expedition-player-name");
const expeditionPlayerGuild = document.querySelector("#expedition-player-guild");
const expeditionPlayerMeta = document.querySelector("#expedition-player-meta");
const expeditionPlayerUpdated = document.querySelector("#expedition-player-updated");
const expeditionPlayerEmblem = document.querySelector("#expedition-player-emblem");
const expeditionProfile = document.querySelector("#expedition-profile");
const expeditionPaldex = document.querySelector("#expedition-paldex");
const expeditionAllocations = document.querySelector("#expedition-allocations");
const expeditionShortcuts = document.querySelector("#expedition-shortcuts");
const expeditionPosition = document.querySelector("#expedition-position");
const expeditionPals = document.querySelector("#expedition-pals");
const expeditionInventory = document.querySelector("#expedition-inventory");
const palSearch = document.querySelector("#pal-search");
const palContainerFilter = document.querySelector("#pal-container-filter");
const palSort = document.querySelector("#pal-sort");
const palResultCount = document.querySelector("#pal-result-count");
const palCollectionOverview = document.querySelector("#pal-collection-overview");
const palLoadMore = document.querySelector("#pal-load-more");
const inventoryOverview = document.querySelector("#inventory-overview");
const inventoryEquipped = document.querySelector("#inventory-equipped");
const inventorySearch = document.querySelector("#inventory-search");
const inventorySectionFilter = document.querySelector("#inventory-section-filter");
const detailTabPaldex = document.querySelector("#detail-tab-paldex");
const detailTabPals = document.querySelector("#detail-tab-pals");
const detailTabInventory = document.querySelector("#detail-tab-inventory");
const detailTabBases = document.querySelector("#detail-tab-bases");
const backToTop = document.querySelector("#back-to-top");
const footerBackToTop = document.querySelector("#footer-back-to-top");
const contextTooltip = document.querySelector("#context-tooltip");
const siteFooter = document.querySelector(".site-footer");

const refreshEveryMs = 20000;
const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let nextRefreshAt = Date.now() + refreshEveryMs;
let refreshPending = false;
let refreshMessage = "";
let refreshMessageUntil = 0;
let refreshMessageState = "updated";
let clockTimer;
let saveSnapshot = null;
let saveIndexPromise = null;
let saveDiagnosticsSnapshot = null;
let statsSnapshot = null;
let headerPresencePlayers = [];
let headerPresenceMaxPlayers = null;
let headerPresenceUpdatedAt = "";
let nextPresenceTooltipRefreshAt = 0;
let fullSaveSnapshot = null;
let fullSaveSnapshotPromise = null;
let fullSaveSnapshotPromiseGenerationId = "";
let publicCatalogManifest = null;
let publicCatalogManifestPromise = null;
const publicCatalogCache = new Map();
const catalogHydratedPlayers = new WeakSet();
const playerSnapshotCache = new Map();
const playerSnapshotPromises = new Map();
const renderedPlayerTabs = new Set();
let basesSnapshot = null;
let basesGenerationRequested = false;
let selectedPlayerBases = [];
let selectedPlayerStock = [];
let stockSource = "all";
let stockCurrentPage = 1;
const stockPageSize = 24;
const mapRouteIsDedicated = document.body.classList.contains("map-view");
let showMapPlayers = true;
let showMapBases = mapRouteIsDedicated;
let showMapLegend = true;
let mapExpandedFallback = false;
let selectedPlayer = null;
let selectedPlayerSnapshotPayload = null;
let palVisibleLimit = 24;
let paldexCurrentPage = 1;
let paldexStatusFilter = "all";
let selectedPaldexKey = "";
const paldexPageSize = 30;
let playerActivityByName = new Map();
let eventsSnapshot = null;
let eventsIndexSnapshot = null;
let eventsRecentSnapshot = null;
let eventsManifestV6 = null;
let eventsHeadV6 = null;
let eventsActivePointerV6 = null;
let eventsContractMode = "v5";
let eventsPreferredContract = "v5";
let eventsContractChannelCheckedAt = 0;
let eventsContractChannelPromise = null;
let eventsV6LoadPromise = null;
let eventsV6RetryAfter = 0;
let eventSelectedDateKey = "";
let eventCursor = "";
let terminalVisibleEvents = [];
let terminalEventWindowStart = 0;
let terminalVisitStartCursor = null;
let terminalVisitStartTotalEchoes = null;
let eventCurrentPage = 1;
let eventsFullLoaded = false;
let eventsV6FullLoadPromise = null;
let lastEventRecentRefreshAt = 0;
const dashboardEventPageSize = 5;
const terminalV6EchoLimit = 6;
let terminalEventPageSize = 8;
let terminalUnseenHideTimer = 0;
const terminalUnseenToastMs = 5200;
let dailySelectedDateKey = "";
let dailyAvailableDateKeys = [];
let dailyRosterPlayers = [];
let dailyStatsPlayers = [];
let dailyStatsUpdatedAt = "";
let dailyLastSignature = "";
let dailyRenderedGenerationId = "";
let dailyCurrentSummary = null;
let dailyHighlightTypeFilter = "";
const siteTimeZone = "America/Toronto";
const eventExportPageSizeFallback = 250;
const eventPageCache = new Map();
const eventPagePromises = new Map();
const eventDayCache = new Map();
const dailyV6Cache = new Map();
let eventsFullLoadPromise = null;
let leaderboardSortKey = "level";
let leaderboardSortDirection = "desc";
let backgroundScrollY = 0;
let playerViewLocked = false;
let playerReturnUrl = "";
let playerDialogReturnFocus = null;
let showInactivePlayers = false;
let lastTrackedLocation = "";
let navUpdatePending = false;
const sourceUpdatedAt = new Map();
const sourceHealth = new Map();
const dataRevisions = {
  metrics: "",
  stats: "",
  uptime: "",
  save: "",
  bases: "",
  diagnostics: "",
  events: "",
  eventsIndex: "",
  eventsManifestV6: "",
  eventsHeadV6: "",
};

const terminalVisitCursorStorageKey = "gaylemon:terminal:last-cursor";
const terminalVisitTotalStorageKey = "gaylemon:terminal:last-total-echoes";
const inactivePlayerBreakpoint = 4;
const recentPlayerWindowMs = 7 * 24 * 60 * 60 * 1000;

const globalMapView = {
  minScale: 1,
  maxScale: 4,
  scale: 1,
  x: 0,
  y: 0,
  pointers: new Map(),
  gesture: null,
  restored: false,
  saveTimer: null,
};

const globalMapViewStorageKey = "gaylemon:map-view";
const gameAssetVersion = "20260712.1";
const worldDiagnosticRefreshIntervalHours = 2;
const worldDiagnosticRefreshAnchorHour = 1;
const worldDiagnosticRefreshWindowMinutes = 15;
const worldDiagnosticWarningMs = 3 * 60 * 60 * 1000;
const worldDiagnosticStaleMs = 6 * 60 * 60 * 1000;

const dataUpdateAnnouncer = document.createElement("p");
dataUpdateAnnouncer.className = "visually-hidden";
dataUpdateAnnouncer.id = "data-update-announcer";
dataUpdateAnnouncer.setAttribute("role", "status");
dataUpdateAnnouncer.setAttribute("aria-live", "polite");
dataUpdateAnnouncer.setAttribute("aria-atomic", "true");
document.body.appendChild(dataUpdateAnnouncer);
nextUpdate?.setAttribute("aria-live", "off");

const sourceFreshnessLabels = {
  metrics: "Serveur",
  uptime: "Disponibilité",
  stats: "Présences",
  save: "Sauvegarde",
  bases: "Bases",
  diagnostics: "Analyse",
  events: "Échos",
  catalog: "Catalogues",
};
let sourceFreshnessDetails = null;

function ensureSourceFreshnessDetails() {
  if (sourceFreshnessDetails || !siteLastUpdated?.parentElement) return sourceFreshnessDetails;
  sourceFreshnessDetails = document.createElement("details");
  sourceFreshnessDetails.className = "source-freshness";
  sourceFreshnessDetails.innerHTML = `
    <summary aria-label="Afficher la fraîcheur des données" aria-controls="source-freshness-panel" aria-expanded="false">
      <img src="/assets/icons/clock-3.svg?v=20260718.1" alt="" width="24" height="24">
      <span class="visually-hidden">Fraîcheur des données</span>
    </summary>
    <span class="source-freshness__panel" id="source-freshness-panel" role="tooltip">
      <span class="source-freshness__panel-kicker">Sources du portail</span>
      <strong>Fraîcheur des données</strong>
      <span data-source-freshness-list><small>Aucune source reçue</small></span>
    </span>`;
  const summary = sourceFreshnessDetails.querySelector("summary");
  let closeTimer = null;
  const openFreshness = () => {
    window.clearTimeout(closeTimer);
    sourceFreshnessDetails.open = true;
    summary?.setAttribute("aria-expanded", "true");
  };
  const closeFreshness = () => {
    window.clearTimeout(closeTimer);
    sourceFreshnessDetails.open = false;
    summary?.setAttribute("aria-expanded", "false");
  };
  sourceFreshnessDetails.addEventListener("toggle", () => {
    summary?.setAttribute("aria-expanded", sourceFreshnessDetails.open ? "true" : "false");
  });
  sourceFreshnessDetails.addEventListener("pointerenter", openFreshness);
  sourceFreshnessDetails.addEventListener("pointerleave", () => {
    closeTimer = window.setTimeout(closeFreshness, 90);
  });
  summary?.addEventListener("focus", openFreshness);
  sourceFreshnessDetails.addEventListener("focusout", (event) => {
    if (!sourceFreshnessDetails.contains(event.relatedTarget)) closeFreshness();
  });
  summary?.addEventListener("click", (event) => {
    event.preventDefault();
    openFreshness();
  });
  document.addEventListener("pointerdown", (event) => {
    if (sourceFreshnessDetails?.open && !sourceFreshnessDetails.contains(event.target)) {
      closeFreshness();
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || !sourceFreshnessDetails?.open) return;
    closeFreshness();
    summary?.focus({ preventScroll: true });
  });
  siteLastUpdated.parentElement.insertAdjacentElement("afterend", sourceFreshnessDetails);
  return sourceFreshnessDetails;
}

function renderSourceFreshness() {
  const details = ensureSourceFreshnessDetails();
  const list = details?.querySelector("[data-source-freshness-list]");
  if (!list) return;
  const rows = [...new Set([...sourceUpdatedAt.keys(), ...sourceHealth.keys()])]
    .filter((source) => sourceFreshnessLabels[source])
    .sort((left, right) => left.localeCompare(right, "fr-CA"));
  const states = rows.map((source) => sourceHealth.get(source)?.state || "delayed");
  const overallState = states.includes("error") ? "error" : states.includes("delayed") ? "delayed" : "available";
  const overallLabel = overallState === "available" ? "à jour" : overallState === "error" ? "une source en erreur" : "une source à surveiller";
  details.dataset.state = overallState;
  details.querySelector("summary")?.setAttribute("aria-label", `Fraîcheur des données : ${overallLabel}`);
  list.innerHTML = rows.length
    ? rows.map((source) => {
      const date = sourceUpdatedAt.get(source);
      const health = sourceHealth.get(source) || { state: "delayed", label: "Retard", details: "" };
      const time = date
        ? `<time datetime="${escapeHtml(date.toISOString())}">${escapeHtml(formatRelativeAge(date))}</time>`
        : "<time>--</time>";
      const detailsText = health.details ? ` title="${escapeHtml(health.details)}"` : "";
      return `<span${detailsText}><b>${escapeHtml(sourceFreshnessLabels[source])}</b><span class="source-freshness__value">${time}<em data-state="${escapeHtml(health.state)}">${escapeHtml(health.label)}</em></span></span>`;
    }).join("")
    : "<small>Aucune source reçue</small>";
}

function sourceHealthState(status, freshness = "") {
  const normalizedStatus = String(status || "").trim().toLocaleLowerCase("fr-CA");
  const normalizedFreshness = String(freshness || "").trim().toLocaleLowerCase("fr-CA");
  if (["transient-error", "error", "down", "unavailable"].includes(normalizedStatus)) return "error";
  if (normalizedFreshness === "stale" || ["stale", "unknown", "documented-but-unavailable", "unsupported"].includes(normalizedStatus)) return "delayed";
  if (["available", "current", "ok", "up"].includes(normalizedStatus)) return "available";
  return normalizedStatus ? "delayed" : "available";
}

function registerSourceHealth(source, status = "available", freshness = "current", details = "") {
  const state = sourceHealthState(status, freshness);
  sourceHealth.set(source, {
    state,
    label: state === "available" ? "Disponible" : state === "error" ? "Erreur" : "Retard",
    details: String(details || ""),
  });
  renderSourceFreshness();
}

function registerPayloadDataUpdate(source, payload) {
  const provenance = payload?.provenance || {};
  registerDataUpdate(
    source,
    provenance.sourceUpdatedAt || payload?.sourceUpdatedAt || payload?.updatedAt,
    provenance.sourceStatus || payload?.sourceStatus || (payload?.ok === false ? "transient-error" : "available"),
    provenance.freshness || payload?.freshness || (payload?.ok === false ? "stale" : "current"),
  );
}

function announceDataUpdate(message) {
  if (!message || !dataUpdateAnnouncer) return;
  dataUpdateAnnouncer.textContent = "";
  window.requestAnimationFrame(() => {
    dataUpdateAnnouncer.textContent = message;
  });
}

function routeMatches(slug) {
  const path = location.pathname.replace(/\/+$/, "") || "/";
  return path === `/${slug}` || path === `/${slug}.html`;
}

function isTerminalRoute() {
  return routeMatches("terminal");
}

function isDailyDigestRoute() {
  return routeMatches("resume");
}

function isMapRoute() {
  return routeMatches("carte");
}

function isLeaderboardRoute() {
  return routeMatches("classements");
}

function isGitHubRoute() {
  return routeMatches("github");
}

function isDashboardRoute() {
  return Boolean(document.getElementById("accueil") && savePlayers);
}

function isHeaderOnlyRoute() {
  return !isDashboardRoute() && !isTerminalRoute() && !isDailyDigestRoute() && !isMapRoute() && !isLeaderboardRoute();
}

function legacyHashRoute() {
  if (location.pathname !== "/") return "";
  if (["#terminal", "#evenements"].includes(location.hash)) return "/terminal";
  if (location.hash === "#classements") return "/classements";
  if (location.hash === "#carte") return "/carte";
  return "";
}

const legacyRoute = legacyHashRoute();
if (legacyRoute) {
  location.replace(legacyRoute);
}

function versionedGameAsset(path) {
  const value = String(path || "");
  if (!/^\/?assets\/game\//.test(value)) return value;
  return `${value}${value.includes("?") ? "&" : "?"}v=${gameAssetVersion}`;
}

function loadDeferredImage(image) {
  if (image?.dataset.src && !image.currentSrc) {
    image.src = versionedGameAsset(image.dataset.src);
  }
}

function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}

function globalMapBounds() {
  const width = globalMapViewport.clientWidth;
  const height = globalMapViewport.clientHeight;
  return {
    width,
    height,
    minX: Math.min(0, width - width * globalMapView.scale),
    minY: Math.min(0, height - height * globalMapView.scale),
  };
}

function applyGlobalMapView() {
  const bounds = globalMapBounds();
  if (!bounds.width || !bounds.height) return;

  globalMapView.x = clamp(globalMapView.x, bounds.minX, 0);
  globalMapView.y = clamp(globalMapView.y, bounds.minY, 0);
  globalMapScene.style.transform = `translate3d(${globalMapView.x}px, ${globalMapView.y}px, 0) scale(${globalMapView.scale})`;
  globalMapScene.style.setProperty("--map-inverse-scale", String(1 / globalMapView.scale));
  globalMapZoom.value = `${Math.round(globalMapView.scale * 100)} %`;

  const zoomOut = document.querySelector('[data-map-action="zoom-out"]');
  const zoomIn = document.querySelector('[data-map-action="zoom-in"]');
  if (zoomOut) zoomOut.disabled = globalMapView.scale <= globalMapView.minScale;
  if (zoomIn) zoomIn.disabled = globalMapView.scale >= globalMapView.maxScale;
}

function saveGlobalMapView() {
  const bounds = globalMapBounds();
  if (!bounds.width || !bounds.height) return;
  const payload = {
    scale: globalMapView.scale,
    centerX: (bounds.width / 2 - globalMapView.x) / (bounds.width * globalMapView.scale),
    centerY: (bounds.height / 2 - globalMapView.y) / (bounds.height * globalMapView.scale),
  };
  try {
    sessionStorage.setItem(globalMapViewStorageKey, JSON.stringify(payload));
  } catch {
    // The map stays interactive when session storage is unavailable.
  }
}

function scheduleGlobalMapViewSave() {
  window.clearTimeout(globalMapView.saveTimer);
  globalMapView.saveTimer = window.setTimeout(saveGlobalMapView, 120);
}

function restoreGlobalMapView() {
  if (globalMapView.restored || !globalMapViewport.clientWidth) return;
  globalMapView.restored = true;
  try {
    const saved = JSON.parse(sessionStorage.getItem(globalMapViewStorageKey) || "null");
    if (saved && Number.isFinite(saved.scale) && Number.isFinite(saved.centerX) && Number.isFinite(saved.centerY)) {
      const width = globalMapViewport.clientWidth;
      const height = globalMapViewport.clientHeight;
      globalMapView.scale = clamp(saved.scale, globalMapView.minScale, globalMapView.maxScale);
      globalMapView.x = width / 2 - saved.centerX * width * globalMapView.scale;
      globalMapView.y = height / 2 - saved.centerY * height * globalMapView.scale;
    }
  } catch {
    // Invalid stored state falls back to the full map.
  }
  applyGlobalMapView();
}

function setGlobalMapZoom(nextScale, clientX, clientY) {
  const rect = globalMapViewport.getBoundingClientRect();
  if (!rect.width || !rect.height) return;
  const scale = clamp(nextScale, globalMapView.minScale, globalMapView.maxScale);
  const anchorX = Number.isFinite(clientX) ? clientX - rect.left : rect.width / 2;
  const anchorY = Number.isFinite(clientY) ? clientY - rect.top : rect.height / 2;
  const contentX = (anchorX - globalMapView.x) / globalMapView.scale;
  const contentY = (anchorY - globalMapView.y) / globalMapView.scale;
  globalMapView.scale = scale;
  globalMapView.x = anchorX - contentX * scale;
  globalMapView.y = anchorY - contentY * scale;
  applyGlobalMapView();
  scheduleGlobalMapViewSave();
}

function resetGlobalMapView() {
  globalMapView.scale = 1;
  globalMapView.x = 0;
  globalMapView.y = 0;
  applyGlobalMapView();
  saveGlobalMapView();
}

function pointerDistance(first, second) {
  return Math.hypot(second.x - first.x, second.y - first.y);
}

function startGlobalMapGesture() {
  const points = [...globalMapView.pointers.values()];
  if (points.length >= 2) {
    const rect = globalMapViewport.getBoundingClientRect();
    const midpointX = (points[0].x + points[1].x) / 2 - rect.left;
    const midpointY = (points[0].y + points[1].y) / 2 - rect.top;
    globalMapView.gesture = {
      type: "pinch",
      distance: Math.max(1, pointerDistance(points[0], points[1])),
      scale: globalMapView.scale,
      contentX: (midpointX - globalMapView.x) / globalMapView.scale,
      contentY: (midpointY - globalMapView.y) / globalMapView.scale,
    };
    return;
  }
  if (points.length === 1) {
    globalMapView.gesture = {
      type: "pan",
      startX: points[0].x,
      startY: points[0].y,
      originX: globalMapView.x,
      originY: globalMapView.y,
    };
  }
}

function setupGlobalMapInteractions() {
  if (!globalMapViewport || !globalMapScene || !globalMapZoom) return;

  document.querySelectorAll("[data-map-action]").forEach((button) => {
    button.addEventListener("click", () => {
      if (button.dataset.mapAction === "zoom-in") setGlobalMapZoom(globalMapView.scale + .5);
      if (button.dataset.mapAction === "zoom-out") setGlobalMapZoom(globalMapView.scale - .5);
      if (button.dataset.mapAction === "reset") resetGlobalMapView();
      if (button.dataset.mapAction === "fullscreen") void toggleGlobalMapFullscreen();
    });
  });

  globalMapViewport.addEventListener("wheel", (event) => {
    event.preventDefault();
    const factor = event.deltaY < 0 ? 1.2 : 1 / 1.2;
    setGlobalMapZoom(globalMapView.scale * factor, event.clientX, event.clientY);
  }, { passive: false });

  globalMapViewport.addEventListener("pointerdown", (event) => {
    if (event.pointerType === "mouse" && event.button !== 0) return;
    globalMapViewport.setPointerCapture(event.pointerId);
    globalMapView.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    globalMapViewport.classList.add("is-panning");
    startGlobalMapGesture();
  });

  globalMapViewport.addEventListener("pointermove", (event) => {
    if (!globalMapView.pointers.has(event.pointerId)) return;
    globalMapView.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
    const points = [...globalMapView.pointers.values()];
    if (points.length >= 2 && globalMapView.gesture?.type === "pinch") {
      const rect = globalMapViewport.getBoundingClientRect();
      const midpointX = (points[0].x + points[1].x) / 2 - rect.left;
      const midpointY = (points[0].y + points[1].y) / 2 - rect.top;
      globalMapView.scale = clamp(
        globalMapView.gesture.scale * pointerDistance(points[0], points[1]) / globalMapView.gesture.distance,
        globalMapView.minScale,
        globalMapView.maxScale,
      );
      globalMapView.x = midpointX - globalMapView.gesture.contentX * globalMapView.scale;
      globalMapView.y = midpointY - globalMapView.gesture.contentY * globalMapView.scale;
      applyGlobalMapView();
      return;
    }
    if (points.length === 1 && globalMapView.gesture?.type === "pan") {
      globalMapView.x = globalMapView.gesture.originX + points[0].x - globalMapView.gesture.startX;
      globalMapView.y = globalMapView.gesture.originY + points[0].y - globalMapView.gesture.startY;
      applyGlobalMapView();
    }
  });

  const endPointerGesture = (event) => {
    globalMapView.pointers.delete(event.pointerId);
    if (globalMapView.pointers.size) {
      startGlobalMapGesture();
    } else {
      globalMapView.gesture = null;
      globalMapViewport.classList.remove("is-panning");
      saveGlobalMapView();
    }
  };
  globalMapViewport.addEventListener("pointerup", endPointerGesture);
  globalMapViewport.addEventListener("pointercancel", endPointerGesture);

  globalMapViewport.addEventListener("keydown", (event) => {
    const panStep = 44;
    if (["+", "="].includes(event.key)) setGlobalMapZoom(globalMapView.scale + .5);
    else if (["-", "_"].includes(event.key)) setGlobalMapZoom(globalMapView.scale - .5);
    else if (event.key === "0") resetGlobalMapView();
    else if (event.key === "ArrowLeft") globalMapView.x += panStep;
    else if (event.key === "ArrowRight") globalMapView.x -= panStep;
    else if (event.key === "ArrowUp") globalMapView.y += panStep;
    else if (event.key === "ArrowDown") globalMapView.y -= panStep;
    else return;
    event.preventDefault();
    applyGlobalMapView();
    scheduleGlobalMapViewSave();
  });

  const revealGlobalMap = () => {
    loadDeferredImage(globalMapImage);
    window.requestAnimationFrame(restoreGlobalMapView);
  };
  if ("IntersectionObserver" in window) {
    const mapObserver = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      revealGlobalMap();
      mapObserver.disconnect();
    }, { rootMargin: "150px 0px" });
    mapObserver.observe(globalMapViewport);
  } else {
    revealGlobalMap();
  }

  if ("ResizeObserver" in window) {
    new ResizeObserver(() => applyGlobalMapView()).observe(globalMapViewport);
  } else {
    window.addEventListener("resize", applyGlobalMapView);
  }
}

setupGlobalMapInteractions();

async function toggleGlobalMapFullscreen() {
  if (!globalMapFigure) return;
  try {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
      mapExpandedFallback = false;
    } else if (globalMapFigure.requestFullscreen) {
      await globalMapFigure.requestFullscreen();
      mapExpandedFallback = false;
    } else {
      mapExpandedFallback = !mapExpandedFallback;
    }
  } catch {
    mapExpandedFallback = !mapExpandedFallback;
  }
  window.requestAnimationFrame(() => {
    applyGlobalMapView();
    syncGlobalMapControls();
  });
}

document.addEventListener("fullscreenchange", () => {
  syncGlobalMapControls();
  window.requestAnimationFrame(applyGlobalMapView);
});

function currentDocumentTitle() {
  if (isTerminalRoute()) {
    return "Terminal des échos | Gaylémon Palworld";
  }
  if (isDailyDigestRoute()) {
    return "Résumé quotidien | Gaylémon Palworld";
  }
  if (isGitHubRoute()) {
    return "Dépôt, Ops et pipeline | Gaylémon Palworld";
  }
  if (selectedPlayer && location.hash.startsWith("#joueur/")) {
    const tab = location.hash.match(/\/(profile|paldex|pals|inventory|bases)$/)?.[1] || "profile";
    const section = tab === "paldex"
      ? "Paldex personnel"
      : tab === "pals"
        ? "Collection de Pals"
      : tab === "inventory"
        ? "Inventaire"
        : tab === "bases"
          ? "Bases et campements"
          : "Progression et statistiques";
    return `${selectedPlayer.name} | ${section} | Gaylémon Palworld`;
  }
  if (location.hash === "#chroniques") {
    return "Progression et chroniques des aventuriers | Gaylémon Palworld";
  }
  if (location.hash === "#classements") {
    return "Classements des aventuriers | Gaylémon Palworld";
  }
  return "Gaylémon Palworld | Progression, statistiques et serveur";
}

function currentDocumentDescription() {
  if (isTerminalRoute()) {
    return "Le terminal complet des échos, productions, constructions, captures, recherches et aventures du serveur Gaylémon Palworld.";
  }
  if (isDailyDigestRoute()) {
    return "Résumé quotidien des grandes lignes du serveur Gaylémon: captures, productions, fabrications, niveaux, découvertes et faits marquants par joueur.";
  }
  if (isGitHubRoute()) {
    return "Structure technique de Gaylémon: Gaylemon Ops, scripts Windows, services Ubuntu, projections JSON publiques, validation et limites de publication.";
  }
  if (!selectedPlayer) {
    return "État du serveur, classements des joueurs, statistiques, progression, carte de Palpagos, bases et collections de Pals.";
  }
  if (selectedPlayer.provisional) {
    return `${selectedPlayer.name} vient d'être détecté sur Gaylémon Palworld. Sa progression apparaîtra après la première sauvegarde de son personnage.`;
  }
  const level = Number(selectedPlayer.level || 0);
  const palCount = Number(selectedPlayer.pals?.total || 0);
  const baseCount = selectedPlayer.guildBases != null ? Number(selectedPlayer.guildBases) : null;
  const campLevel = selectedPlayer.campLevel != null ? Number(selectedPlayer.campLevel) : null;
  const campSummary = baseCount != null && campLevel != null
    ? `, ${baseCount} base${baseCount > 1 ? "s" : ""} de guilde et camp niveau ${campLevel}`
    : "";
  return `Suis la progression de ${selectedPlayer.name}: niveau ${level}, ${palCount} Pals${campSummary}, statistiques et découvertes sur Palpagos.`;
}

function trackVirtualPageView() {
  if (location.hash.startsWith("#joueur/") && !selectedPlayer) return;
  document.title = currentDocumentTitle();
  const description = currentDocumentDescription();
  document.querySelector('meta[name="description"]')?.setAttribute("content", description);
  document.querySelector('meta[property="og:title"]')?.setAttribute("content", document.title);
  document.querySelector('meta[property="og:description"]')?.setAttribute("content", description);
  document.querySelector('meta[name="twitter:title"]')?.setAttribute("content", document.title);
  document.querySelector('meta[name="twitter:description"]')?.setAttribute("content", description);
  if (lastTrackedLocation === location.href || typeof window.gtag !== "function") return;
  lastTrackedLocation = location.href;
  window.gtag("event", "page_view", {
    page_title: document.title,
    page_location: location.href,
    page_path: `${location.pathname}${location.search}${location.hash}`,
  });
}

function trackCommunityLink(link) {
  if (typeof window.gtag !== "function") return;
  window.gtag("event", "community_link_click", {
    link_name: link.dataset.analyticsLink,
    link_location: link.dataset.analyticsLocation,
    link_url: link.href,
    transport_type: "beacon",
  });
}

function syncDisclosureLabel(disclosure) {
  const summary = disclosure.querySelector(":scope > summary");
  const label = summary?.querySelector(".disclosure__label");
  const isMap = disclosure.dataset.disclosureKey.startsWith("world-map");
  if (summary) summary.setAttribute("aria-expanded", String(disclosure.open));
  if (label) {
    label.textContent = disclosure.open
      ? (disclosure.dataset.openLabel || (isMap ? "Masquer la carte" : "Masquer"))
      : (disclosure.dataset.closedLabel || (isMap ? "Afficher la carte" : "Afficher"));
  }
}

document.querySelectorAll("[data-disclosure-key]").forEach((disclosure) => {
  const storageKey = `gaylemon:disclosure:${disclosure.dataset.disclosureKey}`;
  try {
    const savedState = localStorage.getItem(storageKey);
    if (savedState) disclosure.open = savedState === "open";
  } catch {
    // Local storage can be unavailable in hardened privacy modes.
  }
  syncDisclosureLabel(disclosure);
  disclosure.addEventListener("toggle", (event) => {
    syncDisclosureLabel(disclosure);
    try {
      localStorage.setItem(storageKey, disclosure.open ? "open" : "closed");
    } catch {
      // The disclosure remains functional even when persistence is blocked.
    }
    if (event.isTrusted && typeof window.gtag === "function") {
      window.gtag("event", "content_toggle", {
        content_name: disclosure.dataset.disclosureKey,
        content_state: disclosure.open ? "open" : "closed",
      });
    }
  });
});

function setMetric(name, value) {
  document.querySelectorAll(`[data-metric="${name}"]`).forEach((node) => {
    node.textContent = value;
  });
}

function setStat(name, value) {
  const node = document.querySelector(`[data-stat="${name}"]`);
  if (node) {
    node.textContent = value;
  }
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function escapeRegExp(value) {
  return String(value ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function formatTooltipText(value) {
  return String(value || "Aucune description disponible")
    .replace(/\+\{EffectValue1\}%/g, "bonus variable")
    .replace(/-\{EffectValue1\}%/g, "malus variable")
    .replace(/\{EffectValue1\}%/g, "effet variable")
    .replace(/\s*\n\s*/g, " · ");
}

function playerSlug(name) {
  return String(name || "joueur")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("fr-CA")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "") || "joueur";
}

function playerRoute(player, tab = "profile") {
  const route = `#joueur/${playerSlug(player?.name)}/${tab}`;
  return isDashboardRoute() ? route : `/${route}`;
}

function playerShareRoute(player, tab = "profile") {
  return `${location.origin}/joueur/${playerSlug(player?.name)}/${tab}/`;
}

function parseDate(value) {
  if (!value) {
    return null;
  }

  if (typeof value === "string") {
    const trimmed = value.trim();
    const slashDate = trimmed.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
    if (slashDate) {
      const first = Number(slashDate[1]);
      const second = Number(slashDate[2]);
      const month = first > 12 ? second : first;
      const day = first > 12 ? first : second;
      const date = new Date(
        Number(slashDate[3]),
        month - 1,
        day,
        Number(slashDate[4] || 0),
        Number(slashDate[5] || 0),
        Number(slashDate[6] || 0),
      );
      return Number.isNaN(date.getTime()) ? null : date;
    }
  }

  const normalized = typeof value === "string" && /^\d{4}-\d{2}-\d{2} /.test(value)
    ? value.replace(" ", "T")
    : value;
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatDateTime(value) {
  const date = parseDate(value);
  if (!date) {
    return value || "Jamais";
  }

  return date.toLocaleString("fr-CA", {
    dateStyle: "short",
    timeStyle: "medium",
    timeZone: siteTimeZone,
  });
}

function formatTime(value) {
  const date = parseDate(value);
  if (!date) return "--";
  return date.toLocaleTimeString("fr-CA", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: siteTimeZone,
  });
}

function scheduledDiagnosticSlot(now = new Date()) {
  const intervalMs = Math.max(1, worldDiagnosticRefreshIntervalHours) * 60 * 60 * 1000;
  const anchorHour = ((worldDiagnosticRefreshAnchorHour % 24) + 24) % 24;
  let slot = new Date(now.getFullYear(), now.getMonth(), now.getDate(), anchorHour, 0, 0, 0);
  while (slot > now) slot = new Date(slot.getTime() - intervalMs);
  while (slot.getTime() + intervalMs <= now.getTime()) slot = new Date(slot.getTime() + intervalMs);
  return slot;
}

function nextDiagnosticRefreshAt(updatedAtValue) {
  const now = new Date();
  const intervalMs = Math.max(1, worldDiagnosticRefreshIntervalHours) * 60 * 60 * 1000;
  const currentSlot = scheduledDiagnosticSlot(now);
  const updatedAt = parseDate(updatedAtValue);
  const windowMs = Math.max(1, worldDiagnosticRefreshWindowMinutes) * 60 * 1000;
  const slotCovered = updatedAt && updatedAt.getTime() >= currentSlot.getTime() - windowMs;
  if (!slotCovered && now.getTime() < currentSlot.getTime() + windowMs) {
    return currentSlot;
  }
  return new Date(currentSlot.getTime() + intervalMs);
}

function formatRelativeAge(value) {
  const date = parseDate(value);
  if (!date) return "--";
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
  if (seconds < 60) return "à l'instant";
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `il y a ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 48) return `il y a ${hours} h`;
  const days = Math.floor(hours / 24);
  return `il y a ${days} j`;
}

function registerDataUpdate(source, value, status = "available", freshness = "current", details = "") {
  const date = parseDate(value);
  registerSourceHealth(source, status, freshness, details);
  if (!date || !siteLastUpdated) return;
  sourceUpdatedAt.set(source, date);
  const latest = [...sourceUpdatedAt.values()].reduce(
    (current, candidate) => candidate > current ? candidate : current,
    date,
  );
  siteLastUpdated.dateTime = latest.toISOString();
  siteLastUpdatedShort.textContent = latest.toLocaleTimeString("fr-CA", {
    hour: "2-digit",
    minute: "2-digit",
  });
  siteLastUpdatedFull.textContent = latest.toLocaleString("fr-CA", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).replace(",", " ·");
  siteLastUpdated.dataset.tooltip = `Dernières données reçues le ${formatDateTime(latest)}`;
  renderSourceFreshness();
}

function latestDateValue(...values) {
  return values
    .map((value) => parseDate(value))
    .filter(Boolean)
    .sort((left, right) => right - left)[0] || null;
}

function updateActiveNavigation() {
  navUpdatePending = false;
  if (isTerminalRoute() || isDailyDigestRoute() || isMapRoute() || isLeaderboardRoute()) {
    const activeLink = isTerminalRoute()
      ? "terminal"
      : isDailyDigestRoute()
        ? "resume"
        : isMapRoute()
          ? "carte"
          : "classements";
    siteNavLinks.forEach((link) => {
      const isActive = link.dataset.sectionLink === activeLink;
      link.classList.toggle("is-active", isActive);
      if (isActive) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });
    return;
  }
  if (!isDashboardRoute()) {
    siteNavLinks.forEach((link) => {
      link.classList.remove("is-active");
      link.removeAttribute("aria-current");
    });
    return;
  }
  const marker = (siteHeader?.offsetHeight || 0) + 48;
  const sections = ["accueil", "chroniques", "classements", "carte", "evenements"]
    .map((id) => document.getElementById(id))
    .filter(Boolean);
  let active = sections[0]?.id || "accueil";
  for (const section of sections) {
    if (section.getBoundingClientRect().top <= marker) active = section.id;
  }
  siteNavLinks.forEach((link) => {
    const isActive = link.dataset.sectionLink === active;
    link.classList.toggle("is-active", isActive);
    if (isActive) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
}

function syncTerminalView(scrollToTop = false) {
  const active = isTerminalRoute();
  document.body.classList.toggle("terminal-view", active);
  if (active) {
    eventsDisclosure.open = true;
    if (eventsFullLoaded && eventsSnapshot) {
      renderEventFilters(eventsSnapshot.events || []);
      renderEvents();
    } else if (eventsIndexSnapshot) {
      renderEventFiltersFromFacets(eventsIndexSnapshot);
      void renderPagedTerminalEvents(false);
    } else if (eventsSnapshot) {
      renderEventFilters(eventsSnapshot.events || []);
      renderEvents();
    }
    if (scrollToTop) window.scrollTo({ top: 0, behavior: "auto" });
  } else if (eventsSnapshot && eventsDisclosure.open) {
    eventCurrentPage = 1;
    renderEvents();
  }
}

function scheduleActiveNavigationUpdate() {
  if (navUpdatePending) return;
  navUpdatePending = true;
  window.requestAnimationFrame(updateActiveNavigation);
}

function formatLastSeen(value) {
  const date = parseDate(value);
  if (!date) {
    return value || "Jamais";
  }

  return date.toLocaleString("fr-CA", {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatCompactDuration(seconds) {
  const total = Math.max(0, Number(seconds || 0));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);

  if (hours >= 24) {
    const days = Math.floor(hours / 24);
    return `${days}j ${hours % 24}h`;
  }

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }

  return `${minutes}m`;
}

function formatPresenceDurationSince(value, referenceDate = new Date()) {
  const date = parseDate(value);
  if (!date) return "depuis une durée inconnue";
  const total = Math.max(0, Math.floor((referenceDate.getTime() - date.getTime()) / 1000));
  if (total < 60) return "depuis moins d'une minute";

  const days = Math.floor(total / 86400);
  const hours = Math.floor((total % 86400) / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (days > 0) return `depuis ${days}j ${hours}h`;
  if (hours > 0) return `depuis ${hours}h ${minutes}m`;
  return `depuis ${minutes}m`;
}

function presenceStartedAt(player) {
  if (!player) return null;
  if (player.onlineSinceAt) return player.onlineSinceAt;
  if (player.currentSessionStartedAt) return player.currentSessionStartedAt;
  if (player.sessionStartedAt) return player.sessionStartedAt;
  const sessions = Array.isArray(player.sessionHistory) ? player.sessionHistory : [];
  const openSession = [...sessions].reverse().find((session) => session?.startedAt && !session?.endedAt);
  return openSession?.startedAt || null;
}

function normalizePlayerNameKey(value) {
  return String(value || "").trim().toLocaleLowerCase("fr-CA");
}

function mergeHeaderPresencePlayers() {
  const playersByName = new Map();
  const mergePlayer = (player) => {
    const name = String(player?.name || "").trim();
    const key = normalizePlayerNameKey(name);
    if (!key) return;
    const previous = playersByName.get(key) || {};
    playersByName.set(key, {
      ...previous,
      ...player,
      name: name || previous.name || "Joueur",
    });
  };

  headerPresencePlayers.forEach(mergePlayer);
  getPlayersCollection(statsSnapshot)
    .filter((player) => player?.isOnline)
    .forEach(mergePlayer);

  return [...playersByName.values()]
    .sort((first, second) => String(first.name || "").localeCompare(String(second.name || ""), "fr-CA"));
}

function renderHeaderPlayersTooltip() {
  if (!headerPlayers) return;

  const players = mergeHeaderPresencePlayers();
  const now = new Date();
  const count = players.length;
  const maxPlayers = headerPresenceMaxPlayers ?? "--";
  const accessibleLabel = count
    ? players.map((player) => {
      const startedAt = presenceStartedAt(player);
      const arrival = startedAt ? formatTime(startedAt) : "heure d'arrivée inconnue";
      return `${player.name || "Joueur"}, arrivée ${arrival}, ${formatPresenceDurationSince(startedAt, now)}`;
    }).join("; ")
    : "Aucun joueur connecté.";

  if (playersList) playersList.textContent = accessibleLabel;
  headerPlayers.dataset.state = count ? "online" : "empty";
  headerPlayers.setAttribute("aria-label", count
    ? `${count} joueur${count > 1 ? "s" : ""} actuellement en ligne`
    : "Aucun joueur actuellement en ligne");
  headerPlayers.removeAttribute("title");

  if (!playersTooltip) return;
  const updatedText = headerPresenceUpdatedAt ? `Données ${formatRelativeAge(headerPresenceUpdatedAt)}` : "Données en attente";
  if (!count) {
    playersTooltip.innerHTML = `
      <span class="site-header__players-tooltip-head">
        <span><span class="site-header__players-tooltip-kicker">Présences en direct</span><strong>Aucun joueur connecté</strong></span>
        <small>${escapeHtml(updatedText)}</small>
      </span>
      <p>Le serveur ne détecte personne en ligne pour le moment.</p>
    `;
    return;
  }

  playersTooltip.innerHTML = `
    <span class="site-header__players-tooltip-head">
      <span><span class="site-header__players-tooltip-kicker">Présences en direct</span><strong>${count}/${escapeHtml(maxPlayers)} en ligne</strong></span>
      <small>${escapeHtml(updatedText)}</small>
    </span>
    <ul>
      ${players.map((player) => {
    const startedAt = presenceStartedAt(player);
    const arrival = startedAt ? formatTime(startedAt) : "heure inconnue";
    const durationText = formatPresenceDurationSince(startedAt, now);
    return `
        <li style="--player-color:${escapeHtml(playerColor(player))}">
          <span class="site-header__players-tooltip-avatar">${escapeHtml(playerInitials(player.name))}</span>
          <span><b>${escapeHtml(player.name || "Joueur")}</b><small>Arrivée ${escapeHtml(arrival)} · ${escapeHtml(durationText)}</small></span>
        </li>`;
    }).join("")}
    </ul>
    `;
}

function formatPercent(value) {
  if (value == null || Number.isNaN(Number(value))) {
    return "--";
  }

  const number = Number(value);
  return `${number.toLocaleString("fr-CA", {
    minimumFractionDigits: number === 100 ? 0 : 2,
    maximumFractionDigits: 2,
  })} %`;
}

function formatProgressPercent(value) {
  if (value == null || Number.isNaN(Number(value))) return "--";
  return `${Number(value).toLocaleString("fr-CA", { maximumFractionDigits: 1 })} %`;
}

function formatBytes(value) {
  const bytes = Number(value);
  if (!Number.isFinite(bytes) || bytes < 0) return "--";
  if (bytes < 1024) return `${bytes.toLocaleString("fr-CA")} o`;
  const units = ["Kio", "Mio", "Gio"];
  let amount = bytes / 1024;
  let unit = units[0];
  for (let index = 1; index < units.length && amount >= 1024; index += 1) {
    amount /= 1024;
    unit = units[index];
  }
  return `${amount.toLocaleString("fr-CA", { maximumFractionDigits: amount >= 10 ? 1 : 2 })} ${unit}`;
}

function setWorldData(name, value) {
  setTextIfChanged(worldDataGrid?.querySelector(`[data-world-data="${name}"]`), value);
}

function setWorldDataNote(name, value) {
  setTextIfChanged(worldDataGrid?.querySelector(`[data-world-data-note="${name}"]`), value);
}

function setWorldDataQuality(name, state) {
  const card = worldDataGrid?.querySelector(`[data-world-data-card="${name}"]`);
  if (!card) return;
  if (state) card.dataset.quality = state;
  else delete card.dataset.quality;
}

function renderWorldContractStatus() {
  if (!worldDataGrid) return;
  const diagnostics = currentSaveDiagnosticsSnapshot();
  const bases = currentBasesSnapshot();
  const fullSnapshot = currentFullSaveSnapshot();
  const publicOutput = diagnostics?.publicOutput || {};
  const diagnosticEvents = diagnostics?.events || {};
  const eventContractReady = Boolean(
    Number(eventsHeadV6?.schemaVersion) === 6
    || Number(eventsManifestV6?.schemaVersion) === 6
    || Number(eventsActivePointerV6?.schemaVersion) === 6
    || eventsSnapshot?.version != null
    || diagnosticEvents.count
    || diagnosticEvents.updatedAt
  );
  const contracts = [
    { label: "diagnostic", ready: diagnostics?.version != null, value: diagnostics?.version != null ? `v${diagnostics.version}` : "" },
    { label: "index", ready: saveSnapshot?.version != null, value: saveSnapshot?.version != null ? `v${saveSnapshot.version}` : "" },
    { label: "snapshot", ready: Boolean(publicOutput.snapshotBytes || fullSnapshot?.version), value: publicOutput.snapshotBytes || fullSnapshot?.version ? "prêt" : "" },
    { label: "bases", ready: Boolean(publicOutput.basesBytes || bases?.version != null), value: publicOutput.basesBytes ? "prêt" : bases?.version != null ? `v${bases.version}` : "" },
    { label: "échos", ready: eventContractReady, value: eventContractReady ? (eventsManifestV6?.schemaVersion ? `v${eventsManifestV6.schemaVersion}` : "prêt") : "" },
  ];
  const loaded = contracts.filter((contract) => contract.ready);
  const coreReady = contracts.slice(0, 4).every((contract) => contract.ready);
  setWorldData("contracts", coreReady && eventContractReady ? "Prêtes" : coreReady ? "Échos en cours" : "Chargement");
  setWorldDataNote("contracts", loaded.length
    ? loaded.map((contract) => `${contract.label} ${contract.value}`.trim()).join(" · ")
    : "Les exports publics se chargent avec la page");
  setWorldDataQuality("contracts", coreReady ? "up" : "warning");
}

function formatParsingWarningsNote(parse) {
  const warningCount = Number(parse?.warnings || 0);
  if (!warningCount) return "Aucun avertissement non bloquant";

  const unknown = parse?.unknownStructures || {};
  const details = [
    [unknown.unknownBossFlags, "flags boss"],
    [unknown.unknownPalProperties, "champs Pal"],
    [unknown.unknownPalCaptureAssets, "captures"],
    [unknown.unknownAreas, "zones"],
    [unknown.unknownFastTravelPoints, "voyages rapides"],
    [unknown.unknownPalChallengeAssets, "défis capture"],
    [unknown.unknownPaldeckAssets, "Paldex"],
    [unknown.unknownTechnologies, "technologies"],
    [unknown.unresolvedBaseWorkers, "travailleurs"],
  ]
    .map(([value, label]) => [Number(value || 0), label])
    .filter(([value]) => value > 0)
    .map(([value, label]) => `${value.toLocaleString("fr-CA")} ${label}`);

  const base = `${warningCount.toLocaleString("fr-CA")} avertissement${warningCount > 1 ? "s" : ""} non bloquant${warningCount > 1 ? "s" : ""}`;
  return details.length ? `${base}: ${details.join(", ")}` : base;
}

function publicSaveGenerationId(payload) {
  const generationId = String(payload?.generationId || "");
  return /^[A-Za-z0-9._-]+$/.test(generationId) ? generationId : "";
}

function activeSaveGenerationId() {
  return publicSaveGenerationId(saveSnapshot);
}

function saveGenerationIsValid(payload, expectedGenerationId) {
  const generationId = publicSaveGenerationId(payload);
  return Boolean(payload?.ok && generationId && expectedGenerationId && generationId === String(expectedGenerationId));
}

function currentBasesSnapshot() {
  return saveGenerationIsValid(basesSnapshot, activeSaveGenerationId()) ? basesSnapshot : null;
}

function currentSaveDiagnosticsSnapshot() {
  return saveGenerationIsValid(saveDiagnosticsSnapshot, activeSaveGenerationId()) ? saveDiagnosticsSnapshot : null;
}

function currentFullSaveSnapshot() {
  return saveGenerationIsValid(fullSaveSnapshot, activeSaveGenerationId()) ? fullSaveSnapshot : null;
}

function assertActiveSaveGeneration(payload, source, expectedGenerationId = activeSaveGenerationId()) {
  if (
    !saveGenerationIsValid(payload, expectedGenerationId)
    || String(expectedGenerationId) !== activeSaveGenerationId()
  ) {
    throw new Error(`mixed-save-generation:${source}`);
  }
  return payload;
}

async function ensureActiveSaveGeneration() {
  if (saveIndexPromise) await saveIndexPromise;
  if (!activeSaveGenerationId()) await loadSaveSnapshot(true, false);
  const generationId = activeSaveGenerationId();
  if (!generationId) throw new Error("save-generation-unavailable");
  return generationId;
}

function renderSaveDiagnostics(payload) {
  if (!payload?.ok || !worldDataGrid) {
    registerPayloadDataUpdate("diagnostics", payload);
    return;
  }
  saveDiagnosticsSnapshot = payload;
  registerPayloadDataUpdate("diagnostics", payload);
  const save = payload.save || {};
  const parse = payload.parse || {};
  const output = payload.output || {};
  const publicOutput = payload.publicOutput || {};
  const assets = payload.assets || {};
  const footprint = payload.footprint || {};
  setWorldData("level", formatBytes(save.levelBytes));
  setWorldData("players", formatBytes(save.playersBytes));
  setWorldDataNote("players", `${Number(save.playerFiles || 0)} profils analysés`);
  setWorldData("generation", formatBytes(save.generationBytes));
  setWorldData("snapshot", formatBytes(publicOutput.snapshotBytes || output.snapshotBytes));
  setWorldData("bases", formatBytes(publicOutput.basesBytes || output.basesBytes));
  setWorldDataNote("bases", `${formatBytes(output.basesGzipBytes)} compressées · chargées dans la section Bases`);
  setWorldData("index", formatBytes(publicOutput.indexBytes));
  const updatedAt = parseDate(payload.updatedAt);
  const exportAgeMs = updatedAt ? Date.now() - updatedAt.getTime() : 0;
  const freshnessState = exportAgeMs > worldDiagnosticStaleMs ? "stale" : exportAgeMs > worldDiagnosticWarningMs ? "warning" : "up";
  setWorldData("freshness", formatRelativeAge(payload.updatedAt));
  setWorldDataNote("freshness-status", `Export du ${formatDateTime(payload.updatedAt)} · prochain passage ${formatTime(nextDiagnosticRefreshAt(payload.updatedAt))}`);
  setWorldDataQuality("freshness", freshnessState);
  const playersParsed = Number(parse.playersParsed || 0);
  const playerFiles = Number(save.playerFiles || playersParsed || 0);
  setWorldData("coverage", playerFiles ? `${playersParsed}/${playerFiles}` : "--");
  setWorldDataNote("coverage", `${Number(parse.palsParsed || 0).toLocaleString("fr-CA")} Pals · ${Number(parse.basesParsed || 0).toLocaleString("fr-CA")} bases`);
  setWorldDataQuality("coverage", playerFiles && playersParsed >= playerFiles ? "up" : "warning");
  const warningCount = Number(parse.warnings || 0);
  setWorldData("warnings", parse.status === "ok" ? "OK" : "À vérifier");
  setWorldDataNote("warnings", formatParsingWarningsNote(parse));
  setWorldDataQuality("warnings", parse.status === "ok" ? "up" : "warning");
  setWorldData("duration", parse.durationMs == null ? "--" : `${(Number(parse.durationMs) / 1000).toLocaleString("fr-CA", { maximumFractionDigits: 2 })} s`);
  const age = Number(save.backupAgeSeconds || 0);
  setWorldDataNote("freshness", age < 60 ? `Sauvegarde âgée de ${age} s lors de l'analyse` : `Sauvegarde âgée de ${Math.round(age / 60)} min lors de l'analyse`);
  setWorldData("map", `${Number(assets.worldMapWidth || 8192).toLocaleString("fr-CA")} × ${Number(assets.worldMapHeight || 8192).toLocaleString("fr-CA")}`);
  const fallbackFootprintBytes = [
    publicOutput.indexBytes,
    publicOutput.snapshotBytes || output.snapshotBytes,
    publicOutput.basesBytes || output.basesBytes,
    assets.worldMapBytes,
    assets.treeMapBytes,
  ].reduce((total, value) => total + (Number.isFinite(Number(value)) ? Number(value) : 0), 0);
  const footprintTotal = Number(footprint.totalBytes || fallbackFootprintBytes || 0);
  setWorldData("footprint", footprintTotal ? formatBytes(footprintTotal) : "--");
  setWorldDataNote("footprint", footprint.totalBytes
    ? `Données ${formatBytes(footprint.publicDataBytes)} · microsite ${formatBytes(footprint.micrositeBytes)} · assets ${formatBytes(footprint.assetsBytes)} · scripts ${formatBytes(footprint.scriptsBytes)} · serveur ${formatBytes(footprint.serverBytes)} · config ${formatBytes(footprint.dockerBytes)}`
    : `Données publiques et assets connus: ${formatBytes(fallbackFootprintBytes)}`);
  setWorldDataQuality("footprint", footprintTotal ? "up" : "warning");
  setWorldData("parser", String(payload.parser?.commit || "--").slice(0, 12));
  setWorldDataNote("parser", "PalworldSaveTools · catalogue synchronisé");
  const diagnosticEvents = payload.events || {};
  const eventTotal = Number(diagnosticEvents.count || 0);
  const lastEventAt = diagnosticEvents.lastAt || diagnosticEvents.updatedAt;
  if (eventTotal || diagnosticEvents.updatedAt || diagnosticEvents.lastAt) {
    setWorldData("events", eventTotal ? eventTotal.toLocaleString("fr-CA") : "--");
    setWorldDataNote("events", diagnosticEvents.firstAt && diagnosticEvents.lastAt
      ? `${formatDateTime(diagnosticEvents.firstAt)} → ${formatDateTime(diagnosticEvents.lastAt)}`
      : "Journal chargé");
    setWorldDataQuality("events", eventTotal ? "up" : "warning");
    setWorldData("last-event", formatRelativeAge(lastEventAt));
    setWorldDataNote("last-event", lastEventAt
      ? `${formatDateTime(lastEventAt)} · journal à jour ${formatRelativeAge(diagnosticEvents.updatedAt)}`
      : `Journal public · journal à jour ${formatRelativeAge(diagnosticEvents.updatedAt)}`);
    const lastEventDate = parseDate(lastEventAt);
    const feedUpdatedDate = parseDate(diagnosticEvents.updatedAt);
    const eventFreshnessDate = feedUpdatedDate || lastEventDate;
    const eventFreshnessAgeMs = eventFreshnessDate ? Date.now() - eventFreshnessDate.getTime() : Number.POSITIVE_INFINITY;
    setWorldDataQuality("last-event", eventFreshnessAgeMs > worldDiagnosticStaleMs ? "stale" : eventFreshnessAgeMs > worldDiagnosticWarningMs ? "warning" : "up");
  }
      worldDataState.textContent = parse.status === "ok" && freshnessState === "up" ? "Snapshot à jour" : parse.status === "ok" ? "Snapshot ancien" : "Analyse à surveiller";
  worldDataState.dataset.state = parse.status === "ok" && freshnessState === "up" ? "up" : "warning";
  renderWorldContractStatus();
}

function getPlayersCollection(payload) {
  if (Array.isArray(payload?.players)) {
    return payload.players;
  }

  return Object.values(payload?.players || {});
}

function createProvisionalPlayer(activity) {
  return {
    name: String(activity?.name || "Joueur").trim() || "Joueur",
    guild: activity?.guildName || "Aventurier indépendant",
    level: activity?.level != null && Number.isFinite(Number(activity.level)) ? Number(activity.level) : null,
    position: activity?.position || null,
    pals: { collection: [] },
    inventory: [],
    progress: {},
    character: {},
    provisional: true,
  };
}

function getDisplayPlayers(payload) {
  const savedPlayers = (Array.isArray(payload?.players) ? payload.players : [])
    .filter((player) => !player?.provisional);
  const playersBySlug = new Map(savedPlayers.map((player) => [playerSlug(player.name), player]));

  getPlayersCollection(statsSnapshot).forEach((activity) => {
    const slug = playerSlug(activity?.name);
    if (!activity?.isOnline || !slug || playersBySlug.has(slug)) return;
    playersBySlug.set(slug, createProvisionalPlayer(activity));
  });

  return [...playersBySlug.values()].sort((left, right) => {
    const leftActivity = getPlayerActivity(left);
    const rightActivity = getPlayerActivity(right);
    const leftDate = parseDate(leftActivity?.lastSeenAt || leftActivity?.lastOnlineAt)?.getTime() || 0;
    const rightDate = parseDate(rightActivity?.lastSeenAt || rightActivity?.lastOnlineAt)?.getTime() || 0;
    const leftGroup = leftActivity?.isOnline ? 0 : Date.now() - leftDate <= recentPlayerWindowMs ? 1 : 2;
    const rightGroup = rightActivity?.isOnline ? 0 : Date.now() - rightDate <= recentPlayerWindowMs ? 1 : 2;
    return leftGroup - rightGroup || rightDate - leftDate || String(left.name).localeCompare(String(right.name), "fr-CA");
  });
}

function playerIsInactiveForMobile(player, index) {
  const activity = getPlayerActivity(player);
  return index >= inactivePlayerBreakpoint && !activity?.isOnline;
}

function syncPlayerVisibilityToggle(hasInactivePlayers) {
  if (!savePlayers || !playerVisibilityToggle) return;
  savePlayers.classList.toggle("is-showing-inactive", showInactivePlayers);
  playerVisibilityToggle.hidden = !hasInactivePlayers;
  playerVisibilityToggle.setAttribute("aria-expanded", String(showInactivePlayers));
  playerVisibilityToggle.textContent = showInactivePlayers
    ? "Replier les aventuriers moins récents"
    : "Voir les aventuriers moins récents";
}

function getPlayerActivity(player) {
  return playerActivityByName.get(String(player?.name || "").toLocaleLowerCase("fr-CA")) || null;
}

function getPlayerActivityValues(player) {
  const activity = getPlayerActivity(player);
  return {
    activity,
    isOnline: Boolean(activity?.isOnline),
    presence: activity?.isOnline ? "En ligne" : "Dernière trace",
    sessions: activity ? String(Number(activity.sessionCount || 0)) : "--",
    playtime: activity ? (activity.totalOnline || formatCompactDuration(activity.totalOnlineSeconds)) : "--",
    lastSeen: activity?.isOnline ? "En ligne" : (activity ? formatLastSeen(activity.lastSeenAt || activity.lastOnlineAt) : "--"),
    lastSeenNote: activity?.isOnline ? "Présent actuellement" : "Dernière observation",
    ping: activity ? formatPing(activity.ping) : "--",
  };
}

const leaderboardCategories = {
  progression: {
    primary: "level",
    columns: [
      { key: "level", label: "Niveau", value: (player) => Number(player.level || 0) },
      { key: "technologies", label: "Technologies", value: (player) => Number(player.progress?.unlockedTechnologies || 0) },
      { key: "quests", label: "Quêtes", value: (player) => Number(player.progress?.completedQuests || 0) },
      { key: "camp", label: "Niveau du camp", value: (player) => Number(player.campLevel || 0) },
    ],
  },
  collection: {
    primary: "pals",
    columns: [
      { key: "pals", label: "Pals", value: (player) => Number(player.pals?.total || 0) },
      { key: "species", label: "Espèces", value: (player) => Number(player.pals?.uniqueSpecies || 0) },
      { key: "paldex", label: "Paldex", value: (player) => Number(player.progress?.paldex?.capturedSpecies || 0) },
      { key: "captures", label: "Captures", value: (player) => Number(player.progress?.paldex?.totalCaptures || 0) },
    ],
  },
  combat: {
    primary: "bosses",
    columns: [
      { key: "bosses", label: "Boss vaincus", value: (player) => Number(player.progress?.bosses?.defeated || 0) },
      { key: "towers", label: "Boss de tour", value: (player) => Number(player.progress?.bosses?.towerDefeated || 0) },
      { key: "palLevel", label: "Meilleur Pal", value: (player) => Number(player.pals?.highestLevel || 0) },
      { key: "level", label: "Niveau", value: (player) => Number(player.level || 0) },
    ],
  },
  exploration: {
    primary: "exploration",
    columns: [
      { key: "exploration", label: "Exploration", value: (player) => Number(player.progress?.exploration?.completionPercent || 0), format: (value) => formatProgressPercent(value) },
      { key: "travel", label: "Voyages rapides", value: (player) => Number(player.progress?.exploration?.fastTravelUnlocked || 0) },
      { key: "areas", label: "Zones découvertes", value: (player) => Number(player.progress?.exploration?.areasDiscovered || 0) },
      { key: "relics", label: "Rangs de reliques", value: (player) => Number(player.progress?.relics?.totalRanks || 0) },
    ],
  },
  activity: {
    primary: "playtime",
    columns: [
      { key: "playtime", label: "Temps joué", value: (player) => Number(getPlayerActivity(player)?.totalOnlineSeconds || 0), format: (value) => formatCompactDuration(value) },
      { key: "sessions", label: "Connexions", value: (player) => Number(getPlayerActivity(player)?.sessionCount || 0) },
      { key: "lastSeen", label: "Dernière vue", value: (player) => parseDate(getPlayerActivity(player)?.lastSeenAt || getPlayerActivity(player)?.lastOnlineAt)?.getTime() || 0, format: (_, player) => getPlayerActivity(player)?.isOnline ? "En ligne" : formatLastSeen(getPlayerActivity(player)?.lastSeenAt || getPlayerActivity(player)?.lastOnlineAt) },
      { key: "ping", label: "Dernier ping", value: (player) => Number(getPlayerActivity(player)?.ping || 0), format: (value) => formatPing(value) },
    ],
  },
};

function rankingColumn(category, key) {
  return leaderboardCategories[category]?.columns.find((column) => column.key === key);
}

function formatRankingValue(column, player) {
  const value = column.value(player);
  if (column.format) return column.format(value, player);
  return Number(value).toLocaleString("fr-CA");
}

function getRankedPlayers() {
  const category = leaderboardCategory?.value || "progression";
  const definition = leaderboardCategories[category] || leaderboardCategories.progression;
  const sortColumn = rankingColumn(category, leaderboardSortKey) || definition.columns[0];
  const query = normalizeEventSearch(String(leaderboardSearch?.value || "").trim());
  const presence = leaderboardPresence?.value || "all";
  const players = (Array.isArray(saveSnapshot?.players) ? saveSnapshot.players : [])
    .filter((player) => !player.provisional)
    .filter((player) => {
      const activity = getPlayerActivity(player);
      if (presence === "online" && !activity?.isOnline) return false;
      if (presence === "offline" && activity?.isOnline) return false;
      const searchable = normalizeEventSearch(`${player.name || ""} ${player.guild || ""}`);
      return !query || searchable.includes(query);
    });

  players.sort((first, second) => {
    const firstValue = sortColumn.value(first);
    const secondValue = sortColumn.value(second);
    const direction = leaderboardSortDirection === "asc" ? 1 : -1;
    return (firstValue - secondValue) * direction
      || String(first.name || "").localeCompare(String(second.name || ""), "fr-CA");
  });
  return { players, definition, sortColumn };
}

function renderLeaderboards() {
  if (!leaderboardBody || !leaderboardHead || !leaderboardPodium) return;
  const { players, definition, sortColumn } = getRankedPlayers();
  const sourcePlayers = (saveSnapshot?.players || []).filter((player) => !player.provisional);
  const podiumMetric = sortColumn;
  leaderboardResultCount.textContent = `${players.length} aventurier${players.length > 1 ? "s" : ""} sur ${sourcePlayers.length}`;

  leaderboardHead.innerHTML = `
    <tr>
      <th scope="col" class="leaderboard-rank-head">Rang</th>
      <th scope="col">Aventurier</th>
      ${definition.columns.map((column) => `
        <th scope="col" class="${column.key === sortColumn.key ? "is-sorted" : ""}">
          <button type="button" data-leaderboard-sort="${column.key}" aria-pressed="${column.key === sortColumn.key}">
            ${escapeHtml(column.label)}
            <span aria-hidden="true">${column.key === sortColumn.key ? (leaderboardSortDirection === "desc" ? "↓" : "↑") : "↕"}</span>
          </button>
        </th>
      `).join("")}
      <th scope="col"><span class="visually-hidden">Ouvrir la fiche</span></th>
    </tr>`;

  leaderboardPodium.innerHTML = players.length
    ? players.slice(0, 3).map((player, index) => {
      const playerIndex = saveSnapshot.players.indexOf(player);
      const activity = getPlayerActivity(player);
      return `
        <a class="leaderboard-podium-card leaderboard-podium-card--${index + 1}" href="${playerRoute(player)}" data-player-index="${playerIndex}" style="--player-color:${playerColor(player)}">
          <span class="leaderboard-podium-card__rank">#${index + 1}</span>
          <span class="leaderboard-podium-card__avatar">${escapeHtml(playerInitials(player.name))}</span>
          <span class="leaderboard-podium-card__identity"><strong>${escapeHtml(player.name)}</strong><small>${escapeHtml(player.guild || "Aventurier indépendant")}</small></span>
          <span class="leaderboard-podium-card__score"><strong>${escapeHtml(formatRankingValue(podiumMetric, player))}</strong><small>${escapeHtml(podiumMetric.label)}</small></span>
          <i class="${activity?.isOnline ? "is-online" : ""}" aria-label="${activity?.isOnline ? "En ligne" : "Hors ligne"}"></i>
        </a>`;
    }).join("")
    : '<p class="leaderboard-empty">Aucun aventurier ne correspond à ces filtres.</p>';

  leaderboardBody.innerHTML = players.length
    ? players.map((player, index) => {
      const playerIndex = saveSnapshot.players.indexOf(player);
      const activity = getPlayerActivity(player);
      return `
        <tr style="--player-color:${playerColor(player)}">
          <td class="leaderboard-rank"><strong>${index + 1}</strong></td>
          <th scope="row">
            <span class="leaderboard-player">
              <span class="leaderboard-player__avatar">${escapeHtml(playerInitials(player.name))}</span>
              <span><strong>${escapeHtml(player.name)}</strong><small>${escapeHtml(player.guild || "Aventurier indépendant")}</small></span>
              <i class="${activity?.isOnline ? "is-online" : ""}" data-tooltip="${activity?.isOnline ? "En ligne" : "Hors ligne"}"></i>
            </span>
          </th>
          ${definition.columns.map((column) => `<td${column.key === sortColumn.key ? ' class="is-sorted"' : ""}>${escapeHtml(formatRankingValue(column, player))}</td>`).join("")}
          <td><a class="leaderboard-open" href="${playerRoute(player)}" data-player-index="${playerIndex}" aria-label="Voir la fiche de ${escapeHtml(player.name)}">Voir</a></td>
        </tr>`;
    }).join("")
    : '<tr><td class="leaderboard-empty" colspan="7">Aucun aventurier ne correspond à ces filtres.</td></tr>';
}

function setTextIfChanged(node, value) {
  if (node && node.textContent !== value) node.textContent = value;
}

function formatPing(value) {
  const ping = Number(value);
  if (!Number.isFinite(ping)) return "--";
  return `${ping.toLocaleString("fr-CA", { maximumFractionDigits: 1 })} ms`;
}

function renderNextUpdate() {
  if (!nextUpdate) {
    return;
  }

  if (refreshPending) {
    nextUpdate.textContent = "Synchronisation...";
    if (refreshStatus) refreshStatus.dataset.state = "syncing";
    if (refreshProgress) refreshProgress.style.transform = "scaleX(1)";
    return;
  }

  if (refreshMessage && Date.now() < refreshMessageUntil) {
    nextUpdate.textContent = refreshMessage;
    if (refreshStatus) refreshStatus.dataset.state = refreshMessageState;
    if (refreshProgress) refreshProgress.style.transform = "scaleX(1)";
    return;
  }

  refreshMessage = "";
  if (refreshStatus) refreshStatus.dataset.state = "countdown";
  const remainingMs = Math.max(0, nextRefreshAt - Date.now());
  const totalSeconds = Math.ceil(remainingMs / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const ratio = Math.min(1, remainingMs / refreshEveryMs);

  const countdownLabel = `Dans ${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  if (nextUpdate.textContent !== countdownLabel) {
    nextUpdate.textContent = countdownLabel;
  }
  if (refreshProgress) {
    refreshProgress.style.transform = `scaleX(${ratio})`;
  }

  if (Date.now() >= nextPresenceTooltipRefreshAt) {
    nextPresenceTooltipRefreshAt = Date.now() + 30000;
    renderHeaderPlayersTooltip();
  }

  if (remainingMs === 0) void refreshDataInBackground();
}

function startRefreshClock() {
  window.clearInterval(clockTimer);
  clockTimer = window.setInterval(renderNextUpdate, 250);
}

function renderMetrics(payload) {
  if (!payload?.ok) {
    const message = payload?.error || "Les données du serveur ne sont pas encore disponibles.";
    headerPresencePlayers = [];
    headerPresenceUpdatedAt = payload?.updatedAt || "";
    if (playersList) playersList.textContent = message;
    if (headerPlayers) {
      headerPlayers.dataset.state = "empty";
      headerPlayers.removeAttribute("title");
    }
    if (playersTooltip) {
      playersTooltip.innerHTML = `
        <span class="site-header__players-tooltip-kicker">Présences en direct</span>
        <strong>Données indisponibles</strong>
        <p>${escapeHtml(message)}</p>
      `;
    }
    registerPayloadDataUpdate("metrics", payload);
    return;
  }

  const metrics = payload.metrics || {};
  setMetric("players-current", metrics.players ?? "--");
  setMetric("players-max", metrics.maxPlayers ?? "--");
  setMetric("capacity-label", `${metrics.maxPlayers ?? "--"} places`);
  setMetric("fps", metrics.fpsAverage != null ? `${metrics.fpsAverage} FPS` : `${metrics.fps ?? "--"} FPS`);
  setMetric("days", metrics.days ?? "--");
  setMetric("camps", metrics.baseCamps ?? "--");
  setMetric("uptime", metrics.uptime || "--");

  registerPayloadDataUpdate("metrics", payload);
  const players = Array.isArray(payload.players) ? payload.players : [];
  headerPresencePlayers = players;
  headerPresenceMaxPlayers = metrics.maxPlayers ?? null;
  headerPresenceUpdatedAt = payload.updatedAt || "";
  renderHeaderPlayersTooltip();
}

function renderUptime(payload) {
  if (!payload?.ok) {
    uptimeSummary.textContent = payload?.error || "La disponibilité sera affichée au prochain passage du collecteur.";
    uptimeBars.innerHTML = createPlaceholderBars();
    registerPayloadDataUpdate("uptime", payload);
    return;
  }

  const monitor = Array.isArray(payload.monitors) ? payload.monitors[0] : null;
  const summary = payload.summary || {};
  const status = monitor?.status || summary.status || "unknown";
  const uptime = monitor?.uptime24h ?? summary.uptime24hAverage;
  const ping = monitor?.ping;

  registerPayloadDataUpdate("uptime", payload);
  const pingText = ping != null ? ` · réponse ${ping} ms` : "";
  uptimeSummary.textContent = `${getStatusSentence(status)} · ${formatPercent(uptime)} de disponibilité sur 24 h${pingText}`;

  const beats = Array.isArray(monitor?.beats) ? monitor.beats : [];
  uptimeBars.innerHTML = beats.length
    ? beats.map((beat) => `<span class="uptime-segment uptime-segment--${escapeHtml(beat.status || "unknown")}" data-tooltip="${escapeHtml(formatDateTime(beat.time))}"></span>`).join("")
    : createPlaceholderBars();
}

function getStatusSentence(status) {
  switch (status) {
    case "up":
      return "L'aventure est ouverte";
    case "down":
      return "L'aventure fait une pause";
    case "maintenance":
      return "Une maintenance est en cours";
    case "pending":
  return "Chargement";
    default:
      return "Synchronisation en cours";
  }
}

function createPlaceholderBars() {
  return Array.from({ length: 24 }, () => '<span class="uptime-segment uptime-segment--unknown"></span>').join("");
}

function renderStats(payload) {
  const provenance = payload?.provenance || {};
  const sourceSummary = Object.entries(payload?.sources || {})
    .map(([source, value]) => {
      const state = sourceHealthState(value?.status);
      return `${source}: ${state === "available" ? "disponible" : state === "error" ? "erreur" : "retard"}`;
    })
    .join(" · ");
  registerDataUpdate(
    "stats",
    provenance.sourceUpdatedAt || payload?.updatedAt,
    provenance.sourceStatus || (payload?.ok ? "available" : "transient-error"),
    provenance.freshness || (payload?.ok ? "current" : "stale"),
    sourceSummary,
  );
  if (!payload?.ok) {
    return;
  }

  const players = getPlayersCollection(payload);
  const server = payload.server || {};
  statsSnapshot = payload;
  playerActivityByName = new Map(players.map((player) => [String(player.name || "").toLocaleLowerCase("fr-CA"), player]));
  const totalSessions = players.reduce((sum, player) => sum + Number(player.sessionCount || 0), 0);
  const totalPlaySeconds = players.reduce((sum, player) => sum + Number(player.totalOnlineSeconds || 0), 0);

  setStat("uniquePlayers", players.length);
  setStat("sessions", totalSessions);
  setStat("totalPlayTime", formatCompactDuration(totalPlaySeconds));
  setStat("peakPlayers", server.peakPlayers ?? "--");
  setStat("averagePlayers", server.averagePlayers ?? "--");
  setStat("observed", server.totalObserved || "0m");

  updateAdventurerActivity();
  updateGlobalPlayerActivity();
  renderHeaderPlayersTooltip();
  if (saveSnapshot) renderSaveSnapshot(saveSnapshot, false);
  if (selectedPlayer) {
    updateSelectedPlayerActivity();
    renderPlayerUpdatedAt(saveSnapshot?.updatedAt);
  }
}

function playerInitials(name) {
  const parts = String(name || "Joueur").split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  if (parts.length > 1) {
    return parts.slice(0, 2).map((part) => part[0]).join("").toLocaleUpperCase("fr-CA");
  }
  return (parts[0] || "J").slice(0, 2).toLocaleUpperCase("fr-CA");
}

const playerColorCache = new Map();
const assignedPlayerHues = [];

function hueDistance(first, second) {
  const distance = Math.abs(first - second) % 360;
  return Math.min(distance, 360 - distance);
}

function playerColor(playerOrName) {
  const name = typeof playerOrName === "string" ? playerOrName : playerOrName?.name;
  const value = playerSlug(name || "joueur");
  if (playerColorCache.has(value)) return playerColorCache.get(value);

  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  const initialHue = hash % 360;
  const minimumDistance = Math.max(14, 42 - assignedPlayerHues.length * 3);
  let hue = initialHue;
  let attempt = 0;
  while (assignedPlayerHues.some((assigned) => hueDistance(assigned, hue) < minimumDistance) && attempt < 720) {
    attempt += 1;
    hue = (initialHue + attempt * 137.508) % 360;
  }
  hue = Math.round(hue * 10) / 10;
  while (assignedPlayerHues.includes(hue)) hue = Math.round(((hue + .7) % 360) * 10) / 10;
  assignedPlayerHues.push(hue);
  const saturation = 56 + (hash % 9);
  const lightness = 43 + ((hash >>> 8) % 7);
  const color = `hsl(${hue} ${saturation}% ${lightness}%)`;
  playerColorCache.set(value, color);
  return color;
}

function basePlayerNames(base) {
  if (Array.isArray(base?.players) && base.players.length) {
    return [...new Set(base.players.map((name) => String(name || "").trim()).filter(Boolean))]
      .sort((first, second) => first.localeCompare(second, "fr-CA"));
  }
  const guild = String(base?.guild || "").toLocaleLowerCase("fr-CA");
  if (!guild || guild === "guilde anonyme") return [];
  return (Array.isArray(saveSnapshot?.players) ? saveSnapshot.players : [])
    .filter((player) => String(player.guild || "").toLocaleLowerCase("fr-CA") === guild)
    .map((player) => String(player.name || "").trim())
    .filter(Boolean)
    .sort((first, second) => first.localeCompare(second, "fr-CA"));
}

function basePlayerLabel(base, compact = false) {
  const names = basePlayerNames(base);
  if (!names.length) return "Aventurier non identifié";
  if (!compact || names.length === 1) return names.join(", ");
  return `${names[0]} +${names.length - 1}`;
}

function renderServerRealDays() {
  const output = document.querySelector("#server-real-days");
  if (!output) return;
  const officialStart = new Date("2026-07-10T00:00:00-04:00");
  const elapsedDays = Math.max(1, Math.floor((Date.now() - officialStart.getTime()) / 86400000) + 1);
  output.textContent = `${elapsedDays} jour${elapsedDays > 1 ? "s" : ""}`;
}

function isWorldMapPosition(position) {
  if (!position || !Number.isFinite(Number(position.mapX)) || !Number.isFinite(Number(position.mapY))) return false;
  if (position.mapVisible === false) return false;
  return !(Math.abs(Number(position.mapX)) > 550 && Math.abs(Number(position.mapY)) > 550);
}

function playerTeamPals(player) {
  const pals = player?.pals || {};
  const directTeam = [pals.team, pals.activeTeam, pals.partyPreview]
    .find((rows) => Array.isArray(rows) && rows.length);
  if (directTeam) return directTeam;
  const collection = Array.isArray(pals.collection) ? pals.collection : [];
  return collection.filter((pal) => pal.container === "party");
}

function syncGlobalMapControls() {
  globalMapLayout?.classList.toggle("is-legend-hidden", !showMapLegend);
  globalMapLayout?.classList.toggle("is-showing-bases", showMapBases);
  globalMapFigure?.classList.toggle("is-players-hidden", !showMapPlayers);
  const expanded = mapExpandedFallback || Boolean(document.fullscreenElement && document.fullscreenElement === globalMapFigure);
  globalMapFigure?.classList.toggle("is-map-expanded", expanded);
  if (mapPlayerToggle) {
    mapPlayerToggle.setAttribute("aria-pressed", String(showMapPlayers));
    mapPlayerToggle.classList.toggle("is-active", showMapPlayers);
    const label = mapPlayerToggle.querySelector("b");
    if (label) label.textContent = "Joueurs";
    mapPlayerToggle.dataset.tooltip = showMapPlayers ? "Masquer les joueurs" : "Afficher les joueurs";
  }
  if (mapLegendToggle) {
    mapLegendToggle.setAttribute("aria-pressed", String(showMapLegend));
    mapLegendToggle.classList.toggle("is-active", showMapLegend);
    const label = mapLegendToggle.querySelector("b");
    if (label) label.textContent = "Légende";
    mapLegendToggle.dataset.tooltip = showMapLegend ? "Masquer la légende" : "Afficher la légende";
  }
  if (mapFullscreenToggle) {
    mapFullscreenToggle.setAttribute("aria-pressed", String(expanded));
    mapFullscreenToggle.classList.toggle("is-active", expanded);
    mapFullscreenToggle.setAttribute("aria-label", expanded ? "Réduire la carte" : "Agrandir la carte");
    mapFullscreenToggle.dataset.tooltip = expanded ? "Réduire la carte" : "Agrandir la carte";
  }
}

function renderGlobalPlayerMap(players, bases = currentBasesSnapshot()?.bases || []) {
  if (!globalPlayerMarkers || !globalPlayerLegend || !globalMapCaption) return;
  const positioned = players
    .map((player, index) => ({ player, index }))
    .filter(({ player }) => isWorldMapPosition(player?.position)
      && Number.isFinite(Number(player.position.leftPercent))
      && Number.isFinite(Number(player.position.topPercent)));
  const uncharted = players
    .map((player, index) => ({ player, index }))
    .filter(({ player }) => player?.position && !isWorldMapPosition(player.position));
  const positionedBases = (Array.isArray(bases) ? bases : [])
    .filter((base) => base?.position && Number.isFinite(Number(base.position.leftPercent)) && Number.isFinite(Number(base.position.topPercent)));

  if (!positioned.length && !positionedBases.length && !uncharted.length) {
    globalPlayerMarkers.innerHTML = "";
    globalPlayerLegend.innerHTML = '<p class="save-empty">Aucune position connue pour l\'instant.</p>';
    globalMapCaption.textContent = "Les positions apparaîtront après une sauvegarde du monde.";
    syncGlobalMapControls();
    return;
  }

  const playerMarkers = showMapPlayers ? positioned.map(({ player, index }, markerIndex) => {
    const activity = playerActivityByName.get(String(player.name || "").toLocaleLowerCase("fr-CA"));
    const onlineClass = activity?.isOnline ? " is-online" : "";
    const color = playerColor(player);
    const position = player.position;
    return `
      <span class="global-player-marker${onlineClass}" role="img"
        data-player-slug="${playerSlug(player.name)}"
        style="left:${Number(position.leftPercent)}%;top:${Number(position.topPercent)}%;--marker-color:${color};--marker-order:${markerIndex}"
        aria-label="${escapeHtml(player.name)}, position X ${Number(position.mapX || 0)}, Y ${Number(position.mapY || 0)}">
        <i>${escapeHtml(playerInitials(player.name))}</i>
        <strong>${escapeHtml(player.name)}</strong>
      </span>
    `;
  }).join("") : "";
  const baseMarkers = showMapBases ? positionedBases.map((base, markerIndex) => {
    const playerNames = basePlayerNames(base);
    const ownerLabel = basePlayerLabel(base);
    const ownerPrefix = playerNames.length > 1 ? "Aventuriers" : "Aventurier";
    const player = (saveSnapshot?.players || []).find((row) => playerNames.includes(row.name));
    const target = player ? playerRoute(player, "bases") : "#chroniques";
    return `
      <a class="global-base-marker" href="${escapeHtml(target)}"
        style="left:${Number(base.position.leftPercent)}%;top:${Number(base.position.topPercent)}%;--marker-order:${positioned.length + markerIndex}"
        aria-label="${escapeHtml(base.name)}, ${escapeHtml(ownerPrefix.toLocaleLowerCase("fr-CA"))}: ${escapeHtml(ownerLabel)}">
        <i aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M4 10.4 12 4l8 6.4v9.1h-5.4v-5.7H9.4v5.7H4z"/></svg></i>
        <span class="global-base-marker__owner">${escapeHtml(basePlayerLabel(base, true))}</span>
        <strong><b>${escapeHtml(base.name)}</b><small>${escapeHtml(ownerPrefix)} : ${escapeHtml(ownerLabel)}</small></strong>
      </a>
    `;
  }).join("") : "";
  globalPlayerMarkers.innerHTML = playerMarkers + baseMarkers;

  const playerLegend = showMapPlayers ? positioned.map(({ player, index }) => {
    const activity = playerActivityByName.get(String(player.name || "").toLocaleLowerCase("fr-CA"));
    const isOnline = Boolean(activity?.isOnline);
    const color = playerColor(player);
    return `
      <a class="global-player-legend-row" href="${playerRoute(player)}" data-player-index="${index}" data-player-slug="${playerSlug(player.name)}" style="--marker-color:${color}">
        <span class="global-player-legend-row__marker">${escapeHtml(playerInitials(player.name))}</span>
        <span><strong>${escapeHtml(player.name)}</strong><small>Carte X ${Number(player.position.mapX || 0)}, Y ${Number(player.position.mapY || 0)}</small></span>
        <b class="${isOnline ? "is-online" : ""}">${isOnline ? "En ligne" : "Dernière position"}</b>
      </a>
    `;
  }).join("") : "";
  const unchartedLegend = showMapPlayers ? uncharted.map(({ player, index }) => {
    const activity = playerActivityByName.get(String(player.name || "").toLocaleLowerCase("fr-CA"));
    const isOnline = Boolean(activity?.isOnline);
    const color = playerColor(player);
    return `
      <a class="global-player-legend-row global-player-legend-row--uncharted" href="${playerRoute(player)}" data-player-index="${index}" data-player-slug="${playerSlug(player.name)}" style="--marker-color:${color}">
        <span class="global-player-legend-row__marker">${escapeHtml(playerInitials(player.name))}</span>
        <span><strong>${escapeHtml(player.name)}</strong><small>Zone non cartographiée · X ${Number(player.position.mapX || 0)}, Y ${Number(player.position.mapY || 0)}</small></span>
        <b class="${isOnline ? "is-online" : ""}">${isOnline ? "En ligne" : "Dernière position"}</b>
      </a>
    `;
  }).join("") : "";
  const baseLegend = showMapBases && positionedBases.length ? `
    <div class="global-base-legend">
      <strong>${positionedBases.length} base${positionedBases.length > 1 ? "s" : ""} cartographiée${positionedBases.length > 1 ? "s" : ""}</strong>
      <span>${[...new Set(positionedBases.map((base) => base.guild))].length} guildes établies sur l'archipel</span>
      <span>Ouvre la fiche d'un aventurier pour explorer ses campements.</span>
    </div>
  ` : "";
  globalPlayerLegend.innerHTML = showMapLegend ? playerLegend + unchartedLegend + baseLegend : "";
  const unchartedNote = uncharted.length
    ? ` · ${uncharted.length} en zone non cartographiée`
    : "";
  const playerPart = showMapPlayers
    ? `${positioned.length} aventurier${positioned.length > 1 ? "s" : ""}`
    : "Joueurs masqués";
  const basePart = showMapBases
    ? `${positionedBases.length} base${positionedBases.length > 1 ? "s" : ""}`
    : "bases masquées";
  globalMapCaption.textContent = `${playerPart} · ${basePart}` + (showMapPlayers ? unchartedNote : "");
  const visibleBaseCount = currentBasesSnapshot()
    ? positionedBases.length
    : Number(saveSnapshot?.summary?.bases || 0);
  if (mapBaseCount) mapBaseCount.textContent = visibleBaseCount;
  if (mapBaseToggle) {
    mapBaseToggle.setAttribute("aria-pressed", String(showMapBases));
    mapBaseToggle.classList.toggle("is-active", showMapBases);
    const label = mapBaseToggle.querySelector("b");
    if (label) label.textContent = "Bases";
    mapBaseToggle.dataset.tooltip = showMapBases ? "Masquer les bases de la carte" : "Afficher les bases sur la carte";
  }
  syncGlobalMapControls();
}

function updateGlobalPlayerActivity() {
  if (!saveSnapshot || !globalPlayerMarkers || !globalPlayerLegend) return;

  (saveSnapshot.players || []).forEach((player) => {
    const slug = playerSlug(player.name);
    const isOnline = Boolean(getPlayerActivity(player)?.isOnline);
    const marker = globalPlayerMarkers.querySelector(`[data-player-slug="${slug}"]`);
    const legend = globalPlayerLegend.querySelector(`[data-player-slug="${slug}"]`);
    const legendStatus = legend?.querySelector("b");

    marker?.classList.toggle("is-online", isOnline);
    legendStatus?.classList.toggle("is-online", isOnline);
    setTextIfChanged(legendStatus, isOnline ? "En ligne" : "Dernière position");
  });
}

function updateAdventurerActivity() {
  if (!saveSnapshot || !savePlayers) return;

  (saveSnapshot.players || []).forEach((player) => {
    const card = savePlayers.querySelector(`[data-player-slug="${playerSlug(player.name)}"]`);
    if (!card) return;
    const values = getPlayerActivityValues(player);
    setTextIfChanged(card.querySelector('[data-player-activity="sessions"]'), values.sessions);
    setTextIfChanged(card.querySelector('[data-player-activity="playtime"]'), values.playtime);
    setTextIfChanged(card.querySelector('[data-player-activity="lastSeen"]'), values.lastSeen);
    setTextIfChanged(card.querySelector('[data-player-activity="ping"]'), values.ping);
    const presence = card.querySelector("[data-player-presence]");
    presence?.classList.toggle("is-online", values.isOnline);
    setTextIfChanged(presence, values.presence);
  });
}

function renderSaveSnapshot(payload, syncRoute = true) {
  if (!payload?.ok) {
    if (saveState) saveState.textContent = "En attente";
    registerPayloadDataUpdate("save", payload);
    return;
  }

  const summary = payload.summary || {};
  const players = getDisplayPlayers(payload);
  saveSnapshot = { ...payload, players };
  if (saveState) saveState.textContent = "Données synchronisées";
  registerPayloadDataUpdate("save", payload);
  registerDataUpdate(
    "bases",
    payload?.provenance?.sourceUpdatedAt || payload?.updatedAt,
    payload?.provenance?.sourceStatus || (payload?.ok ? "available" : "transient-error"),
    payload?.provenance?.freshness || (payload?.ok ? "current" : "stale"),
    `${dailyPlural(Number(summary.bases || 0), "base indexée", "bases indexées")} dans la dernière sauvegarde publique.`,
  );
  renderWorldContractStatus();
  const summaryValues = {
    players: players.length,
    pals: Number(summary.pals || 0),
    guilds: Number(summary.guilds || 0),
    bases: Number(summary.bases || 0),
    levels: players.reduce((total, player) => total + Number(player.level || 0), 0),
    technologies: players.reduce((total, player) => total + Number(player.progress?.unlockedTechnologies || 0), 0),
  };
  if (saveSummary) {
    Object.entries(summaryValues).forEach(([key, value]) => {
      const element = saveSummary.querySelector(`[data-save-summary="${key}"]`);
      if (element) element.textContent = value.toLocaleString("fr-CA");
    });
  }
  renderGlobalPlayerMap(players);

  if (!players.length) {
    if (savePlayers) savePlayers.innerHTML = '<p class="save-empty">Aucun aventurier n\'a encore laissé sa marque dans les sauvegardes.</p>';
    syncPlayerVisibilityToggle(false);
    return;
  }

  if (savePlayers) savePlayers.innerHTML = players.map((player, index) => {
    const pals = player.pals || {};
    const activity = getPlayerActivityValues(player);
    const teamPals = playerTeamPals(player);
    const cardAccent = playerColor(player);
    const inactiveForMobile = playerIsInactiveForMobile(player, index);
    const visibilityClass = inactiveForMobile ? " adventurer-card--less-recent" : "";
    const visibilityAttribute = inactiveForMobile ? ' data-player-visibility="inactive"' : ' data-player-visibility="recent"';
    if (player.provisional) {
      const level = player.level == null ? "--" : Number(player.level);
      return `
        <article class="adventurer-card adventurer-card--provisional${visibilityClass}"${visibilityAttribute} data-player-slug="${playerSlug(player.name)}" style="--card-order: ${index};--card-accent:${cardAccent}">
          <div class="adventurer-card__cover">
            <div class="adventurer-card__identity">
              <span class="adventurer-card__monogram" aria-hidden="true">${escapeHtml(playerInitials(player.name))}</span>
              <div><p>Nouvel aventurier</p><h3>${escapeHtml(player.name || "Joueur")}</h3></div>
            </div>
            <div class="adventurer-card__badges">
              <span class="level-badge">Niv. ${level}</span>
              <span class="adventurer-card__presence${activity.isOnline ? " is-online" : ""}" data-player-presence>${activity.presence}</span>
            </div>
            <div class="adventurer-card__portraits" aria-hidden="true">
              <span class="adventurer-card__pal adventurer-card__pal--empty">${escapeHtml(playerInitials(player.name))}</span>
            </div>
          </div>
          <div class="adventurer-card__pending">
            <strong>Fiche en préparation</strong>
            <span>La connexion est détectée. La progression apparaîtra après la première sauvegarde du personnage.</span>
          </div>
          <div class="adventurer-card__quickfacts" aria-label="Résumé de ${escapeHtml(player.name || "ce joueur")}">
            <span><small>Présence</small><strong data-player-activity="lastSeen">${activity.lastSeen}</strong></span>
            <span><small>Équipe</small><strong>À venir</strong></span>
          </div>
          <a class="adventurer-card__open" href="${playerRoute(player)}" data-player-index="${index}">Voir la fiche de ${escapeHtml(player.name || "ce joueur")}</a>
        </article>
      `;
    }
    const teamPortraits = teamPals.length
      ? teamPals.slice(0, 3).map((pal) => gameImage(pal.icon, pal.species || pal.name, "adventurer-card__pal")).join("")
      : `<span class="adventurer-card__pal adventurer-card__pal--empty">${escapeHtml(playerInitials(player.name))}</span>`;
    const teamMarkup = teamPals.length
      ? teamPals.slice(0, 5).map((pal) => `<span>${escapeHtml(pal.name || pal.species || "Pal")}${pal.level != null ? ` <b>Niv. ${Number(pal.level)}</b>` : ""}</span>`).join("")
      : "<span>Équipe non détectée dans l'index public</span>";
    const guildBases = player.guildBases != null ? Number(player.guildBases) : null;
    const quickFacts = [
      `<span><small>Pals</small><strong>${Number(pals.total || 0).toLocaleString("fr-CA")}</strong></span>`,
      `<span><small>Équipe</small><strong>${Number(pals.party || teamPals.length || 0).toLocaleString("fr-CA")}</strong></span>`,
      guildBases != null ? `<span><small>Bases</small><strong>${guildBases.toLocaleString("fr-CA")}</strong></span>` : "",
      `<span><small>Dernière vue</small><strong data-player-activity="lastSeen">${activity.lastSeen}</strong></span>`,
    ].filter(Boolean).slice(0, 3).join("");

    return `
      <article class="adventurer-card${visibilityClass}"${visibilityAttribute} data-player-slug="${playerSlug(player.name)}" style="--card-order: ${index};--card-accent:${cardAccent}">
        <div class="adventurer-card__cover">
          <div class="adventurer-card__identity">
            <span class="adventurer-card__monogram" aria-hidden="true">${escapeHtml(playerInitials(player.name))}</span>
            <div>
              <p>${escapeHtml(player.guild || "Aventurier indépendant")}</p>
              <h3>${escapeHtml(player.name || "Joueur")}</h3>
            </div>
          </div>
          <div class="adventurer-card__badges">
            <span class="level-badge">Niv. ${Number(player.level || 0)}</span>
            <span class="adventurer-card__presence${activity.isOnline ? " is-online" : ""}" data-player-presence>${activity.presence}</span>
          </div>
          <div class="adventurer-card__portraits" aria-label="Pals de l'équipe de ${escapeHtml(player.name || "ce joueur")}">
            ${teamPortraits}
          </div>
        </div>
        <div class="adventurer-card__team">
          <small>Équipe active</small>
          <div>${teamMarkup}</div>
        </div>
        <div class="adventurer-card__quickfacts" aria-label="Résumé de ${escapeHtml(player.name || "ce joueur")}">
          ${quickFacts}
        </div>
        <a class="adventurer-card__open" href="${playerRoute(player)}" data-player-index="${index}">Voir la fiche de ${escapeHtml(player.name || "ce joueur")}</a>
      </article>
    `;
  }).join("");
  syncPlayerVisibilityToggle(players.some((player, index) => playerIsInactiveForMobile(player, index)));
  renderLeaderboards();
  if (selectedPlayer?.provisional) {
    const selectedIndex = players.findIndex((player) => playerSlug(player.name) === playerSlug(selectedPlayer.name));
    if (selectedIndex >= 0 && !players[selectedIndex].provisional) {
      void openPlayerDetails(selectedIndex, "profile", false);
    }
  }
  if (syncRoute) openPlayerFromRoute();
}

function humanizeAsset(value) {
  const source = String(value || "").trim();
  if (!source || source.toLocaleLowerCase("fr-CA") === "none") return "Aucune";
  return source
    .replace(/^EPal[^:]+::/, "")
    .replace(/[_-]+/g, " ")
    .replace(/([a-zà-ÿ])([A-Z])/g, "$1 $2")
    .trim() || "À découvrir";
}

function baseWorkerMarkup(worker) {
  const suitability = Array.isArray(worker.workSuitabilityBonuses) ? worker.workSuitabilityBonuses : [];
  const aptitudes = suitability.length
    ? suitability.slice(0, 4).map((item) => `<span>${escapeHtml(item.name)} <b>${Number(item.level || 0)}</b></span>`).join("")
    : "<span>Aptitudes à découvrir</span>";
  const health = worker.healthStatus || "En forme";
  return `
    <article class="base-worker${worker.healthStatus ? " is-unwell" : ""}">
      ${gameImage(worker.icon, worker.species || worker.name, "base-worker__portrait")}
      <div class="base-worker__identity">
        <span>${escapeHtml(worker.species || "Pal")}</span>
        <strong>${escapeHtml(worker.name || worker.species || "Pal")}</strong>
        <small>Niv. ${Number(worker.level || 0)} · ${escapeHtml(health)}</small>
      </div>
      <div class="base-worker__task"><small>Tâche observée</small><strong>${escapeHtml(worker.task || "Disponible à la base")}</strong></div>
      <div class="base-worker__aptitudes">${aptitudes}</div>
      <div class="base-worker__vitals">
        <span data-tooltip="Satiété"><small>Faim</small><b>${Math.round(Number(worker.hunger || 0))}</b></span>
        <span data-tooltip="Santé mentale"><small>SAN</small><b>${worker.sanity == null ? "--" : Math.round(Number(worker.sanity))}</b></span>
        <span data-tooltip="Vitesse de travail calculée"><small>Travail</small><b>${worker.computedStats?.workSpeed ?? "--"}</b></span>
      </div>
    </article>
  `;
}

function baseCountChips(rows, emptyText) {
  if (!Array.isArray(rows) || !rows.length) return `<p class="base-card__empty">${escapeHtml(emptyText)}</p>`;
  return rows.map((row) => `<span><strong>${Number(row.count || 0).toLocaleString("fr-CA")}</strong>${escapeHtml(row.name)}</span>`).join("");
}

function baseItemMarkup(item) {
  return `
    <article class="base-resource">
      ${gameImage(item.icon, item.name, "base-resource__icon")}
      <span><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.category || "Ressource")}</small></span>
      <b>${Number(item.count || 0).toLocaleString("fr-CA")}</b>
    </article>
  `;
}

const stockSourceMeta = {
  chests: { label: "Coffres", shortLabel: "Coffres" },
  production: { label: "Production", shortLabel: "Production" },
  guild: { label: "Stockage de guilde", shortLabel: "Guilde" },
};

function stockBelongsToPlayer(storage, player) {
  if (!player) return false;
  const playerName = String(player.name || "").toLocaleLowerCase("fr-CA");
  const members = Array.isArray(storage?.players) ? storage.players : [];
  if (members.length) {
    return members.some((name) => String(name || "").toLocaleLowerCase("fr-CA") === playerName);
  }
  return storage?.guild && storage.guild === player.guild;
}

function buildSelectedPlayerStock() {
  const grouped = new Map();
  const addItems = (source, location, items) => {
    (Array.isArray(items) ? items : []).forEach((item) => {
      const name = String(item.name || "Ressource");
      const category = translateItemCategory(item.category);
      const key = `${source}|${name.toLocaleLowerCase("fr-CA")}|${category.toLocaleLowerCase("fr-CA")}`;
      const current = grouped.get(key) || {
        source,
        sourceLabel: stockSourceMeta[source].label,
        name,
        category,
        icon: item.icon || null,
        count: 0,
        locations: new Set(),
      };
      current.count += Number(item.count || 0);
      if (location) current.locations.add(location);
      if (!current.icon && item.icon) current.icon = item.icon;
      grouped.set(key, current);
    });
  };

  selectedPlayerBases.forEach((base) => {
    addItems("chests", base.name, base.storage?.topItems);
    addItems("production", base.name, base.production?.topItems);
  });
  (Array.isArray(currentBasesSnapshot()?.guildStorage) ? currentBasesSnapshot().guildStorage : [])
    .filter((storage) => stockBelongsToPlayer(storage, selectedPlayer))
    .forEach((storage) => addItems("guild", storage.guild || "Guilde", storage.topItems));

  return [...grouped.values()]
    .map((item) => ({ ...item, locations: [...item.locations].sort((left, right) => left.localeCompare(right, "fr-CA")) }))
    .sort((left, right) => right.count - left.count || left.name.localeCompare(right.name, "fr-CA"));
}

function stockItemMarkup(item) {
  const locationText = item.locations.length > 1
    ? `${item.locations.length} campements`
    : (item.locations[0] || "Guilde");
  return `
    <article class="stock-item stock-item--${escapeHtml(item.source)}">
      ${gameImage(item.icon, item.name, "stock-item__icon")}
      <div class="stock-item__body">
        <span class="stock-item__source">${escapeHtml(stockSourceMeta[item.source].shortLabel)}</span>
        <strong data-tooltip="${escapeHtml(item.name)}">${escapeHtml(item.name)}</strong>
        <small>${escapeHtml(item.category)} · ${escapeHtml(locationText)}</small>
      </div>
      <b>${Number(item.count || 0).toLocaleString("fr-CA")}<small> unités</small></b>
    </article>
  `;
}

function stockPageNumbers(current, total) {
  if (total <= 7) return Array.from({ length: total }, (_, index) => index + 1);
  const pages = new Set([1, total, current - 1, current, current + 1]);
  const ordered = [...pages].filter((page) => page >= 1 && page <= total).sort((left, right) => left - right);
  const output = [];
  ordered.forEach((page, index) => {
    if (index && page - ordered[index - 1] > 1) output.push("ellipsis");
    output.push(page);
  });
  return output;
}

function renderStockExplorer() {
  if (!stockResults || !selectedPlayer) return;
  const sourceRows = stockSource === "all"
    ? selectedPlayerStock
    : selectedPlayerStock.filter((item) => item.source === stockSource);
  const categories = [...new Set(sourceRows.map((item) => item.category))]
    .sort((left, right) => left.localeCompare(right, "fr-CA"));
  const selectedCategory = categories.includes(stockCategory.value) ? stockCategory.value : "all";
  stockCategory.innerHTML = [
    '<option value="all">Toutes les catégories</option>',
    ...categories.map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`),
  ].join("");
  stockCategory.value = selectedCategory;

  const query = String(stockSearch.value || "").trim().toLocaleLowerCase("fr-CA");
  const filtered = sourceRows.filter((item) => {
    const matchesCategory = selectedCategory === "all" || item.category === selectedCategory;
    const searchable = `${item.name} ${item.category} ${item.sourceLabel} ${item.locations.join(" ")}`.toLocaleLowerCase("fr-CA");
    return matchesCategory && (!query || searchable.includes(query));
  });
  const pageCount = Math.max(1, Math.ceil(filtered.length / stockPageSize));
  stockCurrentPage = Math.min(stockCurrentPage, pageCount);
  const start = (stockCurrentPage - 1) * stockPageSize;
  const visible = filtered.slice(start, start + stockPageSize);

  const totalUnits = selectedPlayerStock.reduce((total, item) => total + item.count, 0);
  const uniqueTypes = new Set(selectedPlayerStock.map((item) => item.name.toLocaleLowerCase("fr-CA"))).size;
  stockTotal.textContent = `${totalUnits.toLocaleString("fr-CA")} unités · ${uniqueTypes} types`;
  stockResultCount.textContent = filtered.length
    ? `${filtered.length} ressource${filtered.length > 1 ? "s" : ""} · page ${stockCurrentPage} sur ${pageCount}`
    : "Aucune ressource ne correspond à ces filtres.";
  stockResults.innerHTML = visible.length
    ? visible.map(stockItemMarkup).join("")
    : '<p class="detail-empty stock-results__empty">Essaie un autre mot-clé, une autre catégorie ou une autre source.</p>';

  const sourceCounts = selectedPlayerStock.reduce((counts, item) => {
    counts[item.source] = (counts[item.source] || 0) + 1;
    return counts;
  }, {});
  document.querySelectorAll("[data-stock-source-count]").forEach((counter) => {
    counter.textContent = counter.dataset.stockSourceCount === "all"
      ? selectedPlayerStock.length
      : (sourceCounts[counter.dataset.stockSourceCount] || 0);
  });
  stockSourceButtons.forEach((button) => {
    const active = button.dataset.stockSource === stockSource;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });

  stockPagination.innerHTML = pageCount > 1 ? [
    `<button type="button" data-stock-page="${stockCurrentPage - 1}" ${stockCurrentPage === 1 ? "disabled" : ""} aria-label="Page précédente">Précédente</button>`,
    ...stockPageNumbers(stockCurrentPage, pageCount).map((page) => page === "ellipsis"
      ? '<span aria-hidden="true">…</span>'
      : `<button type="button" data-stock-page="${page}" class="${page === stockCurrentPage ? "is-active" : ""}" ${page === stockCurrentPage ? 'aria-current="page"' : ""}>${page}</button>`),
    `<button type="button" data-stock-page="${stockCurrentPage + 1}" ${stockCurrentPage === pageCount ? "disabled" : ""} aria-label="Page suivante">Suivante</button>`,
  ].join("") : "";
}

function baseCardMarkup(base, index) {
  const workers = Array.isArray(base.workers?.list) ? base.workers.list : [];
  const structures = base.structures || {};
  const storage = base.storage || {};
  const resources = Array.isArray(storage.topItems) ? storage.topItems : [];
  const healthClass = Number(base.workers?.unwell || 0) || Number(structures.damaged || 0) ? " has-alerts" : "";
  return `
    <details class="base-card${healthClass}" data-base-index="${index}">
      <summary>
        <span class="base-card__emblem" aria-hidden="true">⌂</span>
        <span class="base-card__identity"><small>${escapeHtml(base.guild || "Guilde")}</small><strong>${escapeHtml(base.name || "Base")}</strong><b>Camp niv. ${Number(base.campLevel || 0)}</b></span>
        <span class="base-card__headline"><b>${Number(base.workers?.assigned || 0)}</b><small>travailleurs</small></span>
        <span class="base-card__headline"><b>${Number(structures.total || 0)}</b><small>structures</small></span>
        <span class="base-card__headline"><b>${Number(storage.units || 0)}</b><small>stockages</small></span>
        <span class="base-card__health">${Number(base.workers?.unwell || 0) ? `${Number(base.workers.unwell)} à soigner` : "Équipe en forme"}</span>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6.7 9.7 5.3 5.2 5.3-5.2 1.4 1.4-6.7 6.6-6.7-6.6 1.4-1.4Z"/></svg>
      </summary>
      <div class="base-card__body">
        <div class="base-card__overview">
          <article><span>Au travail</span><strong>${Number(base.workers?.busy || 0)} / ${Number(base.workers?.assigned || 0)}</strong><small>Pals avec une tâche observée</small></article>
          <article><span>État des bâtiments</span><strong>${Number(structures.damaged || 0)} endommagé${Number(structures.damaged || 0) > 1 ? "s" : ""}</strong><small>${Number(structures.unfinished || 0)} construction${Number(structures.unfinished || 0) > 1 ? "s" : ""} en cours</small></article>
          <article><span>Occupation des stocks</span><strong>${Number(storage.fillPercent || 0).toLocaleString("fr-CA")} %</strong><small>${Number(storage.used || 0)} / ${Number(storage.capacity || 0)} emplacements</small></article>
          <article><span>Ressources différentes</span><strong>${Number(storage.itemTypes ?? resources.length).toLocaleString("fr-CA")}</strong><small>Tous les types trouvés dans les coffres</small></article>
        </div>

        <section class="base-card__section">
          <header><div><p class="eyebrow">Équipe de la base</p><h3>Pals travailleurs</h3></div><span>${workers.length} affectés</span></header>
          <div class="base-worker-grid">${workers.length ? workers.map(baseWorkerMarkup).join("") : '<p class="base-card__empty">Aucun Pal affecté à cette base.</p>'}</div>
        </section>

        <div class="base-card__columns">
          <section class="base-card__section">
            <header><div><p class="eyebrow">Architecture</p><h3>Structures</h3></div><span>${Number(structures.total || 0)} au total</span></header>
            <div class="base-chip-grid">${baseCountChips(structures.categories, "Aucune structure catégorisée.")}</div>
            <h4>Bâtiments les plus présents</h4>
            <div class="base-highlight-list">${baseCountChips(structures.highlights, "Aucun bâtiment relevé.")}</div>
          </section>
          <section class="base-card__section">
            <header><div><p class="eyebrow">Réserves</p><h3>Coffres et ressources</h3></div><span>${Number(storage.units || 0)} stockages · ${resources.length} types</span></header>
            <div class="base-storage-meter"><span style="width:${Math.min(100, Number(storage.fillPercent || 0))}%"></span></div>
            <details class="base-resource-disclosure">
              <summary>Afficher les ${resources.length} types de ressources</summary>
              <div class="base-resource-list">${resources.length ? resources.map(baseItemMarkup).join("") : '<p class="base-card__empty">Aucune ressource stockée dans les coffres analysés.</p>'}</div>
            </details>
          </section>
        </div>
      </div>
    </details>
  `;
}

function baseBelongsToPlayer(base, player) {
  if (!player) return false;
  const playerName = String(player.name || "").toLocaleLowerCase("fr-CA");
  const members = Array.isArray(base?.players) ? base.players : [];
  if (members.length) {
    return members.some((name) => String(name || "").toLocaleLowerCase("fr-CA") === playerName);
  }
  return base?.guild && base.guild !== "Guilde anonyme" && base.guild === player.guild;
}

function normalizeExportValue(value) {
  if (Array.isArray(value)) return value.map(normalizeExportValue);
  if (!value || typeof value !== "object") return value;
  return Object.keys(value)
    .sort((left, right) => left.localeCompare(right, "fr-CA"))
    .reduce((output, key) => {
      output[key] = normalizeExportValue(value[key]);
      return output;
    }, {});
}

function cloneExportValue(value) {
  return value == null ? value : normalizeExportValue(JSON.parse(JSON.stringify(value)));
}

function exportTimestampSlug(date = new Date()) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    "-",
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join("");
}

function selectedPlayerBaseRows(player = selectedPlayer) {
  const bases = currentBasesSnapshot();
  return (Array.isArray(bases?.bases) ? bases.bases : [])
    .filter((base) => baseBelongsToPlayer(base, player));
}

function selectedPlayerGuildStorageRows(player = selectedPlayer) {
  const bases = currentBasesSnapshot();
  return (Array.isArray(bases?.guildStorage) ? bases.guildStorage : [])
    .filter((storage) => stockBelongsToPlayer(storage, player));
}

async function ensurePlayerExportDataReady() {
  if (!currentBasesSnapshot()) await loadBases(true);
  if (selectedPlayer) {
    if (!selectedPlayer.provisional) {
      try {
        await hydratePlayerFromPublicCatalogs(selectedPlayer);
      } catch {
        // Les catalogues enrichissent l'analyse, mais leur absence ne bloque pas l'export public.
      }
    }
    selectedPlayerBases = selectedPlayerBaseRows(selectedPlayer);
    selectedPlayerStock = buildSelectedPlayerStock();
  }
}

function playerExportPayloadMeta(payload, source, fallback = {}) {
  const available = Boolean(payload);
  return cloneExportValue({
    source,
    status: available ? (payload?.ok === false ? "unavailable" : "available") : "unavailable",
    generationId: publicSaveGenerationId(payload) || fallback.generationId || null,
    version: payload?.version ?? fallback.version ?? null,
    updatedAt: payload?.updatedAt || fallback.updatedAt || null,
    provenance: payload?.provenance || fallback.provenance || null,
  });
}

function playerRawFields(player) {
  return {
    player: Object.keys(player || {}).sort((left, right) => left.localeCompare(right, "fr-CA")),
    character: Object.keys(player?.character || {}).sort((left, right) => left.localeCompare(right, "fr-CA")),
    progress: Object.keys(player?.progress || {}).sort((left, right) => left.localeCompare(right, "fr-CA")),
    pals: Object.keys(player?.pals || {}).sort((left, right) => left.localeCompare(right, "fr-CA")),
    inventorySections: (Array.isArray(player?.inventory) ? player.inventory : [])
      .map((section) => String(section?.key || section?.label || "section"))
      .sort((left, right) => left.localeCompare(right, "fr-CA")),
  };
}

function currentPlayerIndexRow(player) {
  const slug = playerSlug(player?.name);
  return (Array.isArray(saveSnapshot?.players) ? saveSnapshot.players : [])
    .find((row) => playerSlug(row?.name) === slug) || null;
}

function playerInventoryExportSummary(player) {
  const sections = Array.isArray(player?.inventory) ? player.inventory : [];
  const sectionSummaries = sections.map((section) => {
    const items = Array.isArray(section?.items) ? section.items : [];
    return {
      key: section?.key || null,
      label: section?.label || null,
      itemTypes: items.length,
      quantity: items.reduce((sum, item) => sum + Number(item?.count || 0), 0),
      totalWeight: Math.round(items.reduce((sum, item) => sum + Number(item?.totalWeight || 0), 0) * 10) / 10,
    };
  });
  return {
    sections: sections.length,
    itemTypes: sectionSummaries.reduce((sum, section) => sum + section.itemTypes, 0),
    quantity: sectionSummaries.reduce((sum, section) => sum + section.quantity, 0),
    totalWeight: Math.round(sectionSummaries.reduce((sum, section) => sum + section.totalWeight, 0) * 10) / 10,
    bySection: sectionSummaries,
  };
}

function playerPalExportSummary(player) {
  const collection = Array.isArray(player?.pals?.collection) ? player.pals.collection : [];
  const containers = collection.reduce((counts, pal) => {
    const key = String(pal?.container || "other");
    counts[key] = (counts[key] || 0) + 1;
    return counts;
  }, {});
  return {
    total: player?.pals?.total ?? collection.length,
    collection: collection.length,
    party: containers.party || 0,
    palbox: containers.palbox || 0,
    other: collection.length - Number(containers.party || 0) - Number(containers.palbox || 0),
    uniqueSpecies: player?.pals?.uniqueSpecies ?? null,
    highestLevel: player?.pals?.highestLevel ?? null,
    favorites: Array.isArray(player?.pals?.favorites) ? player.pals.favorites.length : 0,
    containers,
  };
}

function playerBaseExportSummary(bases, guildStorage, stock) {
  return {
    bases: bases.length,
    structures: bases.reduce((total, base) => total + Number(base?.structures?.total || 0), 0),
    damagedStructures: bases.reduce((total, base) => total + Number(base?.structures?.damaged || 0), 0),
    unfinishedStructures: bases.reduce((total, base) => total + Number(base?.structures?.unfinished || 0), 0),
    workersAssigned: bases.reduce((total, base) => total + Number(base?.workers?.assigned || 0), 0),
    workersBusy: bases.reduce((total, base) => total + Number(base?.workers?.busy || 0), 0),
    storageUnits: bases.reduce((total, base) => total + Number(base?.storage?.units || 0), 0),
    productionUnits: bases.reduce((total, base) => total + Number(base?.production?.units || 0), 0),
    guildStorageUnits: guildStorage.reduce((total, storage) => total + Number(storage?.units || 1), 0),
    stockItemTypes: stock.length,
    stockQuantity: stock.reduce((total, item) => total + Number(item?.count || 0), 0),
  };
}

function playerActivityExport(player) {
  const values = getPlayerActivityValues(player);
  return {
    status: values.activity ? "available" : "unavailable",
    isOnline: values.isOnline,
    labels: {
      presence: values.presence,
      sessions: values.sessions,
      playtime: values.playtime,
      lastSeen: values.lastSeen,
      lastSeenNote: values.lastSeenNote,
      ping: values.ping,
    },
    raw: cloneExportValue(values.activity),
  };
}

function buildPlayerAnalysisExport(player) {
  const collection = Array.isArray(player?.pals?.collection) ? player.pals.collection : [];
  const party = collection.filter((pal) => pal.container === "party");
  const palbox = collection.filter((pal) => pal.container === "palbox");
  const otherPals = collection.filter((pal) => !["party", "palbox"].includes(String(pal.container || "")));
  const bases = selectedPlayerBaseRows(player);
  const guildStorage = selectedPlayerGuildStorageRows(player);
  const baseSnapshot = currentBasesSnapshot();
  const indexPlayer = currentPlayerIndexRow(player);
  const activity = playerActivityExport(player);
  const inventory = playerInventoryExportSummary(player);
  const pals = playerPalExportSummary(player);
  const baseSummary = playerBaseExportSummary(bases, guildStorage, selectedPlayerStock);
  const playerPayload = selectedPlayerSnapshotPayload?.player === player ? selectedPlayerSnapshotPayload : null;

  const payload = {
    export: {
      schema: "gaylemon-player-analysis",
      schemaVersion: 2,
      generatedAt: new Date().toISOString(),
      source: "Gaylémon Palworld",
      locale: "fr-CA",
      timeZone: siteTimeZone,
      publicOnly: true,
      deterministic: {
        objectKeys: "sorted-recursively",
        arrayOrder: "source-order-preserved",
        missingValues: "null-or-empty-array",
      },
      note: "Données publiques en vigueur au moment de l'export. Les blocs complets sont sous data et relations.",
    },
    entity: {
      type: "player",
      name: player?.name || null,
      slug: playerSlug(player?.name),
      guild: player?.guild || null,
      level: player?.level ?? null,
    },
    sources: {
      player: playerExportPayloadMeta(playerPayload, "players/{slug}.json", {
        generationId: activeSaveGenerationId(),
        updatedAt: saveSnapshot?.updatedAt || null,
        version: saveSnapshot?.version ?? null,
        provenance: saveSnapshot?.provenance || null,
      }),
      index: playerExportPayloadMeta(saveSnapshot, "public-save-index.json"),
      bases: playerExportPayloadMeta(baseSnapshot, "public-save-bases.json"),
      stats: playerExportPayloadMeta(statsSnapshot, "public-stats.json"),
      catalogs: publicCatalogManifest
        ? playerExportPayloadMeta(publicCatalogManifest, "public-catalogs-manifest.json")
        : { source: "public-catalogs-manifest.json", status: "unavailable", generationId: null, version: null, updatedAt: null, provenance: null },
    },
    summary: {
      player: {
        level: player?.level ?? null,
        guild: player?.guild || null,
        guildBases: player?.guildBases ?? null,
        campLevel: player?.campLevel ?? null,
        position: cloneExportValue(player?.position || null),
      },
      activity: cloneExportValue(activity.labels),
      pals: cloneExportValue(pals),
      inventory: cloneExportValue(inventory),
      bases: cloneExportValue(baseSummary),
      progress: cloneExportValue({
        technologyPoints: player?.progress?.technologyPoints ?? null,
        bossTechnologyPoints: player?.progress?.bossTechnologyPoints ?? null,
        unlockedTechnologies: player?.progress?.unlockedTechnologies ?? null,
        completedQuests: player?.progress?.completedQuests ?? null,
        paldexCapturedSpecies: player?.progress?.paldex?.capturedSpecies ?? null,
        explorationCompletionPercent: player?.progress?.exploration?.completionPercent ?? null,
      }),
    },
    data: {
      rawPublicFields: cloneExportValue(playerRawFields(player)),
      player: cloneExportValue(player),
      indexPlayer: cloneExportValue(indexPlayer),
      activity: cloneExportValue(activity),
      pals: {
        summary: cloneExportValue(pals),
        party: cloneExportValue(party),
        palbox: cloneExportValue(palbox),
        other: cloneExportValue(otherPals),
      },
      inventory: {
        summary: cloneExportValue(inventory),
        sections: cloneExportValue(player?.inventory || []),
      },
      progress: cloneExportValue(player?.progress || {}),
      character: cloneExportValue(player?.character || {}),
    },
    relations: {
      bases: {
        summary: cloneExportValue(baseSummary),
        items: cloneExportValue(bases),
        constructions: cloneExportValue(bases.map((base) => ({
          name: base.name || null,
          guild: base.guild || null,
          campLevel: base.campLevel ?? null,
          position: base.position || null,
          structures: base.structures || {},
          workers: base.workers || {},
          work: base.work || {},
          research: base.research || {},
        }))),
      },
      guildStorage: {
        summary: {
          units: guildStorage.reduce((total, storage) => total + Number(storage?.units || 1), 0),
          itemTypes: guildStorage.reduce((total, storage) => total + Number(storage?.itemTypes || 0), 0),
          rows: guildStorage.length,
        },
        items: cloneExportValue(guildStorage),
      },
      stock: {
        summary: {
          itemTypes: selectedPlayerStock.length,
          quantity: selectedPlayerStock.reduce((total, item) => total + Number(item?.count || 0), 0),
          sources: selectedPlayerStock.reduce((counts, item) => {
            const source = item?.source || "unknown";
            counts[source] = (counts[source] || 0) + 1;
            return counts;
          }, {}),
        },
        items: cloneExportValue(selectedPlayerStock),
      },
    },
    analysisGuide: {
      audience: "lecture automatisée et audit humain",
      entrypoints: [
        { key: "summary", use: "Vue courte et déterministe pour décider quoi inspecter." },
        { key: "data.player", use: "Profil public complet chargé par la fiche joueur." },
        { key: "data.inventory.sections", use: "Inventaire complet, groupé selon les sections publiques." },
        { key: "data.pals", use: "Collection complète, aussi découpée en équipe, Palbox et autres conteneurs publics." },
        { key: "relations.bases.items", use: "Bases reliées au joueur ou à sa guilde." },
        { key: "relations.stock.items", use: "Stock agrégé prêt à filtrer par source, ressource ou campement." },
      ],
      joins: [
        { from: "entity.slug", to: "data.indexPlayer.name via playerSlug(name)" },
        { from: "entity.guild", to: "relations.bases.items[].guild" },
        { from: "entity.guild", to: "relations.guildStorage.items[].guild" },
        { from: "relations.stock.items[].locations[]", to: "relations.bases.items[].name" },
      ],
      privacy: [
        "Projection publique seulement.",
        "Aucun GUID, Steam ID, chemin système, conteneur privé ou détail exact de coffre.",
        "Le stock est agrégé par ressource et source publique.",
      ],
    },
  };
  return normalizeExportValue(payload);
}

function downloadJsonExport(payload, filename) {
  const blob = new Blob([`${JSON.stringify(payload, null, 2)}\n`], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function playerExportButtons() {
  return [...document.querySelectorAll("[data-player-export]")];
}

function setPlayerExportButtonsState({ label = "", state = "", disabled = Boolean(selectedPlayer?.provisional) } = {}) {
  playerExportButtons().forEach((button) => {
    const labelTarget = button.querySelector("[data-player-export-label]") || button;
    labelTarget.textContent = label || button.dataset.exportLabel || "Exporter JSON";
    button.classList.toggle("is-success", state === "success");
    button.classList.toggle("is-error", state === "error");
    button.disabled = disabled;
  });
}

function resetPlayerExportButtons() {
  setPlayerExportButtonsState();
}

async function exportSelectedPlayerAnalysisJson() {
  if (!selectedPlayer || selectedPlayer.provisional || !playerExportButtons().length) return;
  setPlayerExportButtonsState({ label: "Préparation...", disabled: true });

  try {
    await ensurePlayerExportDataReady();
    const payload = buildPlayerAnalysisExport(selectedPlayer);
    const filename = `gaylemon-${playerSlug(selectedPlayer.name)}-analyse-${exportTimestampSlug()}.json`;
    downloadJsonExport(payload, filename);
    setPlayerExportButtonsState({ label: "JSON exporté", state: "success", disabled: true });
    window.setTimeout(resetPlayerExportButtons, 3000);
  } catch {
    setPlayerExportButtonsState({ label: "Export impossible", state: "error", disabled: true });
    window.setTimeout(resetPlayerExportButtons, 3500);
  }
}

function filterBases() {
  if (!baseGrid) return;
  const query = String(baseSearch?.value || "").trim().toLocaleLowerCase("fr-CA");
  let visible = 0;
  [...baseGrid.querySelectorAll("[data-base-index]")].forEach((card) => {
    const base = selectedPlayerBases[Number(card.dataset.baseIndex)];
    if (!base) return;
    const searchText = [
      base.name,
      base.guild,
      ...(Array.isArray(base.structures?.highlights) ? base.structures.highlights : []).map((row) => row.name),
      ...(Array.isArray(base.storage?.topItems) ? base.storage.topItems : []).map((row) => row.name),
      ...(Array.isArray(base.production?.topItems) ? base.production.topItems : []).map((row) => row.name),
      ...(Array.isArray(base.workers?.list) ? base.workers.list : []).map((worker) => `${worker.name} ${worker.species}`),
    ].join(" ").toLocaleLowerCase("fr-CA");
    const matches = !query || searchText.includes(query);
    card.hidden = !matches;
    if (matches) visible += 1;
  });
  baseResultCount.textContent = `${visible} campement${visible > 1 ? "s" : ""} affiché${visible > 1 ? "s" : ""}`;
}

function renderSelectedPlayerBases() {
  if (!baseGrid || !selectedPlayer) return;
  const bases = currentBasesSnapshot();
  selectedPlayerBases = (Array.isArray(bases?.bases) ? bases.bases : [])
    .filter((base) => baseBelongsToPlayer(base, selectedPlayer));
  selectedPlayerStock = buildSelectedPlayerStock();
  const workers = selectedPlayerBases.reduce((total, base) => total + Number(base.workers?.assigned || 0), 0);
  const busyWorkers = selectedPlayerBases.reduce((total, base) => total + Number(base.workers?.busy || 0), 0);
  const guildStorageUnits = (Array.isArray(bases?.guildStorage) ? bases.guildStorage : [])
    .filter((storage) => stockBelongsToPlayer(storage, selectedPlayer))
    .reduce((total, storage) => total + Number(storage.units || 1), 0);
  const summary = {
    bases: selectedPlayerBases.length,
    busyWorkers: `${busyWorkers.toLocaleString("fr-CA")} / ${workers.toLocaleString("fr-CA")}`,
    structures: selectedPlayerBases.reduce((total, base) => total + Number(base.structures?.total || 0), 0),
    storageUnits: selectedPlayerBases.reduce(
      (total, base) => total + Number(base.storage?.units || 0) + Number(base.production?.units || 0),
      guildStorageUnits,
    ),
    resourceTypes: new Set(selectedPlayerStock.map((item) => item.name.toLocaleLowerCase("fr-CA"))).size,
  };
  Object.entries(summary).forEach(([key, value]) => {
    const element = document.querySelector(`[data-base-summary="${key}"]`);
    if (element) element.textContent = typeof value === "number" ? value.toLocaleString("fr-CA") : value;
  });
  if (basesState) basesState.textContent = bases ? "Campements synchronisés" : "Chargement...";
  baseGrid.innerHTML = selectedPlayerBases.length
    ? selectedPlayerBases.map(baseCardMarkup).join("")
    : '<p class="detail-empty detail-empty--large">Aucun campement n’est associé à cet aventurier.</p>';
  renderStockExplorer();
  filterBases();
}

function renderBaseSnapshot(payload) {
  if (!payload?.ok || !Array.isArray(payload.bases)) {
    if (basesState) basesState.textContent = "En attente";
    registerPayloadDataUpdate("bases", payload);
    return;
  }
  basesSnapshot = payload;
  registerPayloadDataUpdate("bases", payload);
  if (basesState) basesState.textContent = `${Number(payload.bases.length || 0).toLocaleString("fr-CA")} bases synchronisées`;
  renderWorldContractStatus();
  if (selectedPlayer) renderSelectedPlayerBases();
  renderGlobalPlayerMap(saveSnapshot?.players || [], payload.bases);
}

const eventTypeMeta = {
  join: { label: "Arrivées", token: "+", color: "#34c98a" },
  leave: { label: "Départs", token: "−", color: "#ef8c5b" },
  reconnect: { label: "Reconnexions", token: "↻", color: "#39b9c5" },
  capture: { label: "Captures", token: "PAL", color: "#52a7e0" },
  challenge: { label: "Défis", token: "★", color: "#efb842" },
  quest: { label: "Quêtes", token: "!", color: "#bc8ee2" },
  loot: { label: "Trésors", token: "◆", color: "#e59d4d" },
  adventure: { label: "Expéditions", token: "⚑", color: "#58b99b" },
  raid: { label: "Raids", token: "RAID", color: "#ef6f6c" },
  boss: { label: "Boss", token: "BOSS", color: "#d86f72" },
  arena: { label: "Arènes", token: "ARN", color: "#d8954d" },
  death: { label: "Sacs", token: "SAC", color: "#b36f63" },
  recovery: { label: "Récupérations", token: "REC", color: "#8aa05e" },
  note: { label: "Notes", token: "NTE", color: "#d5a84f" },
  pal: { label: "Pals", token: "PAL", color: "#55a9d6" },
  mutation: { label: "Mutations", token: "MUT", color: "#b682d8" },
  collection: { label: "Collections", token: "PAL", color: "#4da2dd" },
  craft: { label: "Fabrications", token: "CRA", color: "#f18b55" },
  build: { label: "Constructions", token: "BLD", color: "#68b35d" },
  production: { label: "Productions", token: "PRD", color: "#4cc3b2" },
  hatch: { label: "Éclosions", token: "EGG", color: "#e58ccf" },
  fishing: { label: "Pêche", token: "FSH", color: "#4aa8dd" },
  research: { label: "Recherches", token: "LAB", color: "#8b92e8" },
  base: { label: "Bases", token: "BAS", color: "#79b85a" },
  repair: { label: "Réparations", token: "REP", color: "#d99b4a" },
  level: { label: "Niveaux", token: "LVL", color: "#f1b94f" },
  progress: { label: "Progression", token: "XP", color: "#b88bdd" },
  camp: { label: "Camps et bases", token: "BASE", color: "#79b85a" },
  discovery: { label: "Découvertes", token: "NEW", color: "#e96c9b" },
  maintenance: { label: "Maintenances", token: "MAJ", color: "#e7a934" },
  settings: { label: "Règles du monde", token: "CFG", color: "#cf8b54" },
  server: { label: "Monde", token: "SYS", color: "#77a7be" },
};
function normalizeEventSearch(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("fr-CA");
}

function formatEventTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return { date: "Date inconnue", time: "--:--" };
  return {
    date: new Intl.DateTimeFormat("fr-CA", { day: "numeric", month: "short", year: "numeric" }).format(date),
    time: new Intl.DateTimeFormat("fr-CA", { hour: "2-digit", minute: "2-digit" }).format(date),
  };
}

function eventCanBePublished(event) {
  let details = "";
  try {
    details = JSON.stringify(event?.details || {});
  } catch {
    details = "";
  }
  const searchable = [
    event?.title,
    event?.message,
    event?.base,
    event?.headline,
    event?.body,
    event?.display?.headline,
    event?.display?.body,
    ...(Array.isArray(event?.display?.bullets) ? event.display.bullets : []),
    details,
  ].filter(Boolean).join(" ");
  return !/CommonDropItem3D/i.test(searchable);
}

function dedupeSessionFallbackEvents(events) {
  const sourceEvents = (Array.isArray(events) ? events : []).filter(eventCanBePublished);
  const journalTransitions = sourceEvents
    .filter((event) => event?.source === "journal" && ["join", "leave"].includes(event.type) && event.player)
    .map((event) => ({
      player: String(event.player).toLocaleLowerCase("fr-CA"),
      type: event.type,
      occurredAt: parseDate(event.occurredAt),
    }))
    .filter((event) => event.occurredAt);

  return sourceEvents.filter((event) => {
    if (event?.source !== "players" || !["join", "leave"].includes(event.type) || !event.player) return true;
    const occurredAt = parseDate(event.occurredAt);
    if (!occurredAt) return true;
    const player = String(event.player).toLocaleLowerCase("fr-CA");
    return !journalTransitions.some((journalEvent) => (
      journalEvent.player === player &&
      journalEvent.type === event.type &&
      Math.abs(journalEvent.occurredAt.getTime() - occurredAt.getTime()) <= 120000
    ));
  });
}

function selectedEventTypeValue() {
  return eventTypeFilter?.dataset.pendingValue || eventTypeFilter?.value || "all";
}

function selectedEventPlayerValue() {
  return eventPlayerFilter?.dataset.pendingValue || eventPlayerFilter?.value || "all";
}

function shortStableHash(value) {
  const text = String(value || "");
  let hash = 2166136261;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
}

function eventIdentity(event) {
  if (!event) return "";
  if (event.key) return `key:${event.key}`;
  if (event.source || event.id != null) return `${event.source || "event"}:${event.id ?? ""}`;
  const fallback = [
    event.occurredAt,
    event.type,
    event.player,
    event.base,
    event.title,
    event.message,
  ].filter(Boolean).join("|");
  return fallback ? `fallback:${shortStableHash(fallback)}` : "";
}

function publicEventOrderRank(event) {
  const source = String(event?.source || "");
  const type = String(event?.type || "");
  if (["journal", "players"].includes(source) && type === "leave") return 0;
  if (["journal", "players"].includes(source) && ["join", "reconnect"].includes(type)) return 2;
  return 1;
}

function sortEventsNewestFirst(events, options = {}) {
  const candidates = options.canonical
    ? [...(Array.isArray(events) ? events : [])]
    : dedupeSessionFallbackEvents(events);
  return candidates.sort((left, right) => {
    const rightDate = parseDate(right.occurredAt)?.getTime() || 0;
    const leftDate = parseDate(left.occurredAt)?.getTime() || 0;
    if (rightDate !== leftDate) return rightDate - leftDate;
    const rankDifference = publicEventOrderRank(left) - publicEventOrderRank(right);
    if (rankDifference !== 0) return rankDifference;
    return Number(right.id || 0) - Number(left.id || 0);
  });
}

function v6PublicDataPath(value, prefix) {
  const path = String(value || "").replace(/^\/+/, "");
  if (!path.startsWith(prefix) || /(?:\.\.|\\|%)/.test(path)) return "";
  return path;
}

function v6ManifestDays(manifest = eventsManifestV6) {
  return (Array.isArray(manifest?.days) ? manifest.days : [])
    .filter((entry) => isDailyDateKey(entry?.date) && v6PublicDataPath(entry?.path, "data/public-events-v6/"))
    .sort((left, right) => String(right.date).localeCompare(String(left.date)));
}

function shiftDailyDateKey(dateKey, days) {
  if (!isDailyDateKey(dateKey)) return "";
  const date = new Date(`${dateKey}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + Number(days || 0));
  return date.toISOString().slice(0, 10);
}

function v6NavigableDates(manifest = eventsManifestV6) {
  const published = v6ManifestDays(manifest).map((entry) => entry.date);
  const today = dailyDateKeyFromDate(new Date());
  if (!today) return published;
  const oldest = published.at(-1) || today;
  const dates = new Set(published);
  let cursor = today;
  for (let count = 0; count < 4000 && cursor >= oldest; count += 1) {
    dates.add(cursor);
    cursor = shiftDailyDateKey(cursor, -1);
  }
  return [...dates].sort((left, right) => right.localeCompare(left));
}

function v6DateCanBeOpened(dateKey, manifest = eventsManifestV6) {
  return v6NavigableDates(manifest).includes(dateKey);
}

function v6DayEntry(dateKey, manifest = eventsManifestV6) {
  return v6ManifestDays(manifest).find((entry) => entry.date === dateKey) || null;
}

function v6GenerationIsValid(payload, generationId, head = false) {
  if (!payload?.ok || Number(payload.schemaVersion) !== 6 || !generationId) return false;
  return String(head ? payload.baseGenerationId : payload.generationId) === String(generationId);
}

function v6Sha256IsValid(value) {
  return /^(?:sha256:)?[a-f0-9]{64}$/i.test(String(value || ""));
}

function v6ManifestAsIndex(manifest) {
  const days = v6ManifestDays(manifest);
  return {
    version: 6,
    schemaVersion: 6,
    ok: true,
    generationId: manifest.generationId,
    revision: manifest.generationId,
    updatedAt: manifest.generatedAt || manifest.sourceUpdatedAt,
    sourceUpdatedAt: manifest.sourceUpdatedAt,
    summary: {
      events: Number(manifest.counts?.echoes || 0),
      totalEvents: Number(manifest.counts?.echoes || 0),
      firstAt: days.at(-1)?.firstAt || null,
      lastAt: days[0]?.lastAt || null,
    },
    facets: manifest.facets || { types: [], players: [] },
    days,
  };
}

function clearV6GenerationCaches() {
  eventDayCache.clear();
  dailyV6Cache.clear();
  eventsV6FullLoadPromise = null;
  eventsFullLoaded = false;
  eventCursor = "";
  eventCurrentPage = 1;
}

function captureV6State() {
  return {
    manifest: eventsManifestV6,
    head: eventsHeadV6,
    mode: eventsContractMode,
    index: eventsIndexSnapshot,
    manifestRevision: dataRevisions.eventsManifestV6,
    headRevision: dataRevisions.eventsHeadV6,
    sourceUpdatedAt: sourceUpdatedAt.get("events"),
    selectedDate: eventSelectedDateKey,
    cursor: eventCursor,
    page: eventCurrentPage,
  };
}

function restoreV6State(state) {
  if (!state) return false;
  eventsManifestV6 = state.manifest || null;
  eventsHeadV6 = state.head || null;
  const complete = Boolean(eventsManifestV6 && eventsHeadV6);
  eventsContractMode = complete ? "v6" : state.mode || "v5";
  eventsIndexSnapshot = state.index || (complete ? v6ManifestAsIndex(eventsManifestV6) : null);
  dataRevisions.eventsManifestV6 = state.manifestRevision || (complete ? String(eventsManifestV6.generationId || "") : "");
  dataRevisions.eventsHeadV6 = state.headRevision || (complete ? String(eventsHeadV6.revision || "") : "");
  eventSelectedDateKey = state.selectedDate || "";
  eventCursor = state.cursor || "";
  eventCurrentPage = Math.max(1, Number(state.page || 1));
  if (state.sourceUpdatedAt) sourceUpdatedAt.set("events", state.sourceUpdatedAt);
  else sourceUpdatedAt.delete("events");
  renderSourceFreshness();
  if (eventsHeadV6) renderHomeLatestEchoes(eventsHeadV6);
  return complete;
}

function renderHomeLatestEchoes(payload) {
  if (!homeLatestEchoes) return;
  const candidates = Array.isArray(payload?.events) ? payload.events : [];
  const recent = sortEventsNewestFirst(candidates, { canonical: Number(payload?.schemaVersion) === 6 }).slice(0, 5);
  homeLatestEchoes.innerHTML = recent.length
    ? recent.map((event, index) => renderEventLineHtml(event, index)).join("")
    : '<li class="event-stream__empty">Aucun écho récent pour le moment.</li>';
  if (homeEchoesStatus) {
    homeEchoesStatus.textContent = recent.length
      ? `${recent.length} écho${recent.length > 1 ? "s" : ""} · mis à jour ${formatRelativeAge(payload?.sourceUpdatedAt || payload?.updatedAt || payload?.generatedAt)}`
      : "Les prochains échos apparaîtront ici.";
  }
}

function currentV6MaxCursor() {
  return Number(eventsManifestV6?.cursor?.maxId || eventsHeadV6?.cursor?.maxId || 0);
}

function terminalUnseenSummary(head, visitCursor, visitTotalEchoes) {
  const events = Array.isArray(head?.events) ? head.events : [];
  const cursor = Number(visitCursor || 0);
  const visibleCount = events.filter((event) => Number(event?.id || 0) > cursor).length;
  const currentTotal = Number(head?.counts?.totalEchoes);
  const previousTotal = Number(visitTotalEchoes);
  const hasVisitTotal = visitTotalEchoes !== null && visitTotalEchoes !== undefined && visitTotalEchoes !== "";
  const hasExactTotal = hasVisitTotal && Number.isFinite(currentTotal) && currentTotal >= 0
    && Number.isFinite(previousTotal) && previousTotal >= 0
    && currentTotal >= previousTotal;
  const exactCount = hasExactTotal ? currentTotal - previousTotal : null;
  const usableExactCount = exactCount != null && (exactCount > 0 || visibleCount === 0) ? exactCount : null;
  const count = usableExactCount ?? visibleCount;
  const minId = Number(head?.windowCursor?.minId || head?.cursor?.minId || 0);
  const saturated = usableExactCount == null && Boolean(head?.hasMore) && cursor > 0 && minId > 0 && cursor < minId;
  return {
    count,
    displayCount: `${Number(count || 0).toLocaleString("fr-CA")}${saturated && count > 0 ? "+" : ""}`,
    saturated,
  };
}

function updateTerminalUnseen() {
  if (!eventUnseen || eventsContractMode !== "v6") return;
  window.clearTimeout(terminalUnseenHideTimer);
  const maxCursor = currentV6MaxCursor();
  if (terminalVisitStartCursor == null) {
    let stored = 0;
    let storedTotal = NaN;
    try {
      stored = Number(localStorage.getItem(terminalVisitCursorStorageKey));
      const rawTotal = localStorage.getItem(terminalVisitTotalStorageKey);
      storedTotal = rawTotal == null ? NaN : Number(rawTotal);
    } catch {
      // Une visite privée peut refuser l’accès au stockage local.
    }
    const hasStoredCursor = Number.isFinite(stored) && stored > 0;
    terminalVisitStartCursor = hasStoredCursor ? stored : maxCursor;
    const currentTotal = Number(eventsHeadV6?.counts?.totalEchoes);
    terminalVisitStartTotalEchoes = Number.isFinite(storedTotal) && storedTotal >= 0
      ? storedTotal
      : !hasStoredCursor && Number.isFinite(currentTotal) && currentTotal >= 0 ? currentTotal : null;
  }
  const unseen = terminalUnseenSummary(eventsHeadV6, terminalVisitStartCursor, terminalVisitStartTotalEchoes);
  if (unseen.count === 0) {
    eventUnseen.hidden = true;
    return;
  }
  eventUnseen.hidden = false;
  if (eventUnseenCount) eventUnseenCount.textContent = `+${unseen.displayCount}`;
  const label = eventUnseen.querySelector("span");
  if (label) {
    label.textContent = unseen.count === 1 ? "écho" : "échos";
  }
  eventUnseen.setAttribute("aria-label", unseen.count === 1 ? "1 ajout dans le journal" : `${unseen.displayCount} ajouts dans le journal`);
  terminalUnseenHideTimer = window.setTimeout(() => {
    eventUnseen.hidden = true;
    markTerminalEchoesSeen();
  }, terminalUnseenToastMs);
}

function markTerminalEchoesSeen() {
  const cursor = currentV6MaxCursor();
  if (!cursor) return;
  terminalVisitStartCursor = cursor;
  const totalEchoes = Number(eventsHeadV6?.counts?.totalEchoes);
  terminalVisitStartTotalEchoes = Number.isFinite(totalEchoes) && totalEchoes >= 0 ? totalEchoes : null;
  try {
    localStorage.setItem(terminalVisitCursorStorageKey, String(cursor));
    if (terminalVisitStartTotalEchoes != null) {
      localStorage.setItem(terminalVisitTotalStorageKey, String(terminalVisitStartTotalEchoes));
    }
  } catch {
    // Le terminal reste fonctionnel lorsque le stockage local est bloqué.
  }
  updateTerminalUnseen();
}

async function fetchEventsV6Candidate(silent = false, force = false) {
  const preferredContract = await loadEventsContractChannel(force);
  if (preferredContract !== "v6") {
    return { ok: false, changed: false, fallback: true, inactive: true };
  }
  if (eventsV6LoadPromise) return eventsV6LoadPromise;
  if (!force && !eventsManifestV6 && Date.now() < eventsV6RetryAfter) {
    return { ok: false, changed: false, fallback: true };
  }

  eventsV6LoadPromise = (async () => {
    try {
      let pointer = null;
      try {
        pointer = await readJson("data/public-events-head-v6.json", { revalidate: true });
      } catch (error) {
        if (!String(error?.message || "").includes("HTTP 404")) throw error;
      }
      if (pointer) {
        const pointerGeneration = String(pointer.baseGenerationId || "");
        const pointerManifestPath = v6PublicDataPath(pointer.manifest?.path, `data/public-events-v6/${pointerGeneration}/`);
        const expectedManifestPath = `data/public-events-v6/${pointerGeneration}/manifest.json`;
        if (
          !pointer.ok
          || Number(pointer.schemaVersion) !== 6
          || !/^[A-Za-z0-9._-]+$/.test(pointerGeneration)
          || pointerManifestPath !== expectedManifestPath
          || !v6Sha256IsValid(pointer.manifest?.sha256)
          || !v6Sha256IsValid(pointer.head?.sha256)
        ) throw new Error("invalid-v6-active-pointer");
        if (
          eventsManifestV6
          && eventsHeadV6
          && String(eventsManifestV6.generationId || "") === pointerGeneration
          && String(eventsHeadV6.revision || "") === String(pointer.head?.revision || pointer.revision || "")
        ) {
          eventsActivePointerV6 = pointer;
          return {
            ok: true,
            manifest: eventsManifestV6,
            head: eventsHeadV6,
            generationId: pointerGeneration,
            mode: "v6",
            unchanged: true,
          };
        }
      }
      const manifest = pointer
        ? await readJson(pointer.manifest.path, { immutable: true, expectedSha256: pointer.manifest.sha256 })
        : await readJson("data/public-events-manifest-v6.json", { revalidate: true });
      const generationId = String(manifest?.generationId || "");
      const rawDays = Array.isArray(manifest?.days) ? manifest.days : [];
      const days = v6ManifestDays(manifest);
      const incompleteDay = days.some((entry) => !v6PublicDataPath(entry.dailyPath, "data/public-daily/") || !v6Sha256IsValid(entry.sha256) || !v6Sha256IsValid(entry.dailySha256));
      if (!manifest?.ok || Number(manifest.schemaVersion) !== 6 || !/^[A-Za-z0-9._-]+$/.test(generationId) || days.length !== rawDays.length || incompleteDay) {
        throw new Error("invalid-v6-manifest");
      }
      const expectedHeadPath = `data/public-events-v6/${generationId}/head.json`;
      const headPath = v6PublicDataPath(manifest.head?.path, `data/public-events-v6/${generationId}/`);
      if (headPath !== expectedHeadPath || !v6Sha256IsValid(manifest.head?.sha256)) throw new Error("invalid-v6-head-path");
      if (
        pointer
        && (
          String(pointer.baseGenerationId || "") !== generationId
          || pointer.head?.path !== manifest.head?.path
          || pointer.head?.sha256 !== manifest.head?.sha256
          || String(pointer.head?.revision || "") !== String(manifest.head?.revision || "")
        )
      ) throw new Error("mixed-v6-active-pointer");
      const head = await readJson(headPath, { immutable: true, expectedSha256: manifest.head.sha256 });
      if (!v6GenerationIsValid(head, generationId, true)) throw new Error("mixed-v6-generation");
      eventsActivePointerV6 = pointer;
      eventsV6RetryAfter = 0;
      return { ok: true, manifest, head, generationId, mode: "v6" };
    } catch (error) {
      if (eventsManifestV6 && eventsHeadV6) {
        return {
          ok: true,
          manifest: eventsManifestV6,
          head: eventsHeadV6,
          generationId: String(eventsManifestV6.generationId || ""),
          mode: "v6",
          stale: true,
          error,
        };
      }
      eventsV6RetryAfter = Date.now() + 5 * 60 * 1000;
      if (!silent) console.info("Le journal v6 n’est pas encore publié; repli sur le journal actuel.");
      return { ok: false, changed: false, fallback: true, error };
    } finally {
      eventsV6LoadPromise = null;
    }
  })();
  return eventsV6LoadPromise;
}

async function loadEventsContractChannel(force = false) {
  if (!force && eventsContractChannelCheckedAt && Date.now() - eventsContractChannelCheckedAt < refreshEveryMs - 500) {
    return eventsPreferredContract;
  }
  if (eventsContractChannelPromise) return eventsContractChannelPromise;

  eventsContractChannelPromise = (async () => {
    try {
      const payload = await readJson("public-events-channel.json", { revalidate: true });
      const activeContract = String(payload?.activeContract || "").toLocaleLowerCase("en-CA");
      if (Number(payload?.schemaVersion) !== 1 || !["v5", "v6"].includes(activeContract)) {
        throw new Error("invalid-events-contract-channel");
      }
      const changed = activeContract !== eventsPreferredContract;
      eventsPreferredContract = activeContract;
      eventsContractChannelCheckedAt = Date.now();
      if (changed && activeContract === "v5" && eventsContractMode === "v6") {
        eventsContractMode = "v5";
        eventsManifestV6 = null;
        eventsHeadV6 = null;
        eventsActivePointerV6 = null;
        eventsSnapshot = null;
        eventsIndexSnapshot = null;
        eventsRecentSnapshot = null;
        eventsFullLoaded = false;
        eventsFullLoadPromise = null;
        clearV6GenerationCaches();
      }
      return eventsPreferredContract;
    } catch {
      eventsContractChannelCheckedAt = Date.now();
      return eventsPreferredContract;
    } finally {
      eventsContractChannelPromise = null;
    }
  })();

  return eventsContractChannelPromise;
}

function commitEventsV6Candidate(candidate) {
  if (!candidate?.ok || !candidate.manifest || !candidate.head) throw new Error("invalid-v6-candidate");
  const previousGeneration = String(eventsManifestV6?.generationId || "");
  const previousHeadRevision = String(eventsHeadV6?.revision || "");
  const generationId = String(candidate.manifest.generationId || "");
  const headRevision = String(candidate.head.revision || candidate.head.cursor?.maxId || candidate.head.generatedAt || "");
  eventsManifestV6 = candidate.manifest;
  eventsHeadV6 = candidate.head;
  eventsContractMode = "v6";
  eventsIndexSnapshot = v6ManifestAsIndex(candidate.manifest);
  dataRevisions.eventsManifestV6 = generationId;
  dataRevisions.eventsHeadV6 = headRevision;
  registerPayloadDataUpdate("events", candidate.head);
  renderHomeLatestEchoes(candidate.head);
  updateTerminalUnseen();
  return {
    ok: true,
    changed: previousGeneration !== generationId || previousHeadRevision !== headRevision,
    generationChanged: Boolean(previousGeneration && previousGeneration !== generationId),
    stale: Boolean(candidate.stale),
    mode: "v6",
  };
}

async function stageAndCommitV6Candidate(candidate, loadPayload, commitCandidate) {
  const payload = await loadPayload();
  const state = commitCandidate(candidate);
  return { payload, state };
}

async function loadEventsV6State(silent = false, force = false) {
  const candidate = await fetchEventsV6Candidate(silent, force);
  if (!candidate.ok) {
    if (!eventsManifestV6 || !eventsHeadV6) eventsContractMode = "v5";
    return candidate;
  }
  return commitEventsV6Candidate(candidate);
}

function mergeV6DayWithHead(dayPayload, dateKey, manifest = eventsManifestV6, head = eventsHeadV6) {
  const activeGenerationId = String(manifest?.generationId || "");
  const headEvents = head && String(head.baseGenerationId) === activeGenerationId
    ? (head.events || []).filter((event) => dailyDateKeyFromDate(parseDate(event?.occurredAt)) === dateKey)
    : [];
  const byKey = new Map();
  [...(dayPayload.events || []), ...headEvents].forEach((event, index) => {
    byKey.set(eventIdentity(event) || `v6:${index}`, event);
  });
  const events = sortEventsNewestFirst([...byKey.values()], { canonical: true });
  return {
    ...dayPayload,
    version: 6,
    activeGenerationId,
    revision: `${activeGenerationId}:${dayPayload.generationId}:${dateKey}:${head?.revision || dayPayload.contentHash || ""}`,
    updatedAt: head?.sourceUpdatedAt || dayPayload.sourceUpdatedAt || dayPayload.generatedAt,
    summary: {
      events: events.length,
      totalEvents: events.length,
      firstAt: events.at(-1)?.occurredAt || null,
      lastAt: events[0]?.occurredAt || null,
    },
    events,
  };
}

async function loadEventDayV6(dateKey, manifest = eventsManifestV6, head = eventsHeadV6) {
  const entry = v6DayEntry(dateKey, manifest);
  if (!manifest?.generationId || !v6DateCanBeOpened(dateKey, manifest)) throw new Error("v6-day-unavailable");
  if (!entry) {
    return mergeV6DayWithHead({
      schemaVersion: 6,
      ok: true,
      generationId: String(manifest.generationId),
      date: dateKey,
      generatedAt: manifest.generatedAt,
      sourceUpdatedAt: manifest.sourceUpdatedAt,
      freshness: manifest.freshness,
      sourceStatus: manifest.sourceStatus,
      cursor: { minId: 0, maxId: 0 },
      counts: { echoes: 0, representedEvents: 0, confirmedEchoes: 0, derivedEchoes: 0 },
      contentHash: `empty:${dateKey}`,
      events: [],
    }, dateKey, manifest, head);
  }
  const generationId = String(entry.fragmentGenerationId || entry.generationId || manifest.generationId);
  const cacheKey = `${generationId}:${entry.path}:${dateKey}`;
  let payload = eventDayCache.get(cacheKey);
  if (!payload) {
    payload = await readJson(v6PublicDataPath(entry.path, "data/public-events-v6/"), {
      immutable: true,
      expectedSha256: entry.sha256,
    });
    if (!v6GenerationIsValid(payload, generationId) || payload.date !== dateKey || !Array.isArray(payload.events)) {
      throw new Error("mixed-v6-day-generation");
    }
    eventDayCache.set(cacheKey, payload);
  }
  return mergeV6DayWithHead(payload, dateKey, manifest, head);
}

function v6ManifestTotalEchoes(manifest = eventsManifestV6, head = eventsHeadV6) {
  const total = Number(manifest?.counts?.echoes ?? head?.counts?.totalEchoes ?? 0);
  return Number.isFinite(total) && total >= 0 ? total : 0;
}

function dedupeV6Events(events) {
  const byKey = new Map();
  (Array.isArray(events) ? events : []).filter(eventCanBePublished).forEach((event, index) => {
    byKey.set(eventIdentity(event) || `v6:${index}`, event);
  });
  return sortEventsNewestFirst([...byKey.values()], { canonical: true });
}

function v6TerminalPayloadFromEvents(events, options = {}) {
  const manifest = options.manifest || eventsManifestV6;
  const head = options.head || eventsHeadV6;
  const generationId = String(manifest?.generationId || head?.baseGenerationId || "");
  const sortedEvents = dedupeV6Events(events);
  const totalEchoes = v6ManifestTotalEchoes(manifest, head) || sortedEvents.length;
  return {
    schemaVersion: 6,
    version: 6,
    ok: true,
    terminalFull: Boolean(options.full),
    terminalHead: !options.full,
    generationId,
    activeGenerationId: generationId,
    revision: `${generationId}:${head?.revision || manifest?.generatedAt || ""}:${options.full ? "terminal-full" : "terminal-window"}`,
    generatedAt: manifest?.generatedAt || head?.generatedAt,
    sourceUpdatedAt: head?.sourceUpdatedAt || manifest?.sourceUpdatedAt,
    updatedAt: head?.sourceUpdatedAt || manifest?.sourceUpdatedAt || manifest?.generatedAt || head?.generatedAt,
    freshness: manifest?.freshness || head?.freshness,
    sourceStatus: manifest?.sourceStatus || head?.sourceStatus,
    summary: {
      events: sortedEvents.length,
      totalEvents: totalEchoes,
      firstAt: sortedEvents.at(-1)?.occurredAt || null,
      lastAt: sortedEvents[0]?.occurredAt || null,
    },
    counts: {
      ...(head?.counts || {}),
      echoes: sortedEvents.length,
      totalEchoes,
    },
    events: sortedEvents,
  };
}

async function loadFullTerminalEventsV6(force = false) {
  const generationId = String(eventsManifestV6?.generationId || eventsHeadV6?.baseGenerationId || "");
  if (!generationId) throw new Error("v6-terminal-full-unavailable");
  if (!force && eventsFullLoaded && eventsSnapshot?.schemaVersion === 6 && String(eventsSnapshot.activeGenerationId || "") === generationId) {
    return eventsSnapshot;
  }
  if (eventsV6FullLoadPromise) return eventsV6FullLoadPromise;

  eventsV6FullLoadPromise = (async () => {
    const days = v6ManifestDays(eventsManifestV6);
    const payloads = await Promise.all(days.map((entry) => loadEventDayV6(entry.date, eventsManifestV6, eventsHeadV6)));
    const payload = v6TerminalPayloadFromEvents(payloads.flatMap((day) => day.events || []), {
      manifest: eventsManifestV6,
      head: eventsHeadV6,
      full: true,
    });
    eventsSnapshot = payload;
    eventsFullLoaded = true;
    renderEventSummaryCards(payload);
    renderEventSyncStatus(new Date(), payload.updatedAt);
    return payload;
  })().finally(() => {
    eventsV6FullLoadPromise = null;
  });

  return eventsV6FullLoadPromise;
}

async function collectPagedTerminalEventsV6() {
  const totalEvents = v6ManifestTotalEchoes();
  const pageSize = terminalV6EchoLimit;
  const pageCount = Math.max(1, Math.ceil(totalEvents / pageSize));
  eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), pageCount);
  const start = (eventCurrentPage - 1) * pageSize;
  const end = Math.min(start + pageSize, totalEvents);
  const rows = [];
  let offset = 0;

  for (const entry of v6ManifestDays(eventsManifestV6)) {
    const dayCount = Math.max(0, Number(entry.events ?? entry.echoes ?? 0));
    const nextOffset = offset + dayCount;
    if (dayCount > 0 && nextOffset > start && offset < end) {
      const payload = await loadEventDayV6(entry.date, eventsManifestV6, eventsHeadV6);
      const localStart = Math.max(0, start - offset);
      const localEnd = Math.min(payload.events.length, end - offset);
      rows.push(...payload.events.slice(localStart, localEnd));
    }
    offset = nextOffset;
    if (offset >= end) break;
  }

  return dedupeV6Events(rows).slice(0, pageSize);
}

async function renderPagedTerminalEventsV6(options = {}) {
  if (!isTerminalRoute() || eventsContractMode !== "v6" || !eventsManifestV6 || !eventsHeadV6) return false;
  const preserveViewport = Boolean(options.preserveViewport);
  const streamTopBefore = preserveViewport ? eventStream?.getBoundingClientRect().top : null;
  const totalEvents = v6ManifestTotalEchoes();
  const pageCount = Math.max(1, Math.ceil(totalEvents / terminalV6EchoLimit));
  eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), pageCount);

  const canKeepCurrentRows = Boolean(options.preserveDom && eventStream?.querySelector(".event-line"));
  if (!canKeepCurrentRows && eventStream) {
    eventStream.innerHTML = '<li class="event-stream__empty">Chargement des échos...</li>';
  }

  const visible = await collectPagedTerminalEventsV6();
  terminalEventWindowStart = (eventCurrentPage - 1) * terminalV6EchoLimit;
  terminalVisibleEvents = visible;
  if (eventResultCount) {
    const label = `${dailyPlural(visible.length, "écho affiché", "échos affichés")} · ${formatInteger(totalEvents)} synchronisés`;
    eventResultCount.textContent = pageCount > 1 ? `${label} · page ${eventCurrentPage} sur ${pageCount}` : label;
  }
  renderEventStreamItems(visible, true, false, { preserveDom: Boolean(options.preserveDom) });
  renderEventPaginationControls(pageCount);
  if (preserveViewport && Number.isFinite(streamTopBefore)) {
    const streamTopAfter = eventStream?.getBoundingClientRect().top;
    if (Number.isFinite(streamTopAfter)) {
      window.scrollBy({ top: streamTopAfter - streamTopBefore, behavior: "auto" });
    }
  }
  return true;
}

function v6HeadAsTerminalPayload(head, manifest = eventsManifestV6) {
  const generationId = String(manifest?.generationId || head?.baseGenerationId || "");
  if (!v6GenerationIsValid(head, generationId, true)) throw new Error("mixed-v6-terminal-head");
  const events = sortEventsNewestFirst((head.events || []).filter(eventCanBePublished), { canonical: true })
    .slice(0, terminalV6EchoLimit);
  const totalEchoes = Number(manifest?.counts?.echoes ?? head?.counts?.totalEchoes ?? events.length);
  return {
    ...head,
    version: 6,
    schemaVersion: 6,
    ok: true,
    recent: true,
    terminalHead: true,
    generationId,
    activeGenerationId: generationId,
    revision: `${generationId}:${head.revision || head.cursor?.maxId || head.generatedAt || ""}:terminal-head`,
    updatedAt: head.sourceUpdatedAt || head.generatedAt || manifest?.sourceUpdatedAt || manifest?.generatedAt,
    summary: {
      events: events.length,
      totalEvents: Number.isFinite(totalEchoes) && totalEchoes >= 0 ? totalEchoes : events.length,
      firstAt: events.at(-1)?.occurredAt || null,
      lastAt: events[0]?.occurredAt || null,
    },
    counts: {
      ...(head.counts || {}),
      echoes: events.length,
      totalEchoes: Number.isFinite(totalEchoes) && totalEchoes >= 0 ? totalEchoes : events.length,
    },
    events,
  };
}

function renderEventDateControls() {
  if (!eventDateNavigation || !isDailyDigestRoute()) return;
  const dates = v6NavigableDates();
  const index = dates.indexOf(eventSelectedDateKey);
  eventDateNavigation.hidden = eventsContractMode !== "v6";
  if (eventDateInput) {
    eventDateInput.value = eventSelectedDateKey || "";
    eventDateInput.min = dates.at(-1) || "";
    eventDateInput.max = dailyDateKeyFromDate(new Date()) || dates[0] || "";
  }
  if (eventDatePrevious) eventDatePrevious.disabled = index < 0 || index >= dates.length - 1;
  if (eventDateNext) eventDateNext.disabled = index <= 0;
  if (eventDateToday) eventDateToday.disabled = eventSelectedDateKey === dailyDateKeyFromDate(new Date());
}

async function loadTerminalEventsV6(silent = false) {
  const rollbackState = captureV6State();
  const previousRevision = eventsSnapshot?.revision || "";
  const hadFullGeneration = eventsFullLoaded && String(eventsSnapshot?.activeGenerationId || "") === String(eventsManifestV6?.generationId || "");
  const shouldPreserveView = Boolean(silent && (terminalFiltersAreActive() || eventCurrentPage > 1));
  try {
    const candidate = await fetchEventsV6Candidate(silent, true);
    if (!candidate.ok) return candidate;
    const { payload, state } = await stageAndCommitV6Candidate(
      candidate,
      () => Promise.resolve(v6HeadAsTerminalPayload(candidate.head, candidate.manifest)),
      commitEventsV6Candidate,
    );
    eventSelectedDateKey = "";
    eventCursor = "";
    if (state.generationChanged) clearV6GenerationCaches();
    if (!shouldPreserveView) eventCurrentPage = 1;
    eventsSnapshot = payload;
    eventsRecentSnapshot = payload;
    eventsFullLoaded = false;
    renderEventSummaryCards(payload);
    renderEventSyncStatus(new Date(), payload.updatedAt);
    renderEventFiltersFromFacets(eventsIndexSnapshot);
    eventDateNavigation?.setAttribute("hidden", "");
    if (terminalFiltersAreActive() || hadFullGeneration) {
      await loadFullTerminalEventsV6(state.generationChanged);
      renderEvents(false, { preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
    } else if (eventCurrentPage > 1) {
      await renderPagedTerminalEventsV6({ preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
    } else {
      renderEvents(false, { preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
    }
    updateTerminalUnseen();
    return { ok: true, changed: state.changed || previousRevision !== payload.revision, mode: "v6" };
  } catch (error) {
    const restored = restoreV6State(rollbackState);
    if (restored) {
      if (eventsSnapshot?.version === 6 && String(eventsSnapshot.activeGenerationId || "") === String(eventsManifestV6?.generationId || "")) {
        eventDateNavigation?.setAttribute("hidden", "");
        return { ok: true, changed: false, stale: true, error, mode: "v6" };
      }
      try {
        eventSelectedDateKey = "";
        eventCursor = "";
        if (!shouldPreserveView) eventCurrentPage = 1;
        const payload = v6HeadAsTerminalPayload(eventsHeadV6, eventsManifestV6);
        eventsSnapshot = payload;
        eventsRecentSnapshot = payload;
        eventsFullLoaded = false;
        renderEventSummaryCards(payload);
        renderEventSyncStatus(new Date(), payload.updatedAt);
        renderEventFiltersFromFacets(eventsIndexSnapshot);
        eventDateNavigation?.setAttribute("hidden", "");
        if (terminalFiltersAreActive() || hadFullGeneration) {
          await loadFullTerminalEventsV6(false);
          renderEvents(false, { preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
        } else if (eventCurrentPage > 1) {
          await renderPagedTerminalEventsV6({ preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
        } else {
          renderEvents(false, { preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
        }
        updateTerminalUnseen();
        return { ok: true, changed: false, stale: true, error, mode: "v6" };
      } catch {
        // Le repli v5 reste disponible si la dernière génération complète n’est plus lisible.
      }
    }
    return { ok: false, changed: false, fallback: true, error };
  }
}

async function selectEventDate(dateKey, updateUrl = true) {
  if (!v6DateCanBeOpened(dateKey)) return;
  const previousDate = eventSelectedDateKey;
  try {
    const payload = await loadEventDayV6(dateKey);
    eventSelectedDateKey = dateKey;
    eventCursor = "";
    eventCurrentPage = 1;
    eventsSnapshot = payload;
    renderEventSummaryCards(payload);
    renderEventSyncStatus(new Date(), payload.updatedAt);
    renderEventDateControls();
    renderEvents();
    if (updateUrl) writeTerminalState();
  } catch {
    eventSelectedDateKey = previousDate;
    renderEventDateControls();
    announceDataUpdate("Cette journée n’a pas pu être chargée. La journée déjà ouverte reste affichée.");
  }
}

async function loadHomeEchoes(silent = false) {
  const v6 = await loadEventsV6State(true, true);
  if (v6.ok && eventsHeadV6) return v6;
  try {
    const payload = await readJson("data/public-events-recent.json");
    renderHomeLatestEchoes(payload);
    registerPayloadDataUpdate("events", payload);
    return { ok: true, changed: isNewDataRevision("events", payload), mode: "v5" };
  } catch {
    if (!silent && homeEchoesStatus) homeEchoesStatus.textContent = "Les échos sont momentanément indisponibles.";
    return { ok: false, changed: false };
  }
}

async function loadTerminalEventsPreferred(silent = false) {
  const v6 = await loadTerminalEventsV6(true);
  if (v6.ok && eventsContractMode === "v6") return v6;
  eventDateNavigation?.setAttribute("hidden", "");
  const fallback = eventFiltersRequireFullHistory()
    ? await loadEventsWithRecentOverlay(silent)
    : await loadEventsIndex(silent);
  if (fallback.ok && !eventsFullLoaded && eventsIndexSnapshot) {
    await renderPagedTerminalEvents(false, { preserveDom: Boolean(silent), preserveViewport: Boolean(silent) });
  }
  return { ...fallback, mode: "v5" };
}

function primaryEventRevision(payload) {
  if (!payload || payload.recent) return "";
  return String(payload.sourceRevision || payload.revision || "").split("+")[0];
}

function recentEventRevision(payload) {
  if (!payload) return "";
  const explicit = String(payload.recentRevision || "");
  if (explicit) return explicit;
  if (payload.recent) return String(payload.revision || "");
  const parts = String(payload.revision || "").split("+").filter(Boolean);
  return parts.length > 1 ? parts.at(-1) : "";
}

function v5TailReplacementWindow(basePayload, overlayPayload) {
  const baseVersion = Number(basePayload?.schemaVersion || basePayload?.version || 0);
  const overlayVersion = Number(overlayPayload?.schemaVersion || overlayPayload?.version || 0);
  const window = overlayPayload?.projectionWindow;
  if (
    baseVersion !== 5
    || overlayVersion !== 5
    || !overlayPayload?.recent
    || window?.mode !== "replace-tail"
    || window?.complete !== true
  ) return null;

  const replaceAt = parseDate(window.replaceFrom);
  const baseRevision = Number(basePayload?.projectionRevision);
  const fromRevision = Number(window.fromProjectionRevision);
  const throughRevision = Number(window.throughProjectionRevision);
  const overlayRevision = Number(overlayPayload?.projectionRevision);
  if (
    !replaceAt
    || !Number.isInteger(baseRevision)
    || !Number.isInteger(fromRevision)
    || !Number.isInteger(throughRevision)
    || !Number.isInteger(overlayRevision)
    || baseRevision >= throughRevision
    || fromRevision >= throughRevision
    || overlayRevision !== throughRevision
  ) return null;

  return {
    replaceAt,
    replaceFrom: String(window.replaceFrom),
    fromRevision,
    throughRevision,
    fullyCovered: baseRevision >= fromRevision,
  };
}

function mergeV5PagedTailEvents(baseEvents, basePayload, overlayPayload) {
  const replacement = v5TailReplacementWindow(basePayload, overlayPayload);
  const coldEvents = dedupeSessionFallbackEvents(baseEvents);
  if (!replacement) return coldEvents;

  const byKey = new Map();
  coldEvents.forEach((event, index) => {
    const occurredAt = parseDate(event?.occurredAt);
    if (occurredAt && occurredAt >= replacement.replaceAt) return;
    byKey.set(eventIdentity(event) || `cold:${index}`, event);
  });
  dedupeSessionFallbackEvents(overlayPayload?.events).forEach((event, index) => {
    const occurredAt = parseDate(event?.occurredAt);
    if (!occurredAt || occurredAt < replacement.replaceAt) return;
    byKey.set(eventIdentity(event) || `recent:${index}`, event);
  });
  return sortEventsNewestFirst([...byKey.values()], { canonical: true });
}

function mergeEventPayloads(basePayload, overlayPayload) {
  const replacement = v5TailReplacementWindow(basePayload, overlayPayload);
  const baseEvents = dedupeSessionFallbackEvents(basePayload?.events).filter((event) => {
    if (!replacement) return true;
    const occurredAt = parseDate(event?.occurredAt);
    return !occurredAt || occurredAt < replacement.replaceAt;
  });
  const overlayEvents = dedupeSessionFallbackEvents(overlayPayload?.events);
  const baseRevision = primaryEventRevision(basePayload);
  const overlayRevision = recentEventRevision(overlayPayload) || recentEventRevision(basePayload);
  if (!overlayEvents.length) {
    return {
      ...basePayload,
      events: baseEvents,
      sourceRevision: baseRevision,
      recentRevision: overlayRevision,
      projectionRevision: replacement?.throughRevision ?? basePayload?.projectionRevision,
      projectionWindow: replacement ? overlayPayload.projectionWindow : basePayload?.projectionWindow,
      revision: [baseRevision || basePayload?.revision, overlayRevision].filter(Boolean).join("+"),
      summary: {
        ...(basePayload?.summary || {}),
        events: baseEvents.length,
        firstAt: baseEvents.at(-1)?.occurredAt || null,
        lastAt: baseEvents[0]?.occurredAt || null,
      },
    };
  }

  const byKey = new Map();
  baseEvents.forEach((event, index) => byKey.set(eventIdentity(event) || `base:${index}`, event));
  overlayEvents.forEach((event, index) => byKey.set(eventIdentity(event) || `recent:${index}`, event));
  const events = sortEventsNewestFirst([...byKey.values()]);
  const baseTotal = Number(basePayload?.summary?.totalEvents || basePayload?.summary?.events || baseEvents.length || 0);
  const overlayTotal = Number(overlayPayload?.summary?.totalEvents || overlayPayload?.summary?.events || overlayEvents.length || 0);
  const latestUpdatedAt = latestDateValue(basePayload?.updatedAt, overlayPayload?.updatedAt)?.toISOString();

  return {
    ...basePayload,
    ok: true,
    version: Math.max(Number(basePayload?.version || 0), Number(overlayPayload?.version || 0)),
    sourceRevision: baseRevision,
    recentRevision: overlayRevision,
    projectionRevision: replacement?.throughRevision ?? basePayload?.projectionRevision,
    projectionWindow: replacement ? overlayPayload.projectionWindow : basePayload?.projectionWindow,
    revision: [baseRevision || basePayload?.revision, overlayRevision].filter(Boolean).join("+"),
    updatedAt: latestUpdatedAt || basePayload?.updatedAt || overlayPayload?.updatedAt || new Date().toISOString(),
    summary: {
      ...(basePayload?.summary || {}),
      totalEvents: Math.max(baseTotal, overlayTotal, events.length),
      events: events.length,
      firstAt: events.at(-1)?.occurredAt || null,
      lastAt: events[0]?.occurredAt || null,
    },
    events,
  };
}

function renderEventFilterOptions(types, players) {
  const selectedType = selectedEventTypeValue();
  const selectedPlayer = selectedEventPlayerValue();
  if (selectedType !== "all" && !types.includes(selectedType)) types = [selectedType, ...types];
  if (selectedPlayer !== "all" && !players.includes(selectedPlayer)) players = [selectedPlayer, ...players];

  if (eventTypeFilter) eventTypeFilter.innerHTML = [
    '<option value="all">Tous les événements</option>',
    ...types.map((type) => `<option value="${escapeHtml(type)}">${escapeHtml(eventTypeMeta[type]?.label || type)}</option>`),
  ].join("");
  if (eventPlayerFilter) eventPlayerFilter.innerHTML = [
    '<option value="all">Tous les aventuriers</option>',
    ...players.map((player) => `<option value="${escapeHtml(player)}">${escapeHtml(player)}</option>`),
  ].join("");
  if (eventTypeFilter && types.includes(selectedType)) eventTypeFilter.value = selectedType;
  if (eventPlayerFilter && players.includes(selectedPlayer)) eventPlayerFilter.value = selectedPlayer;
  if (eventTypeFilter) delete eventTypeFilter.dataset.pendingValue;
  if (eventPlayerFilter) delete eventPlayerFilter.dataset.pendingValue;
}

function renderEventFilters(events) {
  events = dedupeSessionFallbackEvents(events);
  const types = [...new Set(events.map((event) => event.type).filter(Boolean))];
  const players = [...new Set(events.map((event) => event.player).filter(Boolean))]
    .sort((left, right) => left.localeCompare(right, "fr-CA"));

  renderEventFilterOptions(types, players);
}

function renderEventFiltersFromFacets(payload) {
  const recentEvents = dedupeSessionFallbackEvents(eventsRecentSnapshot?.events || (!eventsFullLoaded ? eventsSnapshot?.events : []));
  const types = [...new Set([
    ...(payload?.facets?.types || [])
    .map((facet) => typeof facet === "string" ? facet : facet?.value)
    .filter(Boolean),
    ...recentEvents.map((event) => event.type).filter(Boolean),
  ])];
  const players = [...new Set([
    ...(payload?.facets?.players || [])
    .map((facet) => typeof facet === "string" ? facet : facet?.value)
    .filter(Boolean),
    ...recentEvents.map((event) => event.player).filter(Boolean),
  ])]
    .sort((left, right) => left.localeCompare(right, "fr-CA"));

  renderEventFilterOptions(types, players);
}

function eventFiltersRequireFullHistory() {
  return Boolean(
    normalizeEventSearch(eventSearch?.value) ||
    selectedEventTypeValue() !== "all" ||
    selectedEventPlayerValue() !== "all"
  );
}

function eventPageNumbers(current, total) {
  const visibleCount = Math.min(3, total);
  const start = clamp(current - 1, 1, Math.max(1, total - visibleCount + 1));
  return Array.from({ length: visibleCount }, (_, index) => start + index);
}

function estimateTerminalEventRowHeight() {
  const renderedLine = eventStream?.querySelector(".event-line");
  if (renderedLine) {
    return clamp(renderedLine.getBoundingClientRect().height + 1, 62, 148);
  }
  if (window.innerWidth <= 650) return 94;
  if (window.innerWidth <= 980) return 78;
  return 68;
}

function calculateTerminalPageSize() {
  if (!isTerminalRoute() || !eventStream) return terminalEventPageSize;
  return clamp(Math.floor(terminalStreamAvailableHeight() / estimateTerminalEventRowHeight()), 1, 18);
}

function updateTerminalPageSize(preserveFirstItem = false) {
  if (!isTerminalRoute()) return false;
  const previous = terminalEventPageSize;
  const firstVisibleIndex = Math.max(0, (eventCurrentPage - 1) * previous);
  terminalEventPageSize = calculateTerminalPageSize();
  if (preserveFirstItem && previous !== terminalEventPageSize) {
    eventCurrentPage = Math.floor(firstVisibleIndex / terminalEventPageSize) + 1;
  }
  return previous !== terminalEventPageSize;
}

function refineRenderedTerminalPageSize() {
  if (!isTerminalRoute() || !eventStream) return false;
  const rows = [...eventStream.querySelectorAll(".event-line")];
  if (!rows.length) return false;
  const averageRowHeight = rows.reduce((sum, row) => sum + row.getBoundingClientRect().height, 0) / rows.length;
  const next = clamp(Math.floor(terminalStreamAvailableHeight() / Math.max(averageRowHeight, 1)), 1, 18);
  if (next === terminalEventPageSize) return false;
  terminalEventPageSize = next;
  return true;
}

function terminalStreamAvailableHeight() {
  if (!eventStream) return 0;
  const streamTop = eventStream.getBoundingClientRect().top;
  const paginationHeight = eventPagination?.getBoundingClientRect().height || 58;
  const bottomGap = window.innerWidth <= 720 ? 86 : 18;
  return Math.max(160, window.innerHeight - streamTop - paginationHeight - bottomGap);
}

function readTerminalState() {
  if (!isTerminalRoute()) return;
  const saved = JSON.parse(localStorage.getItem("gaylemon-terminal-filters") || "{}");
  const params = new URLSearchParams(location.search);
  const values = {
    q: params.get("q") ?? saved.q ?? "",
    type: params.get("type") ?? saved.type ?? "all",
    player: params.get("player") ?? saved.player ?? "all",
    page: Number(params.get("page") || saved.page || 1),
    cursor: params.get("cursor") ?? saved.cursor ?? "",
  };
  if (eventSearch) eventSearch.value = values.q;
  if (eventTypeFilter) {
    eventTypeFilter.dataset.pendingValue = values.type;
    eventTypeFilter.value = values.type;
  }
  if (eventPlayerFilter) {
    eventPlayerFilter.dataset.pendingValue = values.player;
    eventPlayerFilter.value = values.player;
  }
  eventCurrentPage = Math.max(1, values.page || 1);
  eventSelectedDateKey = "";
  eventCursor = values.cursor || "";
  syncEventControlsState();
  updateTerminalPageSize();
}

function terminalFiltersAreActive() {
  return Boolean(
    normalizeEventSearch(eventSearch?.value) ||
    selectedEventTypeValue() !== "all" ||
    selectedEventPlayerValue() !== "all"
  );
}

function syncEventControlsState() {
  if (!eventControls) return;
  const active = terminalFiltersAreActive();
  eventControls.classList.toggle("has-active-filters", active);
}

function writeTerminalState() {
  if (!isTerminalRoute()) return;
  const state = {
    q: eventSearch?.value || "",
    type: selectedEventTypeValue(),
    player: selectedEventPlayerValue(),
    page: eventCurrentPage,
    cursor: eventCursor,
  };
  localStorage.setItem("gaylemon-terminal-filters", JSON.stringify(state));
  const params = new URLSearchParams();
  if (state.q) params.set("q", state.q);
  for (const key of ["type", "player"]) {
    if (state[key] && state[key] !== "all") params.set(key, state[key]);
  }
  if (state.page > 1) {
    params.set("page", String(state.page));
  }
  const query = params.toString();
  history.replaceState(null, "", `/terminal${query ? `?${query}` : ""}`);
}

function elementFromHtml(html) {
  const template = document.createElement("template");
  template.innerHTML = html.trim();
  return template.content.firstElementChild;
}

function eventRenderSignature(event) {
  return shortStableHash(JSON.stringify([
    event?.occurredAt || "",
    event?.type || "",
    event?.player || "",
    event?.base || "",
    event?.icon || "",
    event?.title || "",
    event?.message || "",
    event?.display?.headline || "",
    event?.display?.body || "",
    event?.confidence || "confirmed",
    event?.details?.windowMinutes || 0,
    ...(event?.display?.bullets || []),
  ]));
}

function renderEventStreamItems(visible, terminal, refinePageSize, options = {}) {
  if (!eventStream) return false;
  if (!visible.length) {
    eventStream.innerHTML = '<li class="event-stream__empty">Aucun écho ne correspond à cette recherche.</li>';
    return false;
  }

  const rendered = visible.map((event, index) => ({
    key: eventIdentity(event) || `visible:${index}`,
    signature: eventRenderSignature(event),
    html: renderEventLineHtml(event, index),
  }));

  if (!options.preserveDom) {
    eventStream.innerHTML = rendered.map((item) => item.html).join("");
    return Boolean(terminal && eventsContractMode !== "v6" && refinePageSize && refineRenderedTerminalPageSize());
  }

  const existingLines = new Map(
    [...eventStream.querySelectorAll(".event-line[data-event-key]")].map((line) => [line.dataset.eventKey, line]),
  );
  const nextNodes = rendered.map((item) => {
    const existing = existingLines.get(item.key);
    if (existing && existing.dataset.eventRender === item.signature) return existing;
    const node = elementFromHtml(item.html);
    if (terminal && !prefersReducedMotion.matches) {
      node.classList.add("event-line--new");
    }
    return node;
  }).filter(Boolean);

  eventStream.replaceChildren(...nextNodes);
  if (terminal && !prefersReducedMotion.matches) {
    window.requestAnimationFrame(() => {
      eventStream.querySelectorAll(".event-line--new").forEach((line) => {
        line.classList.remove("event-line--new");
      });
    });
  }
  return Boolean(terminal && eventsContractMode !== "v6" && refinePageSize && refineRenderedTerminalPageSize());
}

function renderEventLineHtml(event, index = 0) {
    const meta = eventTypeMeta[event.type] || eventTypeMeta.server;
    const timestamp = formatEventTime(event.occurredAt);
    const accent = event.player ? playerColor(event.player) : meta.color;
    const playerClass = event.player ? " event-line--player" : "";
    const headline = compactEventHeadline(event, event.display?.headline || event.title);
    const bullets = Array.isArray(event.display?.bullets) ? event.display.bullets : [];
    const body = compactItemizedEventBody(event, event.display?.body || event.message, bullets);
    const detailClass = bullets.length ? " event-line--with-bullets" : "";
    const visual = event.icon
      ? gameImage(event.icon, "", "event-line__portrait")
      : `<span class="event-line__token" aria-hidden="true">${escapeHtml(meta.token)}</span>`;
    const key = eventIdentity(event) || `visible:${index}`;
    const signature = eventRenderSignature(event);
    const confidenceBadge = event.confidence === "derived"
      ? '<em class="event-line__confidence" aria-label="Rattaché à la guilde : le fait vient de la guilde, le joueur affiché est le meilleur repère disponible" title="Cet écho vient de la guilde; le joueur affiché est le meilleur repère disponible.">Rattaché à la guilde</em>'
      : "";
    const windowMinutes = eventAggregationWindowMinutes(event);
    const windowBadge = windowMinutes
      ? `<em class="event-line__window" aria-label="Tranche de ${windowMinutes} minutes">Tranche de ${windowMinutes} min</em>`
      : "";
    return `
      <li class="event-line event-line--${escapeHtml(event.type)}${playerClass}${detailClass}" data-event-key="${escapeHtml(key)}" data-event-render="${escapeHtml(signature)}" style="--event-accent:${accent};--event-type-accent:${meta.color}">
        <time datetime="${escapeHtml(event.occurredAt)}"><strong>${escapeHtml(timestamp.time)}</strong><span>${escapeHtml(timestamp.date)}</span></time>
        <span class="event-line__rail" aria-hidden="true"><i></i></span>
        <span class="event-line__visual">${visual}</span>
        <span class="event-line__content">
          <span class="event-line__meta"><b>${escapeHtml(meta.label)}</b>${windowBadge}${event.player ? `<em class="event-line__player">${escapeHtml(event.player)}</em>` : ""}${event.base ? `<em class="event-line__base">${escapeHtml(event.base)}</em>` : ""}${confidenceBadge}</span>
          <strong>${escapeHtml(headline)}</strong>
          <span class="event-line__body">${escapeHtml(body)}</span>
          ${bullets.length ? `<ul class="event-line__bullets">${bullets.map((bullet) => `<li>${escapeHtml(bullet)}</li>`).join("")}</ul>` : ""}
        </span>
      </li>`;
}

function eventBulletQuantityTotal(bullets) {
  return bullets.reduce((sum, bullet) => {
    const match = String(bullet || "").match(/^[+-]?(\d+)/);
    return sum + (match ? Number(match[1]) : 0);
  }, 0);
}

function eventDetailItemsQuantityTotal(event, key) {
  const items = Array.isArray(event.details?.items) ? event.details.items : [];
  return items.reduce((sum, item) => sum + Number(item?.[key] || 0), 0);
}

function frenchPlural(value, singular, pluralForm) {
  return value === 1 ? singular : pluralForm;
}

function eventAggregationWindowMinutes(event) {
  const minutes = Number(event?.details?.windowMinutes || 0);
  return Number.isFinite(minutes) && minutes > 0 ? Math.round(minutes) : 0;
}

function eventAggregationWindowLabel(event) {
  const minutes = eventAggregationWindowMinutes(event);
  if (!minutes) return "";
  return minutes === 1 ? "1 min" : `${minutes} min`;
}

function eventAggregationHeadline(event, fallbackHeadline) {
  const minutes = eventAggregationWindowMinutes(event);
  if (!minutes) return fallbackHeadline;
  const labels = {
    craft: "Fabrications terminées",
    production: "Ressources produites relevées",
    fishing: "Pêche ramenée",
    build: "Base agrandie",
    repair: "Réparations terminées",
    base: "État de base relevé",
    loot: "Butin récupéré",
    collection: "Collection enrichie",
  };
  return labels[event.type] || fallbackHeadline || "Activité relevée";
}

function compactEventHeadline(event, fallbackHeadline) {
  if (eventAggregationWindowMinutes(event)) return eventAggregationHeadline(event, fallbackHeadline);
  if (event.type !== "production") return fallbackHeadline;
  const player = String(event.player || "").trim();
  const base = String(event.base || "").trim();
  if (player && base) return `${player} termine une production à ${base}`;
  if (player) return `${player} termine une production`;
  if (base) return `${base} termine une production`;
  return fallbackHeadline;
}

function compactProductionEventBody(event, fallbackBody, bullets) {
  const added = eventBulletQuantityTotal(bullets) || eventDetailItemsQuantityTotal(event, "added");
  const total = Number(event.details?.total || eventDetailItemsQuantityTotal(event, "count"));
  if (!added) return fallbackBody;
  const isDerived = event.confidence === "derived";
  const ready = isDerived
    ? added === 1 ? "1 ressource supplémentaire a été relevée." : `${added.toLocaleString("fr-CA")} ressources supplémentaires ont été relevées.`
    : added === 1 ? "1 ressource produite est prête." : `${added.toLocaleString("fr-CA")} ressources produites sont prêtes.`;
  const body = total > 0
    ? `${ready} ${isDerived ? "Stock observé" : "Stock de production"} : ${total.toLocaleString("fr-CA")}.`
    : ready;
  return body;
}

function compactItemizedEventBody(event, fallbackBody, bullets) {
  if (event.type === "production") return compactProductionEventBody(event, fallbackBody, bullets);
  if (!bullets.length || !["craft", "fishing", "build", "repair", "base"].includes(event.type)) return fallbackBody;
  const added = eventBulletQuantityTotal(bullets);
  const total = Number(event.details?.total || 0);
  const player = String(event.player || "").trim();
  const base = String(event.base || "").trim();
  if (!added || (!player && !base)) return fallbackBody;

  if (event.type === "craft") {
    const totalLabel = total > 0 ? ` Total cumulé : ${total.toLocaleString("fr-CA")}.` : "";
    return `${player} termine ${added.toLocaleString("fr-CA")} ${frenchPlural(added, "fabrication", "fabrications")}.${totalLabel}`;
  }
  if (event.type === "fishing") {
    const totalLabel = total > 0 ? ` Total cumulé : ${total.toLocaleString("fr-CA")}.` : "";
    return `${player} ramène ${added.toLocaleString("fr-CA")} ${frenchPlural(added, "prise de pêche", "prises de pêche")}.${totalLabel}`;
  }
  const owner = player || base;
  if (event.type === "build") {
    const scope = base && !String(owner).includes(base) ? ` à ${base}` : "";
    const totalLabel = total > 0 ? ` Total suivi : ${total.toLocaleString("fr-CA")}.` : "";
    return `${owner} ajoute ${added.toLocaleString("fr-CA")} ${frenchPlural(added, "structure", "structures")}${scope}.${totalLabel}`;
  }
  if (event.type === "repair") {
    const scope = base && !String(owner).includes(base) ? ` à ${base}` : "";
    return `${owner} remet ${added.toLocaleString("fr-CA")} ${frenchPlural(added, "structure", "structures")} en état${scope}.`;
  }
  if (event.type === "base") {
    const scope = base && !String(owner).includes(base) ? ` à ${base}` : "";
    return `${owner} relève ${added.toLocaleString("fr-CA")} ${frenchPlural(added, "structure endommagée", "structures endommagées")}${scope}.`;
  }
  return fallbackBody;
}

function renderEventPaginationControls(pageCount) {
  if (!eventPagination) return;
  if (pageCount <= 1) {
    eventPagination.innerHTML = "";
    eventPagination.hidden = true;
    return;
  }

  eventPagination.hidden = false;
  if (isTerminalRoute()) {
    eventPagination.innerHTML = `
      <button type="button" data-event-page="${eventCurrentPage - 1}" aria-label="Page précédente" ${eventCurrentPage === 1 ? "disabled" : ""}>‹</button>
      <span class="event-pagination__position">
        <span>Page</span>
        <input class="event-pagination__page-input" type="number" inputmode="numeric" min="1" max="${pageCount}" value="${eventCurrentPage}" aria-label="Aller à la page">
        <span>/ ${formatInteger(pageCount)}</span>
      </span>
      <button type="button" data-event-page="${eventCurrentPage + 1}" aria-label="Page suivante" ${eventCurrentPage === pageCount ? "disabled" : ""}>›</button>`;
    return;
  }

  const pages = eventPageNumbers(eventCurrentPage, pageCount);
  let previousPage = 0;
  const pageButtons = pages.map((page) => {
    const gap = previousPage && page - previousPage > 1 ? '<span aria-hidden="true">…</span>' : "";
    previousPage = page;
    return `${gap}<button type="button" data-event-page="${page}"${page === eventCurrentPage ? ' class="is-current" aria-current="page"' : ""}>${page}</button>`;
  }).join("");
  eventPagination.innerHTML = `
    <button type="button" data-event-page="${eventCurrentPage - 1}" ${eventCurrentPage === 1 ? "disabled" : ""}>Précédente</button>
    <span class="event-pagination__pages">${pageButtons}</span>
    <button type="button" data-event-page="${eventCurrentPage + 1}" ${eventCurrentPage === pageCount ? "disabled" : ""}>Suivante</button>`;
}

function eventIndexTotalEvents() {
  return Number(eventsIndexSnapshot?.summary?.totalEvents || eventsIndexSnapshot?.summary?.events || 0);
}

function eventIndexDisplayTotalEvents() {
  const replacement = v5TailReplacementWindow(eventsIndexSnapshot, eventsRecentSnapshot);
  const recentTotal = Number(eventsRecentSnapshot?.summary?.totalEvents);
  return replacement && Number.isInteger(recentTotal) && recentTotal >= 0
    ? recentTotal
    : eventIndexTotalEvents();
}

function eventIndexPageSize() {
  return Math.max(1, Number(eventsIndexSnapshot?.pageSize || eventExportPageSizeFallback));
}

function eventIndexPagePath(pageNumber) {
  const page = Number(pageNumber) || 1;
  const metadata = (eventsIndexSnapshot?.pages || []).find((entry) => Number(entry?.page) === page);
  return String(metadata?.path || `data/public-events-page-${String(page).padStart(4, "0")}.json`).replace(/^\/+/, "");
}

function eventIndexPageSignature(entry) {
  if (!entry) return "";
  return [
    entry.path || "",
    entry.events || "",
    entry.firstAt || "",
    entry.lastAt || "",
  ].join("|");
}

function eventIndexEntryForPage(pageNumber) {
  const page = Number(pageNumber) || 1;
  return (eventsIndexSnapshot?.pages || []).find((entry) => Number(entry?.page) === page);
}

function eventPayloadPageSignature(payload) {
  if (!payload) return "";
  return [
    payload.path || "",
    (payload.events || []).length || payload.summary?.events || "",
    payload.summary?.firstAt || "",
    payload.summary?.lastAt || "",
  ].join("|");
}

function eventCachedPageMatchesIndex(pageNumber, payload) {
  const entry = eventIndexEntryForPage(pageNumber);
  if (!entry || !payload) return false;
  return eventIndexPageSignature(entry) === eventPayloadPageSignature(payload);
}

function invalidateChangedEventPages(previousIndex, nextIndex) {
  if (!previousIndex || !nextIndex) {
    eventPageCache.clear();
    eventPagePromises.clear();
    return;
  }

  const previousPages = new Map((previousIndex.pages || []).map((entry) => [
    Number(entry?.page) || 1,
    eventIndexPageSignature(entry),
  ]));
  const nextPages = new Set();
  for (const entry of nextIndex.pages || []) {
    const page = Number(entry?.page) || 1;
    nextPages.add(page);
    if (previousPages.get(page) !== eventIndexPageSignature(entry)) {
      eventPageCache.delete(page);
      eventPagePromises.delete(page);
    }
  }

  for (const page of eventPageCache.keys()) {
    if (!nextPages.has(page)) eventPageCache.delete(page);
  }
  for (const page of eventPagePromises.keys()) {
    if (!nextPages.has(page)) eventPagePromises.delete(page);
  }
}

function eventExportPageNumbersForWindow(start, end, pageSize) {
  if (end <= start) return [];
  const firstPage = Math.floor(start / pageSize) + 1;
  const lastPage = Math.floor((end - 1) / pageSize) + 1;
  return Array.from({ length: lastPage - firstPage + 1 }, (_, index) => firstPage + index);
}

async function loadEventExportPage(pageNumber) {
  const page = Number(pageNumber) || 1;
  if (eventPageCache.has(page)) {
    const cached = eventPageCache.get(page);
    if (eventCachedPageMatchesIndex(page, cached)) return cached;
    eventPageCache.delete(page);
  }
  if (eventPagePromises.has(page)) return eventPagePromises.get(page);

  const promise = readJson(eventIndexPagePath(page))
    .then((payload) => {
      const pagePayload = {
        ...payload,
        path: eventIndexPagePath(page),
        events: dedupeSessionFallbackEvents(payload?.events),
      };
      eventPageCache.set(page, pagePayload);
      return pagePayload;
    })
    .finally(() => eventPagePromises.delete(page));
  eventPagePromises.set(page, promise);
  return promise;
}

async function collectPagedTerminalEvents() {
  const totalEvents = eventIndexTotalEvents();
  updateTerminalPageSize();
  const terminalPageCount = Math.max(1, Math.ceil(totalEvents / terminalEventPageSize));
  eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), terminalPageCount);
  const start = (eventCurrentPage - 1) * terminalEventPageSize;
  const end = Math.min(start + terminalEventPageSize, totalEvents);
  const exportPageSize = eventIndexPageSize();
  const sourcePages = eventExportPageNumbersForWindow(start, end, exportPageSize);
  const payloads = await Promise.all(sourcePages.map((page) => loadEventExportPage(page)));
  const sourceStart = (sourcePages[0] - 1) * exportPageSize;
  const coldEvents = payloads.flatMap((payload) => payload.events || []);
  // La tête v5 peut avancer entre deux checkpoints froids. Tant que la
  // fenêtre demandée part de la première page exportée, on reconstruit cette
  // tête avec la queue canonique. Les pages profondes restent volontairement
  // celles du dernier checkpoint jusqu'à sa prochaine publication.
  const events = sourceStart === 0
    ? mergeV5PagedTailEvents(coldEvents, eventsIndexSnapshot, eventsRecentSnapshot)
    : coldEvents;
  return events.slice(start - sourceStart, end - sourceStart);
}

async function renderPagedTerminalEvents(refinePageSize = true, options = {}) {
  if (!isTerminalRoute() || !eventsIndexSnapshot || eventFiltersRequireFullHistory()) return false;
  const preserveViewport = Boolean(options.preserveViewport);
  const streamTopBefore = preserveViewport ? eventStream?.getBoundingClientRect().top : null;

  const totalEvents = eventIndexTotalEvents();
  if (!totalEvents) {
    if (eventResultCount) eventResultCount.textContent = "Aucun écho";
    if (eventStream) eventStream.innerHTML = '<li class="event-stream__empty">Les premiers échos arrivent...</li>';
    renderEventPaginationControls(1);
    return true;
  }

  try {
    updateTerminalPageSize();
    const pageCount = Math.max(1, Math.ceil(totalEvents / terminalEventPageSize));
    eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), pageCount);
    const start = (eventCurrentPage - 1) * terminalEventPageSize;
    const end = Math.min(start + terminalEventPageSize, totalEvents);
    const missingPages = eventExportPageNumbersForWindow(start, end, eventIndexPageSize())
      .filter((page) => !eventPageCache.has(page));
    const canKeepCurrentRows = Boolean(options.preserveDom && eventStream?.querySelector(".event-line"));
    if (missingPages.length && eventStream && !canKeepCurrentRows) {
      eventStream.innerHTML = '<li class="event-stream__empty">Chargement des échos...</li>';
    }

    const visible = await collectPagedTerminalEvents();
    const displayTotalEvents = eventIndexDisplayTotalEvents();
    const resultLabel = `${displayTotalEvents.toLocaleString("fr-CA")} écho${displayTotalEvents > 1 ? "s" : ""}`;
    const updatedPageCount = Math.max(1, Math.ceil(totalEvents / terminalEventPageSize));
    if (eventResultCount) {
      eventResultCount.textContent = updatedPageCount > 1
        ? `${resultLabel} · page ${eventCurrentPage} sur ${updatedPageCount}`
        : resultLabel;
    }
    if (renderEventStreamItems(visible, true, refinePageSize, { preserveDom: Boolean(options.preserveDom) })) {
      await renderPagedTerminalEvents(false, options);
      return true;
    }
    renderEventPaginationControls(updatedPageCount);
    if (preserveViewport && Number.isFinite(streamTopBefore)) {
      const streamTopAfter = eventStream?.getBoundingClientRect().top;
      if (Number.isFinite(streamTopAfter)) {
        window.scrollBy({ top: streamTopAfter - streamTopBefore, behavior: "auto" });
      }
    }
    return true;
  } catch {
    const result = await loadEventsWithRecentOverlay(true);
    if (result.ok) renderEvents(false, options);
    return result.ok;
  }
}

async function updateTerminalEvents(refinePageSize = true) {
  if (isTerminalRoute() && eventsContractMode === "v6") {
    if (eventFiltersRequireFullHistory() && !eventsFullLoaded) {
      if (eventResultCount) eventResultCount.textContent = "Chargement de l'historique complet...";
      await loadFullTerminalEventsV6();
    }
    if (!eventFiltersRequireFullHistory() && !eventsFullLoaded && eventCurrentPage > 1) {
      await renderPagedTerminalEventsV6({ preserveDom: true, preserveViewport: true });
    } else {
      renderEvents(refinePageSize);
    }
    writeTerminalState();
    return;
  }
  if (isTerminalRoute() && !eventsFullLoaded && eventFiltersRequireFullHistory()) {
    if (eventResultCount) eventResultCount.textContent = "Chargement de l'historique complet...";
    await loadEventsWithRecentOverlay(true);
  }
  if (isTerminalRoute() && !eventsFullLoaded && !eventsIndexSnapshot && !eventsSnapshot) {
    await loadEventsWithRecentOverlay(true);
  }
  if (isTerminalRoute() && !eventsFullLoaded && eventsIndexSnapshot) {
    await renderPagedTerminalEvents(refinePageSize);
  } else {
    renderEvents(refinePageSize);
  }
  writeTerminalState();
}

function renderEvents(refinePageSize = true, options = {}) {
  const preserveViewport = Boolean(options.preserveViewport);
  const streamTopBefore = preserveViewport ? eventStream?.getBoundingClientRect().top : null;
  const events = dedupeSessionFallbackEvents(eventsSnapshot?.events);
  const query = normalizeEventSearch(eventSearch?.value);
  const type = selectedEventTypeValue();
  const player = selectedEventPlayerValue();
  const filtered = events.filter((event) => {
    if (type !== "all" && event.type !== type) return false;
    if (player !== "all" && event.player !== player) return false;
    if (!query) return true;
    return normalizeEventSearch([
      event.player,
      event.guild,
      event.base,
      event.title,
      event.message,
      event.display?.headline,
      event.display?.body,
      ...(event.display?.bullets || []),
      event.type,
    ].filter(Boolean).join(" ")).includes(query);
  });
  const terminal = isTerminalRoute();
  const terminalV6 = terminal && eventsContractMode === "v6";
  if (terminal && !terminalV6) updateTerminalPageSize();
  const pageSize = terminalV6 ? terminalV6EchoLimit : terminal ? terminalEventPageSize : dashboardEventPageSize;
  const totalEvents = Number(eventsSnapshot?.summary?.totalEvents || events.length);
  const v6HeadOnly = terminalV6 && !eventsFullLoaded && !eventFiltersRequireFullHistory();
  const paginationTotal = v6HeadOnly ? Math.max(v6ManifestTotalEchoes(), filtered.length) : filtered.length;
  const pageCount = Math.max(1, Math.ceil(paginationTotal / pageSize));
  if (terminalV6) {
    eventCursor = "";
    eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), pageCount);
    terminalEventWindowStart = eventsFullLoaded ? (eventCurrentPage - 1) * pageSize : 0;
    terminalVisibleEvents = eventsFullLoaded ? filtered : filtered.slice(0, terminalV6EchoLimit);
  } else {
    eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), pageCount);
    terminalEventWindowStart = (eventCurrentPage - 1) * pageSize;
    terminalVisibleEvents = filtered;
  }
  const start = terminalEventWindowStart;
  const visible = terminalV6 && !eventsFullLoaded ? terminalVisibleEvents : filtered.slice(start, start + pageSize);

  const resultLabel = terminalV6
    ? (filtered.length === events.length && !eventFiltersRequireFullHistory()
      ? `${dailyPlural(visible.length, "écho affiché", "échos affichés")} · ${formatInteger(totalEvents)} synchronisés`
      : `${dailyPlural(filtered.length, "résultat", "résultats")} · ${formatInteger(totalEvents)} synchronisés`)
    : filtered.length === events.length
    ? (eventsSnapshot?.recent && totalEvents > events.length
      ? `${events.length} échos récents affichés sur ${totalEvents.toLocaleString("fr-CA")}`
      : `${events.length} écho${events.length > 1 ? "s" : ""}`)
    : `${filtered.length} résultat${filtered.length > 1 ? "s" : ""} sur ${events.length}`;
  if (eventResultCount) {
    eventResultCount.textContent = pageCount > 1
      ? `${resultLabel} · page ${eventCurrentPage} sur ${pageCount}`
      : resultLabel;
  }

  if (renderEventStreamItems(visible, terminal, refinePageSize, { preserveDom: Boolean(options.preserveDom) })) {
    renderEvents(false, options);
    return;
  }
  renderEventPaginationControls(pageCount);
  if (preserveViewport && Number.isFinite(streamTopBefore)) {
    const streamTopAfter = eventStream?.getBoundingClientRect().top;
    if (Number.isFinite(streamTopAfter)) {
      window.scrollBy({ top: streamTopAfter - streamTopBefore, behavior: "auto" });
    }
  }
}

function formatInteger(value) {
  return Number(value || 0).toLocaleString("fr-CA");
}

function dailyPlural(value, singular, plural = `${singular}s`) {
  return `${formatInteger(value)} ${Number(value) === 1 ? singular : plural}`;
}

function dailyDateKeyParts(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: siteTimeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date).reduce((values, part) => {
    if (part.type !== "literal") values[part.type] = part.value;
    return values;
  }, {});
  if (!parts.year || !parts.month || !parts.day) return null;
  return parts;
}

function dailyDateKeyFromDate(date) {
  const parts = dailyDateKeyParts(date);
  return parts ? `${parts.year}-${parts.month}-${parts.day}` : "";
}

function dailyDateFromKey(key, endOfDay = false) {
  const match = String(key || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const time = endOfDay ? "23:59:59.999" : "12:00:00.000";
  return new Date(`${match[1]}-${match[2]}-${match[3]}T${time}-04:00`);
}

function dailyDateStartFromKey(key) {
  const match = String(key || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return match ? new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00.000-04:00`) : null;
}

function dailyDateEndFromKey(key) {
  const start = dailyDateStartFromKey(key);
  if (!start) return null;
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return end;
}

function isDailyDateKey(value) {
  return Boolean(dailyDateFromKey(value));
}

function dailyDisplayDate(key, options = {}) {
  const date = dailyDateFromKey(key);
  if (!date) return key || "Journée inconnue";
  return date.toLocaleDateString("fr-CA", {
    weekday: options.short ? undefined : "long",
    day: "numeric",
    month: options.short ? "short" : "long",
    year: "numeric",
  });
}

function dailyEnumerateKeys(firstDate, lastDate) {
  const firstKey = dailyDateKeyFromDate(firstDate);
  const lastKey = dailyDateKeyFromDate(lastDate);
  if (!firstKey || !lastKey) return [];
  const start = dailyDateFromKey(firstKey);
  const end = dailyDateFromKey(lastKey);
  if (!start || !end || start > end) return [];
  const keys = [];
  const current = new Date(start);
  while (current <= end && keys.length < 45) {
    keys.push(dailyDateKeyFromDate(current));
    current.setDate(current.getDate() + 1);
  }
  return keys;
}

function dailyAvailableKeysFromIndex() {
  if (Number(eventsIndexSnapshot?.schemaVersion) === 6 && Array.isArray(eventsIndexSnapshot?.days)) {
    return eventsIndexSnapshot.days.map((entry) => entry.date).filter(isDailyDateKey);
  }
  const keys = new Set();
  for (const entry of eventsIndexSnapshot?.pages || []) {
    if (!Number(entry?.events || 0)) continue;
    const first = parseDate(entry.firstAt);
    const last = parseDate(entry.lastAt);
    if (!first || !last) continue;
    const start = first < last ? first : last;
    const end = first < last ? last : first;
    dailyEnumerateKeys(start, end).forEach((key) => keys.add(key));
  }
  return [...keys].sort((left, right) => right.localeCompare(left));
}

function dailyRequestedDateKey() {
  const key = new URLSearchParams(location.search).get("jour") || "";
  return isDailyDateKey(key) ? key : "";
}

function dailyResolveSelectedDate() {
  const requested = dailySelectedDateKey || dailyRequestedDateKey();
  if (requested) return requested;
  return dailyAvailableDateKeys[0] || dailyDateKeyFromDate(new Date());
}

function dailySetUrlDate(key) {
  if (!isDailyDigestRoute() || !isDailyDateKey(key)) return;
  history.replaceState(null, "", `/resume?jour=${encodeURIComponent(key)}`);
}

function dailyPagesForDate(key) {
  if (!isDailyDateKey(key)) return [];
  return (eventsIndexSnapshot?.pages || []).filter((entry) => {
    if (!Number(entry?.events || 0)) return false;
    const first = parseDate(entry.firstAt);
    const last = parseDate(entry.lastAt);
    if (!first || !last) return false;
    const firstKey = dailyDateKeyFromDate(first);
    const lastKey = dailyDateKeyFromDate(last);
    if (!firstKey || !lastKey) return false;
    const rangeStart = firstKey < lastKey ? firstKey : lastKey;
    const rangeEnd = firstKey < lastKey ? lastKey : firstKey;
    return rangeStart <= key && key <= rangeEnd;
  });
}

async function loadDailyRoster() {
  try {
    const [savePayload, statsPayload] = await Promise.all([
      readJson("data/public-save-index.json"),
      readJson("data/public-stats.json").catch(() => null),
    ]);
    const rosterPlayers = Array.isArray(savePayload?.players) ? savePayload.players : [];
    dailyStatsPlayers = Array.isArray(statsPayload?.players) ? statsPayload.players : [];
    dailyStatsUpdatedAt = statsPayload?.updatedAt || "";
    const playersByName = new Map();
    rosterPlayers.forEach((player) => {
      const name = String(player?.name || "").trim();
      const key = normalizePlayerNameKey(name);
      if (key) playersByName.set(key, { ...player, name });
    });
    dailyStatsPlayers.forEach((player) => {
      const name = String(player?.name || "").trim();
      const key = normalizePlayerNameKey(name);
      if (!key) return;
      const previous = playersByName.get(key) || {};
      playersByName.set(key, { ...previous, ...player, name: previous.name || name });
    });
    dailyRosterPlayers = [...playersByName.values()];
    registerPayloadDataUpdate("save", savePayload);
    if (statsPayload) registerPayloadDataUpdate("stats", statsPayload);
    return { ok: true, changed: false };
  } catch {
    dailyRosterPlayers = [];
    dailyStatsPlayers = [];
    dailyStatsUpdatedAt = "";
    return { ok: false, changed: false };
  }
}

async function loadDailyEventsForDate(key) {
  const pages = dailyPagesForDate(key);
  if (!pages.length) return [];
  const payloads = await Promise.all(pages.map((entry) => loadEventExportPage(entry.page)));
  const coldEvents = payloads.flatMap((payload) => payload.events || []);
  const includesColdHead = pages.some((entry) => Number(entry?.page) === 1);
  const events = includesColdHead
    ? mergeV5PagedTailEvents(coldEvents, eventsIndexSnapshot, eventsRecentSnapshot)
    : coldEvents;
  return sortEventsNewestFirst(events)
    .filter((event) => dailyDateKeyFromDate(parseDate(event.occurredAt)) === key);
}

function dailyList(value) {
  if (Array.isArray(value)) return value;
  if (value == null || value === "") return [];
  return [value];
}

function dailyNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : 0;
  const parsed = Number(String(value ?? "").replace(/[^\d.-]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function dailyFirstNumber(text, pattern) {
  const match = String(text || "").match(pattern);
  return match ? dailyNumber(match[1]) : 0;
}

function dailyAddedTotal(value) {
  return dailyList(value).reduce((total, item) => {
    if (item && typeof item === "object") {
      return total + Math.max(0, dailyNumber(item.added ?? item.count ?? 0));
    }
    const match = String(item || "").match(/^\s*\+(\d[\d\s]*)/);
    return total + (match ? dailyNumber(match[1]) : 0);
  }, 0);
}

function dailyRemovedTotal(value) {
  return dailyList(value).reduce((total, item) => {
    if (item && typeof item === "object") return total;
    const match = String(item || "").match(/^\s*-(\d[\d\s]*)/);
    return total + (match ? dailyNumber(match[1]) : 0);
  }, 0);
}

function dailyCountedEntriesFromText(text) {
  const normalized = String(text || "")
    .replace(/\s+et\s+/gi, ", ")
    .split(/\s*,\s*/)
    .map((part) => part.trim())
    .filter(Boolean);
  return normalized.map((part) => {
    const match = part.match(/^(\d[\d\s]*)\s+(.+)$/);
    if (!match) return null;
    return {
      count: Math.max(0, dailyNumber(match[1])),
      name: match[2].trim().replace(/[.;:]$/, ""),
    };
  }).filter((entry) => entry && entry.count > 0 && entry.name);
}

function dailyMessageWithoutPlayer(message, player) {
  const text = String(message || "").trim();
  const name = String(player || "").trim();
  if (!name) return text;
  return text.replace(new RegExp(`^${escapeRegExp(name)}\\s+`, "i"), "").trim();
}

function dailyCollectionEntries(event) {
  const message = `${event?.display?.body || ""} ${event?.message || ""}`;
  const match = message.match(/accueille\s+(.+?)\s+dans\s+sa\s+collection/i);
  return match ? dailyCountedEntriesFromText(match[1]) : [];
}

function dailyCaptureEntries(event) {
  const message = dailyMessageWithoutPlayer(`${event?.display?.body || ""} ${event?.message || ""}`, event?.player);
  if (event?.type === "capture") {
    const match = message.match(/capture\s+(\d[\d\s]*)\s+(.+?)\.\s+Total/i);
    if (match) {
      return [{
        count: Math.max(0, dailyNumber(match[1])),
        name: match[2].trim(),
      }];
    }
    const firstCapture = message.match(/capture\s+(.+?)\s+pour\s+la\s+premi[eè]re\s+fois/i);
    if (firstCapture) {
      return [{ count: 1, name: firstCapture[1].trim().replace(/[.;:]$/, "") }];
    }
    const paldex = message.match(/inscrit\s+(.+?)\s+dans\s+son\s+Paldex(?:\s+avec\s+(\d[\d\s]*)\s+captures?)?/i);
    if (paldex) {
      return [{ count: Math.max(1, dailyNumber(paldex[2] || 1)), name: paldex[1].trim().replace(/[.;:]$/, "") }];
    }
  }
  if (event?.type === "collection") return dailyCollectionEntries(event);
  return [];
}

function dailyCountedTotal(entries) {
  return entries.reduce((total, entry) => total + Number(entry.count || 0), 0);
}

function dailyHourFromDate(date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  const hour = new Intl.DateTimeFormat("en-CA", {
    timeZone: siteTimeZone,
    hour: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date).find((part) => part.type === "hour")?.value;
  const parsed = Number(hour);
  return Number.isInteger(parsed) ? parsed : null;
}

function dailyEventQuantities(event) {
  const details = event?.details || {};
  const message = `${event?.display?.body || ""} ${event?.message || ""}`;
  const bullets = details.bullets ?? event?.display?.bullets;
  const items = details.items;
  const structures = details.structures;
  const quantities = {
    craft: 0,
    production: 0,
    build: 0,
    repair: 0,
    capture: 0,
    collection: 0,
    fishing: 0,
    levelUps: 0,
    level: 0,
    boss: event?.type === "boss" ? 1 : 0,
    discovery: event?.type === "discovery" ? 1 : 0,
    progress: ["progress", "research", "quest", "challenge", "camp"].includes(event?.type) ? 1 : 0,
    challenge: event?.type === "challenge" ? 1 : 0,
    quest: event?.type === "quest" ? 1 : 0,
    loot: event?.type === "loot" ? 1 : 0,
    note: event?.type === "note" ? 1 : 0,
    mutation: event?.type === "mutation" ? 1 : 0,
    death: event?.type === "death" ? 1 : 0,
    recovery: event?.type === "recovery" ? 1 : 0,
    adventure: event?.type === "adventure" ? 1 : 0,
    rare: 0,
  };

  if (event?.type === "craft") {
    quantities.craft = dailyAddedTotal(items) || dailyAddedTotal(bullets) || dailyFirstNumber(message, /termine\s+(\d[\d\s]*)\s+fabrication/i) || 1;
  }
  if (event?.type === "production") {
    quantities.production = dailyAddedTotal(items) || dailyAddedTotal(bullets) || dailyFirstNumber(message, /(\d[\d\s]*)\s+ressources?\s+produites?/i) || 1;
  }
  if (event?.type === "build") {
    quantities.build = dailyAddedTotal(structures) || dailyAddedTotal(bullets) || dailyFirstNumber(message, /(\d[\d\s]*)\s+nouvelles?\s+structures?/i) || 1;
  }
  if (event?.type === "repair") {
    quantities.repair = dailyRemovedTotal(bullets) || dailyFirstNumber(message, /(\d[\d\s]*)\s+structures?\s+r[ée]par/i) || 1;
  }
  if (event?.type === "capture") {
    quantities.capture = dailyCountedTotal(dailyCaptureEntries(event)) || dailyFirstNumber(message, /capture\s+(\d[\d\s]*)/i) || 1;
  }
  if (event?.type === "collection") {
    quantities.collection = dailyCountedTotal(dailyCollectionEntries(event)) || dailyFirstNumber(message, /compte\s+(\d[\d\s]*)\s+Pals?\s+de\s+plus/i) || 1;
  }
  if (event?.type === "fishing") {
    quantities.fishing = dailyAddedTotal(items) || dailyAddedTotal(bullets) || dailyFirstNumber(message, /ram[èe]ne\s+(\d[\d\s]*)/i) || 1;
  }
  if (event?.type === "level") {
    quantities.levelUps = 1;
    quantities.level = dailyFirstNumber(message, /niveau\s+(\d[\d\s]*)/i);
  }

  const rareTypes = new Set(["level", "boss", "mutation", "research", "quest", "challenge", "note", "camp"]);
  const text = `${event?.title || ""} ${event?.message || ""}`.toLocaleLowerCase("fr-CA");
  if (rareTypes.has(event?.type) || /premi[eè]re|nouveau|nouvelle|unique|mutation|boss/.test(text)) {
    quantities.rare = 1;
  }
  return quantities;
}

function dailyItemQuantity(item) {
  return Math.max(0, dailyNumber(item?.added ?? item?.count ?? 0)) || 1;
}

function dailyItemKey(item, type) {
  const asset = String(item?.asset || "").trim();
  const name = String(item?.name || "Objet").trim();
  return `${type}|${asset || name}`.toLocaleLowerCase("fr-CA");
}

function dailyItemsFromEvent(event) {
  if (!["craft", "production", "fishing"].includes(event?.type)) return [];
  return dailyList(event?.details?.items).filter((item) => item && typeof item === "object").map((item) => ({
    key: dailyItemKey(item, event.type),
    type: event.type,
    name: String(item.name || "Objet").trim() || "Objet",
    icon: item.icon || null,
    quantity: dailyItemQuantity(item),
    isNew: Boolean(item.isNew),
    player: String(event.player || "Monde").trim() || "Monde",
  })).filter((item) => item.quantity > 0);
}

function dailyAddAggregate(map, entry) {
  if (!entry?.key) return;
  const current = map.get(entry.key) || {
    key: entry.key,
    type: entry.type || "",
    name: entry.name || "Objet",
    icon: entry.icon || null,
    quantity: 0,
    newCount: 0,
    players: new Map(),
  };
  current.quantity += Number(entry.quantity || 0);
  if (entry.isNew) current.newCount += Number(entry.quantity || 0);
  if (!current.icon && entry.icon) current.icon = entry.icon;
  const playerName = entry.player || "Monde";
  current.players.set(playerName, (current.players.get(playerName) || 0) + Number(entry.quantity || 0));
  map.set(entry.key, current);
}

function dailyPalKey(name, type) {
  return `${type}|${String(name || "Pal").trim()}`.toLocaleLowerCase("fr-CA");
}

function dailyPalEntriesFromEvent(event) {
  const type = event?.type === "capture" ? "capture" : event?.type === "collection" ? "collection" : "";
  if (!type) return [];
  const entries = type === "capture" ? dailyCaptureEntries(event) : dailyCollectionEntries(event);
  return entries.map((entry) => ({
    key: dailyPalKey(entry.name, type),
    type,
    name: entry.name,
    icon: event.icon || entry.icon || null,
    quantity: Number(entry.count || 0),
    player: String(event.player || "Monde").trim() || "Monde",
  })).filter((entry) => entry.quantity > 0 && entry.name && entry.name.toLocaleLowerCase("fr-CA") !== "autres");
}

function dailyTopAggregates(map, limit = 5) {
  return [...map.values()]
    .sort((left, right) => Number(right.quantity || 0) - Number(left.quantity || 0)
      || String(left.name).localeCompare(String(right.name), "fr-CA"))
    .slice(0, limit);
}

function dailyConsolidatedPalFinds(summaryOrPlayer) {
  const source = summaryOrPlayer?.palFinds instanceof Map
    ? summaryOrPlayer.palFinds
    : dailyV6Map(summaryOrPlayer?.palFinds);
  if (!(source instanceof Map)) return new Map();
  const consolidated = new Map();
  source.forEach((entry) => {
    const name = String(entry?.name || "").trim();
    if (!name) return;
    const key = name.toLocaleLowerCase("fr-CA");
    const current = consolidated.get(key) || {
      ...entry,
      key,
      type: "pal",
      name,
      quantity: 0,
      players: new Map(),
    };
    current.quantity = Math.max(Number(current.quantity || 0), Number(entry?.quantity || 0));
    if (!current.icon && entry?.icon) current.icon = entry.icon;
    const entryPlayers = entry?.players instanceof Map ? entry.players : new Map(Object.entries(entry?.players || {}));
    entryPlayers.forEach((quantity, playerName) => {
      current.players.set(playerName, Math.max(Number(current.players.get(playerName) || 0), Number(quantity || 0)));
    });
    consolidated.set(key, current);
  });
  return consolidated;
}

function dailyPalSignalTotal(summaryOrPlayer) {
  const aggregateTotal = [...dailyConsolidatedPalFinds(summaryOrPlayer).values()]
    .reduce((total, entry) => total + Number(entry?.quantity || 0), 0);
  if (aggregateTotal > 0) return aggregateTotal;
  const metrics = summaryOrPlayer?.metrics || summaryOrPlayer?.totals || summaryOrPlayer || {};
  const captures = Number(metrics.capture || 0);
  const collection = Number(metrics.collection || 0);
  if (captures && collection) return Math.max(captures, collection);
  return captures + collection;
}

function dailyAggregatePlayersLabel(entry, limit = 2) {
  const players = [...(entry?.players || new Map()).entries()]
    .sort((left, right) => Number(right[1] || 0) - Number(left[1] || 0)
      || String(left[0]).localeCompare(String(right[0]), "fr-CA"));
  if (!players.length) return "Bilan consolidé";
  const visible = players.slice(0, limit).map(([name, quantity]) => `${name} ${formatInteger(quantity)}`);
  const hidden = players.length - visible.length;
  return `${visible.join(" · ")}${hidden > 0 ? ` · +${hidden}` : ""}`;
}

function dailyAggregateQuantityLabel(entry) {
  const quantity = Number(entry?.quantity || 0);
  if (entry?.type === "craft") return dailyPlural(quantity, "objet fabriqué", "objets fabriqués");
  if (entry?.type === "production") return dailyPlural(quantity, "ressource produite", "ressources produites");
  if (entry?.type === "capture") return dailyPlural(quantity, "capture Paldex détectée", "captures Paldex détectées");
  if (entry?.type === "collection") return dailyPlural(quantity, "Pal ajouté en collection", "Pals ajoutés en collection");
  if (entry?.type === "pal") return dailyPlural(quantity, "Pal repéré", "Pals repérés");
  return formatInteger(quantity);
}

function dailyAggregateShortKind(entry) {
  if (entry?.type === "craft") return "fabrication";
  if (entry?.type === "production") return "production";
  if (entry?.type === "capture") return "captures Paldex";
  if (entry?.type === "collection") return "collection";
  if (entry?.type === "pal") return "Pals";
  return "total";
}

function dailyTopAggregateLabel(entry, fallback = "Aucun élément dominant", options = {}) {
  if (!entry) return fallback;
  const prefix = options.withDont ? "dont " : "";
  return `${prefix}${entry.name} · ${dailyAggregateQuantityLabel(entry)}`;
}

function dailyFactTotal(metrics) {
  return Number(metrics.discovery || 0)
    + Number(metrics.boss || 0)
    + Number(metrics.progress || 0)
    + Number(metrics.challenge || 0)
    + Number(metrics.quest || 0)
    + Number(metrics.loot || 0)
    + Number(metrics.note || 0)
    + Number(metrics.mutation || 0)
    + Number(metrics.fishing || 0)
    + Number(metrics.death || 0)
    + Number(metrics.recovery || 0)
    + Number(metrics.adventure || 0);
}

function dailyImpactScore(quantities) {
  return Number(quantities.levelUps || 0) * 120
    + Number(quantities.boss || 0) * 80
    + Number(quantities.death || 0) * 24
    + Number(quantities.recovery || 0) * 8
    + Number(quantities.mutation || 0) * 42
    + Number(quantities.discovery || 0) * 34
    + Number(quantities.challenge || 0) * 28
    + Number(quantities.quest || 0) * 28
    + Number(quantities.progress || 0) * 18
    + Number(quantities.loot || 0) * 16
    + Number(quantities.note || 0) * 12
    + Number(quantities.capture || 0) * 8
    + Number(quantities.collection || 0) * 7
    + Number(quantities.fishing || 0) * 6
    + Number(quantities.build || 0) * 3
    + Number(quantities.repair || 0) * 2
    + Math.min(320, Number(quantities.craft || 0)) * .08
    + Math.min(320, Number(quantities.production || 0)) * .1
    + Number(quantities.rare || 0) * 18;
}

function dailyHighlightScore(event, quantities) {
  const typeScore = {
    death: 42,
    recovery: 18,
    level: 82,
    boss: 78,
    mutation: 76,
    loot: 48,
    research: 64,
    quest: 58,
    challenge: 54,
    discovery: 44,
    adventure: 42,
    collection: 40,
    capture: 36,
    fishing: 34,
    build: 22,
    production: 14,
    craft: 12,
    repair: 20,
  }[event?.type] || 10;
  const quantity = quantities.craft + quantities.production + quantities.build + quantities.capture + quantities.collection + quantities.fishing;
  const quantityScore = quantity >= 1000 ? 42 : quantity >= 250 ? 30 : quantity >= 100 ? 20 : quantity >= 25 ? 12 : quantity >= 8 ? 6 : 0;
  return typeScore + quantityScore + (quantities.rare ? 18 : 0);
}

function dailyHighlightBadge(quantities) {
  if (quantities.level) return `Niveau ${formatInteger(quantities.level)}`;
  if (quantities.capture) return dailyPlural(quantities.capture, "capture");
  if (quantities.collection) return dailyPlural(quantities.collection, "Pal accueilli", "Pals accueillis");
  if (quantities.production) return `${formatInteger(quantities.production)} produit${quantities.production > 1 ? "s" : ""}`;
  if (quantities.craft) return `${formatInteger(quantities.craft)} fabrication${quantities.craft > 1 ? "s" : ""}`;
  if (quantities.build) return dailyPlural(quantities.build, "structure");
  if (quantities.fishing) return dailyPlural(quantities.fishing, "prise");
  if (quantities.boss) return "Boss";
  if (quantities.discovery) return "Découverte";
  if (quantities.challenge) return "Défi";
  if (quantities.mutation) return "Mutation";
  return "";
}

function dailyHighlightFromEvent(event, quantities) {
  const date = parseDate(event.occurredAt);
  const headline = event?.display?.headline || event?.title || "Écho";
  const body = event?.display?.body || event?.message || "";
  const score = dailyHighlightScore(event, quantities);
  return {
    key: eventIdentity(event),
    type: event.type || "server",
    player: event.player || "Monde",
    base: event.base || "",
    occurredAt: event.occurredAt,
    timestamp: date ? date.getTime() : 0,
    time: date ? formatTime(date) : "--",
    headline,
    body,
    confidence: event.confidence || "confirmed",
    badge: dailyHighlightBadge(quantities),
    score,
    accent: event.player ? playerColor(event.player) : (eventTypeMeta[event.type]?.color || "#77a7be"),
  };
}

function dailyShortDateTime(value) {
  const date = parseDate(value);
  if (!date) return value || "--";
  return date.toLocaleString("fr-CA", {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: siteTimeZone,
  }).replace(",", " ·");
}

function dailyShortDate(value) {
  const date = parseDate(value);
  if (!date) return value || "--";
  return date.toLocaleDateString("fr-CA", {
    month: "short",
    day: "2-digit",
    timeZone: siteTimeZone,
  });
}

function dailySessionOverlap(session, dateKey) {
  const dayStart = dailyDateStartFromKey(dateKey);
  const dayEnd = dailyDateEndFromKey(dateKey);
  const startedAt = parseDate(session?.startedAt || session?.startAt || session?.start);
  const endedAt = parseDate(session?.endedAt || session?.endAt || session?.end) || parseDate(dailyStatsUpdatedAt) || new Date();
  if (!dayStart || !dayEnd || !startedAt || !endedAt) return null;
  const boundedStartMs = Math.max(startedAt.getTime(), dayStart.getTime());
  const boundedEndMs = Math.min(endedAt.getTime(), dayEnd.getTime());
  if (boundedEndMs <= boundedStartMs) return null;
  return {
    startedAt: session?.startedAt || session?.startAt || session?.start || startedAt.toISOString(),
    endedAt: session?.endedAt || session?.endAt || session?.end || null,
    boundedStart: new Date(boundedStartMs),
    boundedEnd: new Date(boundedEndMs),
    seconds: Math.floor((boundedEndMs - boundedStartMs) / 1000),
    inferredOpen: !(session?.endedAt || session?.endAt || session?.end),
  };
}

function createDailyPlayerSummary(player) {
  const name = String(player?.name || player || "Monde").trim() || "Monde";
  return {
    name,
    guild: player?.guild || player?.guildName || null,
    level: player?.level ?? null,
    pals: player?.pals?.total ?? null,
    lastSeenAt: player?.lastSeenAt || null,
    lastOnlineAt: player?.lastOnlineAt || null,
    lastSessionEndedAt: player?.lastSessionEndedAt || null,
    totalOnline: player?.totalOnline || null,
    totalOnlineSeconds: Number(player?.totalOnlineSeconds || 0),
    sessionCount: Number(player?.sessionCount || 0),
    sessionHistory: Array.isArray(player?.sessionHistory) ? player.sessionHistory : [],
    dailyOnlineSeconds: 0,
    dailySessionCount: 0,
    dailyPresenceObserved: false,
    dailySessions: [],
    eventCount: 0,
    firstAt: null,
    lastAt: null,
    typeCounts: new Map(),
    metrics: {
      craft: 0,
      production: 0,
      build: 0,
      repair: 0,
      capture: 0,
      collection: 0,
      fishing: 0,
      levelUps: 0,
      boss: 0,
      discovery: 0,
      progress: 0,
      challenge: 0,
      quest: 0,
      loot: 0,
      note: 0,
      mutation: 0,
      death: 0,
      recovery: 0,
      adventure: 0,
      rare: 0,
    },
    craftedItems: new Map(),
    producedItems: new Map(),
    palFinds: new Map(),
    highlights: [],
    score: 0,
  };
}

function applyDailyPresence(player, dateKey) {
  const sessions = (player.sessionHistory || [])
    .map((session) => dailySessionOverlap(session, dateKey))
    .filter(Boolean);
  const lastTraceAt = player.lastSeenAt || player.lastOnlineAt || player.lastSessionEndedAt || null;
  const lastTraceDate = parseDate(lastTraceAt);
  if (!sessions.length && lastTraceDate && dailyDateKeyFromDate(lastTraceDate) === dateKey) {
    sessions.push({
      startedAt: lastTraceAt,
      endedAt: lastTraceAt,
      boundedStart: lastTraceDate,
      boundedEnd: lastTraceDate,
      seconds: 0,
      observedOnly: true,
    });
  }

  if (!sessions.length) return;

  player.dailySessions = sessions.sort((left, right) => left.boundedStart - right.boundedStart);
  player.dailySessionCount = sessions.length;
  player.dailyPresenceObserved = true;
  player.dailyOnlineSeconds = sessions.reduce((sum, session) => sum + Number(session.seconds || 0), 0);
  const firstSession = player.dailySessions[0];
  const lastSession = player.dailySessions.at(-1);
  if (firstSession?.boundedStart && (!player.firstAt || firstSession.boundedStart < player.firstAt)) player.firstAt = firstSession.boundedStart;
  if (lastSession?.boundedEnd && (!player.lastAt || lastSession.boundedEnd > player.lastAt)) player.lastAt = lastSession.boundedEnd;
  player.score += Math.min(160, (player.dailyOnlineSeconds / 3600) * 10 + player.dailySessionCount * 4);
}

function dailyPlayerHasActivity(player) {
  return Boolean(Number(player?.eventCount || 0) > 0 || player?.dailyPresenceObserved);
}

function addDailyQuantities(target, quantities) {
  for (const key of Object.keys(target)) {
    target[key] += Number(quantities[key] || 0);
  }
}

function buildDailyDigest(dateKey, events) {
  const players = new Map();
  dailyRosterPlayers.forEach((player) => {
    const name = String(player?.name || "").trim();
    if (name) players.set(name, createDailyPlayerSummary(player));
  });

  const totals = {
    eventCount: events.length,
    activePlayers: 0,
    craft: 0,
    production: 0,
    build: 0,
    repair: 0,
    capture: 0,
    collection: 0,
    fishing: 0,
    levelUps: 0,
    boss: 0,
    discovery: 0,
    progress: 0,
    challenge: 0,
    quest: 0,
    loot: 0,
    note: 0,
    mutation: 0,
    death: 0,
    recovery: 0,
    adventure: 0,
    rare: 0,
    onlineSeconds: 0,
    presenceSessions: 0,
  };
  const typeCounts = new Map();
  const craftedItems = new Map();
  const producedItems = new Map();
  const palFinds = new Map();
  const hourly = Array.from({ length: 24 }, (_, hour) => ({ hour, count: 0 }));
  const highlights = [];

  for (const event of events) {
    const date = parseDate(event.occurredAt);
    const hour = dailyHourFromDate(date);
    if (hour != null && hourly[hour]) hourly[hour].count += 1;
    const type = event.type || "server";
    typeCounts.set(type, (typeCounts.get(type) || 0) + 1);

    const playerName = String(event.player || "Monde").trim() || "Monde";
    if (!players.has(playerName)) players.set(playerName, createDailyPlayerSummary(playerName));
    const player = players.get(playerName);
    const quantities = dailyEventQuantities(event);
    const highlight = dailyHighlightFromEvent(event, quantities);
    const itemEntries = dailyItemsFromEvent(event);
    const palEntries = dailyPalEntriesFromEvent(event);

    player.eventCount += 1;
    player.typeCounts.set(type, (player.typeCounts.get(type) || 0) + 1);
    addDailyQuantities(player.metrics, quantities);
    itemEntries.forEach((entry) => {
      if (entry.type === "craft") {
        dailyAddAggregate(craftedItems, entry);
        dailyAddAggregate(player.craftedItems, entry);
      } else if (entry.type === "production") {
        dailyAddAggregate(producedItems, entry);
        dailyAddAggregate(player.producedItems, entry);
      }
    });
    palEntries.forEach((entry) => {
      dailyAddAggregate(palFinds, entry);
      dailyAddAggregate(player.palFinds, entry);
    });
    player.score += dailyImpactScore(quantities);
    if (!player.firstAt || date < player.firstAt) player.firstAt = date;
    if (!player.lastAt || date > player.lastAt) player.lastAt = date;
    addDailyQuantities(totals, quantities);

    if (highlight.score >= 54 || highlights.length < 24) {
      highlights.push(highlight);
      player.highlights.push(highlight);
    }
  }

  players.forEach((player) => {
    applyDailyPresence(player, dateKey);
    totals.onlineSeconds += Number(player.dailyOnlineSeconds || 0);
    totals.presenceSessions += Number(player.dailySessionCount || 0);
  });

  const playerSummaries = [...players.values()].sort((left, right) => (
    Number(dailyPlayerHasActivity(right)) - Number(dailyPlayerHasActivity(left)) ||
    right.score - left.score ||
    String(left.name).localeCompare(String(right.name), "fr-CA")
  ));
  totals.activePlayers = playerSummaries.filter((player) => dailyPlayerHasActivity(player) && player.name !== "Monde").length;

  return {
    dateKey,
    events,
    totals,
    typeCounts,
    craftedItems,
    producedItems,
    palFinds,
    hourly,
    players: playerSummaries,
    highlights: highlights
      .sort((left, right) => right.score - left.score || right.timestamp - left.timestamp)
      .slice(0, 14),
  };
}

function renderDailyDateControls(dateKey) {
  if (!dailyDateInput) return;
  dailyDateInput.value = dateKey || "";
  dailyDateInput.min = dailyAvailableDateKeys.at(-1) || "";
  dailyDateInput.max = dailyAvailableDateKeys[0] || "";
  const index = dailyAvailableDateKeys.indexOf(dateKey);
  if (dailyPrevious) dailyPrevious.disabled = index < 0 || index >= dailyAvailableDateKeys.length - 1;
  if (dailyNext) dailyNext.disabled = index <= 0;
  if (dailyToday) dailyToday.disabled = dateKey === dailyDateKeyFromDate(new Date());
}

function renderDailyMetric(label, value, detail, tone = "", tooltip = "") {
  return `
    <article class="daily-metric ${tone ? `daily-metric--${escapeHtml(tone)}` : ""}"${tooltip ? ` tabindex="0" data-tooltip="${escapeHtml(tooltip)}"` : ""}>
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
      <small>${escapeHtml(detail)}</small>
    </article>`;
}

function dailyPlayerReasons(player) {
  if (!player) return "";
  if (!Number(player.eventCount || 0)) {
    if (player.dailyPresenceObserved && Number(player.dailyOnlineSeconds || 0) > 0) {
      return `${formatCompactDuration(player.dailyOnlineSeconds)} de présence observée`;
    }
    if (player.dailyPresenceObserved) return "présence repérée";
    const lastTrace = player.lastSeenAt || player.lastOnlineAt || player.lastSessionEndedAt;
    return lastTrace
      ? `aucune trace ce jour-là; dernière trace ${dailyShortDateTime(lastTrace)}`
      : "aucune trace ce jour-là";
  }
  const metrics = player.metrics || {};
  const reasons = [
    { label: "niveaux gagnés", singular: "niveau gagné", value: Number(metrics.levelUps || 0) },
    { label: "de présence observée", value: Number(player.dailyOnlineSeconds || 0), format: (value) => formatCompactDuration(value) },
    { label: "ressources produites", singular: "ressource produite", value: Number(metrics.production || 0) },
    { label: "objets fabriqués", singular: "objet fabriqué", value: Number(metrics.craft || 0) },
    { label: "captures Paldex", singular: "capture Paldex", value: Number(metrics.capture || 0) },
    { label: "ajouts collection", singular: "ajout collection", value: Number(metrics.collection || 0) },
    { label: "structures", singular: "structure", value: Number(metrics.build || 0) + Number(metrics.repair || 0) },
    { label: "faits", singular: "fait", value: dailyFactTotal(metrics) },
  ].filter((reason) => reason.value > 0)
    .sort((left, right) => right.value - left.value)
    .slice(0, 3)
    .map((reason) => `${reason.format ? reason.format(reason.value) : formatInteger(reason.value)} ${reason.value === 1 && reason.singular ? reason.singular : reason.label}`);
  return reasons.length ? reasons.join(" · ") : "activité discrète mais présente";
}

function renderDailyBrief(summary) {
  const active = summary.players.filter((player) => dailyPlayerHasActivity(player) && player.name !== "Monde");
  const leader = [...active].sort((left, right) => Number(right.score || 0) - Number(left.score || 0)
    || String(left.name).localeCompare(String(right.name), "fr-CA"))[0];
  const busiestHour = [...summary.hourly].sort((left, right) => right.count - left.count)[0];
  const topHighlight = summary.highlights[0];
  const topCraft = dailyTopAggregates(summary.craftedItems, 1)[0];
  const topProduction = dailyTopAggregates(summary.producedItems, 1)[0];
  const topPal = dailyTopAggregates(dailyConsolidatedPalFinds(summary), 1)[0];
  const palSignals = dailyPalSignalTotal(summary);
  const factTotal = dailyFactTotal(summary.totals);
  const lead = summary.presenceAvailable === false
    ? (summary.totals.eventCount
      ? `${dailyPlural(summary.totals.activePlayers, "joueur dans les échos", "joueurs dans les échos")} · ${dailyPlural(summary.totals.eventCount, "moment publié", "moments publiés")}`
      : "Aucun moment publié pour cette journée.")
    : (summary.totals.eventCount || summary.totals.presenceSessions
      ? `${dailyPlural(summary.totals.activePlayers, "joueur actif", "joueurs actifs")} · ${dailyPlural(summary.totals.eventCount, "moment publié", "moments publiés")}`
      : "Aucun fait ni présence pour cette journée.");
  const workshopLine = [
    summary.totals.craft ? dailyPlural(summary.totals.craft, "objet fabriqué", "objets fabriqués") : "",
    summary.totals.production ? dailyPlural(summary.totals.production, "ressource produite", "ressources produites") : "",
  ].filter(Boolean).join(" · ");
  const workshopDetail = [topCraft ? `fabrication: ${topCraft.name}` : "", topProduction ? `production: ${topProduction.name}` : ""]
    .filter(Boolean).join(" · ");
  const palLine = palSignals
    ? `${dailyPlural(palSignals, "Pal repéré", "Pals repérés")}${topPal ? ` · ${topPal.name} ressort le plus` : " dans les captures et collections"}`
    : "Aucune capture ou collection marquante.";
  return `
    <div class="daily-brief__lead">
      <strong>${escapeHtml(dailyDisplayDate(summary.dateKey))}</strong>
      <span>${lead}</span>
    </div>
    <ul class="daily-brief__list">
      <li><b>Joueur qui ressort</b><span>${leader ? `${leader.name}: ${dailyPlayerReasons(leader)}` : "Personne ne se démarque nettement."}</span></li>
      <li><b>Ateliers et bases</b><span>${workshopLine ? `${workshopLine}${workshopDetail ? ` · ${workshopDetail}` : ""}` : "Peu de fabrication ou production visible."}</span></li>
      <li><b>Pals</b><span>${palLine}</span></li>
      <li><b>Progression</b><span>${dailyPlural(summary.totals.levelUps, "niveau gagné", "niveaux gagnés")} · ${dailyPlural(factTotal, "fait marquant", "faits marquants")}</span></li>
      <li><b>Moment fort</b><span>${topHighlight ? `${topHighlight.player}: ${topHighlight.headline}` : "Rien d'inhabituel à signaler."}</span></li>
      <li><b>Rythme</b><span>${busiestHour?.count ? `${String(busiestHour.hour).padStart(2, "0")} h est la période la plus animée` : "Pas assez de données pour dégager un pic."}</span></li>
    </ul>
    <div class="daily-type-strip">
      ${[topCraft, topProduction, topPal].filter(Boolean).map((entry) => `<span style="--type-color:${escapeHtml(entry.type === "production" ? "#ef7164" : ["capture", "collection", "pal"].includes(entry.type) ? "#40c875" : "#a06ad7")}"><b>${escapeHtml(entry.name)}</b>${escapeHtml(dailyAggregateQuantityLabel(entry))}</span>`).join("")}
    </div>`;
}

function renderDailyHourly(summary) {
  const max = Math.max(1, ...summary.hourly.map((entry) => entry.count));
  return summary.hourly.map((entry) => {
    const height = Math.max(5, Math.round((entry.count / max) * 100));
    return `
      <span class="daily-hour" tabindex="0" data-tooltip="${String(entry.hour).padStart(2, "0")} h · ${dailyPlural(entry.count, "fait de la journée", "faits de la journée")}" style="--hour-height:${height}%">
        <i></i><b>${entry.hour % 3 === 0 ? `${String(entry.hour).padStart(2, "0")}h` : ""}</b>
      </span>`;
  }).join("");
}

function renderDailyTypes(summary) {
  const groups = [
    {
      title: "Objets fabriqués",
      empty: "Aucune fabrication détectée.",
      accent: "#a06ad7",
      total: summary.totals.craft,
      rows: dailyTopAggregates(summary.craftedItems, 6),
      filter: "craft",
      tooltip: "Clique pour revoir les fabrications qui ressortent dans la journée.",
    },
    {
      title: "Ressources produites",
      empty: "Aucune production détectée.",
      accent: "#ef7164",
      total: summary.totals.production,
      rows: dailyTopAggregates(summary.producedItems, 6),
      filter: "production",
      tooltip: "Clique pour revoir les productions qui ressortent dans la journée.",
    },
    {
      title: "Pals repérés",
      empty: "Des captures et collections sont comptées, mais aucun Pal ne ressort encore par nom.",
      accent: "#40c875",
      total: dailyPalSignalTotal(summary),
      rows: dailyTopAggregates(dailyConsolidatedPalFinds(summary), 6),
      filter: "pal",
      tooltip: "Clique pour revoir les captures et ajouts de Pals qui ressortent.",
    },
  ];
  return groups.map((group) => {
    const active = dailyHighlightTypeFilter === group.filter;
    return `
    <article class="daily-tangible-card${active ? " is-active" : ""}" style="--tangible-color:${escapeHtml(group.accent)}" tabindex="0" role="button" aria-pressed="${active ? "true" : "false"}" data-daily-type-filter="${escapeHtml(group.filter)}" data-tooltip="${escapeHtml(active ? "Filtre actif. Clique pour revoir tous les moments." : group.tooltip)}">
      <header>
        <span>${escapeHtml(group.title)}</span>
        <strong>${formatInteger(group.total)}</strong>
      </header>
      <ol class="daily-item-list">
        ${group.rows.length ? group.rows.map((row) => `
          <li data-tooltip="${escapeHtml(`${row.name}: ${dailyAggregateQuantityLabel(row)} · ${dailyAggregatePlayersLabel(row, 3)}`)}">
            ${row.icon ? gameImage(row.icon, row.name, "daily-item-icon") : `<span class="daily-item-icon daily-item-icon--empty">${escapeHtml(playerInitials(row.name))}</span>`}
            <span><b>${escapeHtml(row.name)}</b><small>${escapeHtml(`${dailyAggregateShortKind(row)} · ${dailyAggregatePlayersLabel(row, 2)}`)}</small></span>
            <strong>${formatInteger(row.quantity)}</strong>
          </li>`).join("") : `<li class="daily-item-list__empty">${escapeHtml(group.empty)}</li>`}
      </ol>
    </article>`;
  }).join("");
}

function dailyPlayerFactLabels(player) {
  const metrics = player.metrics || {};
  const facts = [
    { label: "Boss", value: metrics.boss },
    { label: "Découvertes", value: metrics.discovery },
    { label: "Défis", value: metrics.challenge },
    { label: "Progrès", value: metrics.progress },
    { label: "Mutations", value: metrics.mutation },
    { label: "Objets uniques", value: metrics.loot },
    { label: "Notes", value: metrics.note },
    { label: "Pêche", value: metrics.fishing },
    { label: "Retours", value: metrics.recovery },
    { label: "K.O.", value: metrics.death },
  ].filter((fact) => Number(fact.value || 0) > 0)
    .sort((left, right) => Number(right.value || 0) - Number(left.value || 0) || left.label.localeCompare(right.label, "fr-CA"));
  return facts.slice(0, 4);
}

function dailyPlayerTopLine(player) {
  const topCraft = dailyTopAggregates(player.craftedItems, 1)[0];
  const topProduction = dailyTopAggregates(player.producedItems, 1)[0];
  const topPal = dailyTopAggregates(dailyConsolidatedPalFinds(player), 1)[0];
  const pieces = [
    topCraft ? `Fabrication: ${topCraft.name} (${formatInteger(topCraft.quantity)})` : "",
    topProduction ? `Production: ${topProduction.name} (${formatInteger(topProduction.quantity)})` : "",
    topPal ? `${dailyAggregateShortKind(topPal)}: ${topPal.name} (${formatInteger(topPal.quantity)})` : "",
  ].filter(Boolean);
  return pieces.slice(0, 2).join(" · ") || "Aucune fabrication, production ou capture dominante dans les données du jour.";
}

function dailyPlayerLastTrace(player) {
  return player?.lastSeenAt || player?.lastOnlineAt || player?.lastSessionEndedAt || null;
}

function dailyPlayerPresenceFocus(player) {
  if (Number(player?.eventCount || 0) > 0) return dailyPlayerTopLine(player);
  if (player?.dailyPresenceObserved && Number(player?.dailyOnlineSeconds || 0) > 0) {
    return `Présence observée ${formatCompactDuration(player.dailyOnlineSeconds)}; aucun moment du journal attribué pendant cette journée.`;
  }
  if (player?.dailyPresenceObserved) {
    return "Présence repérée ce jour-là.";
  }
  const lastTrace = dailyPlayerLastTrace(player);
  return lastTrace
    ? `Aucune présence ni moment publié le ${dailyDisplayDate(dailySelectedDateKey, { short: true })}; dernière trace ${dailyShortDateTime(lastTrace)}.`
    : `Aucune présence ni moment publié pour ${dailyDisplayDate(dailySelectedDateKey, { short: true })}.`;
}

function renderDailyPresenceHighlights(player) {
  if (!player?.dailyPresenceObserved || !Array.isArray(player.dailySessions)) return [];
  return player.dailySessions.slice(0, 2).map((session) => {
    const start = session.boundedStart || parseDate(session.startedAt);
    const duration = Number(session.seconds || 0) > 0
      ? formatCompactDuration(session.seconds)
      : "durée inconnue";
    return {
      occurredAt: session.startedAt,
      time: start ? formatTime(start) : "--",
      headline: session.observedOnly ? "Présence détectée" : `Session observée · ${duration}`,
      score: Number(session.seconds || 0),
      timestamp: start ? start.getTime() : 0,
    };
  });
}

function renderDailyPlayerCard(player) {
  const highlights = [
    ...player.highlights,
    ...renderDailyPresenceHighlights(player),
  ]
    .sort((left, right) => right.score - left.score || right.timestamp - left.timestamp)
    .slice(0, 2);
  const facts = dailyPlayerFactLabels(player);
  const meta = [
    player.level != null ? `Niveau ${formatInteger(player.level)}` : "",
    player.guild || "",
    player.pals != null ? `${formatInteger(player.pals)} Pals` : "",
  ].filter(Boolean).join(" · ");
  const playerAccent = playerColor(player.name);
  const palTotal = dailyPalSignalTotal(player);
  const factTotal = dailyFactTotal(player.metrics);
  const hasPublishedEchoes = Number(player.eventCount || 0) > 0;
  const hasDailyActivity = dailyPlayerHasActivity(player);
  const lastTrace = dailyPlayerLastTrace(player);
  const presenceStat = player.presenceAvailable === false
    ? `<span data-tooltip="Moments attribués à ce joueur pendant la journée."><b>${formatInteger(player.eventCount)}</b><small>Moments</small></span>`
    : `<span data-tooltip="${escapeHtml("Durée de présence estimée depuis les sessions observées.")}"><b>${player.dailyOnlineSeconds ? formatCompactDuration(player.dailyOnlineSeconds) : "--"}</b><small>Présence</small></span>`;
  const statsMarkup = hasPublishedEchoes ? `
        <span data-tooltip="${escapeHtml("Montées de niveau détectées pendant la journée.")}"><b>${formatInteger(player.metrics.levelUps)}</b><small>Niveaux gagnés</small></span>
        <span data-tooltip="${escapeHtml("Captures et ajouts de collection regroupés par Pal.")}"><b>${formatInteger(palTotal)}</b><small>Pals repérés</small></span>
        <span data-tooltip="${escapeHtml("Quantités ajoutées par les événements de fabrication.")}"><b>${formatInteger(player.metrics.craft)}</b><small>Objets fabriqués</small></span>
        <span data-tooltip="${escapeHtml("Ressources prêtes ou sorties de production dans les bases.")}"><b>${formatInteger(player.metrics.production)}</b><small>Ressources produites</small></span>
        ${presenceStat}
        <span data-tooltip="${escapeHtml("Découvertes, défis, boss, mutations, notes, pêche et autres faits non routiniers.")}"><b>${formatInteger(factTotal)}</b><small>Faits divers</small></span>` : hasDailyActivity ? `
        <span data-tooltip="${escapeHtml("Durée de présence estimée depuis les sessions observées.")}"><b>${player.dailyOnlineSeconds ? formatCompactDuration(player.dailyOnlineSeconds) : "--"}</b><small>Présence</small></span>
        <span data-tooltip="${escapeHtml("Sessions observées pendant la journée sélectionnée.")}"><b>${formatInteger(player.dailySessionCount)}</b><small>Sessions du jour</small></span>
        <span data-tooltip="${escapeHtml("Aucun moment attribué à ce joueur pour cette journée.")}"><b>0</b><small>Moments</small></span>
        <span data-tooltip="${escapeHtml("Niveau actuel du joueur.")}"><b>${player.level != null ? formatInteger(player.level) : "--"}</b><small>Niveau actuel</small></span>` : `
        <span data-tooltip="${escapeHtml("Niveau actuel du joueur.")}"><b>${player.level != null ? formatInteger(player.level) : "--"}</b><small>Niveau actuel</small></span>
        <span data-tooltip="${escapeHtml("Nombre actuel de Pals du joueur.")}"><b>${player.pals != null ? formatInteger(player.pals) : "--"}</b><small>Pals actuels</small></span>
        <span data-tooltip="${escapeHtml(lastTrace ? `Dernière trace: ${formatDateTime(lastTrace)}` : "Aucune trace de présence.")}"><b>${lastTrace ? dailyShortDate(lastTrace) : "--"}</b><small>Dernière trace</small></span>`;
  return `
    <article class="daily-player-card${hasDailyActivity ? "" : " daily-player-card--quiet"}" style="--player-color:${escapeHtml(playerAccent)};--card-accent:${escapeHtml(playerAccent)}" tabindex="0" data-tooltip="${escapeHtml(`Score de journée: ${Math.round(Number(player.score || 0))} · ${dailyPlayerReasons(player)}`)}">
      <header>
        <span class="daily-player-card__avatar">${escapeHtml(playerInitials(player.name))}</span>
        <span><strong>${escapeHtml(player.name)}</strong><small>${escapeHtml(meta || "Profil")}</small></span>
      </header>
      <div class="daily-player-card__stats">
        ${statsMarkup}
      </div>
      <p class="daily-player-card__focus">${escapeHtml(dailyPlayerPresenceFocus(player))}</p>
      <div class="daily-player-card__types">
        ${facts.length ? facts.map((fact) => `<span>${escapeHtml(fact.label)} ${formatInteger(fact.value)}</span>`).join("") : player.dailyPresenceObserved ? `<span>Présence ${escapeHtml(formatCompactDuration(player.dailyOnlineSeconds))}</span>` : "<span>Aucun fait divers marquant</span>"}
      </div>
      <ul class="daily-player-card__highlights">
        ${highlights.length ? highlights.map((highlight) => `<li><time${highlight.occurredAt ? ` datetime="${escapeHtml(highlight.occurredAt)}" data-tooltip="${escapeHtml(formatDateTime(highlight.occurredAt))}"` : ""}>${escapeHtml(highlight.time)}</time><span>${escapeHtml(highlight.headline)}</span></li>`).join("") : `<li class="daily-player-card__empty"><span>${escapeHtml(hasDailyActivity ? "Pas de fait marquant détecté ce jour-là." : "Pas de présence détectée ce jour-là.")}</span></li>`}
      </ul>
    </article>`;
}

function dailySyntheticHighlights(summary) {
  const active = summary.players.filter((player) => dailyPlayerHasActivity(player) && player.name !== "Monde");
  const leader = [...active].sort((left, right) => Number(right.score || 0) - Number(left.score || 0)
    || String(left.name).localeCompare(String(right.name), "fr-CA"))[0];
  const topCraft = dailyTopAggregates(summary.craftedItems, 1)[0];
  const topProduction = dailyTopAggregates(summary.producedItems, 1)[0];
  const topPal = dailyTopAggregates(dailyConsolidatedPalFinds(summary), 1)[0];
  const rows = [];
  if (leader) {
    rows.push({
      type: "daily-leader",
      player: leader.name,
      time: "Bilan",
      headline: "Joueur qui se démarque",
      body: dailyPlayerReasons(leader),
      badge: "Cumul",
      accent: playerColor(leader.name),
      score: 999,
    });
  }
  if (topCraft) {
    rows.push({
      type: "daily-craft",
      player: dailyAggregatePlayersLabel(topCraft, 1).split(" ")[0] || "Atelier",
      time: "Bilan",
      headline: `${topCraft.name} domine les fabrications`,
      body: `${dailyAggregateQuantityLabel(topCraft)} · ${dailyAggregatePlayersLabel(topCraft, 3)}`,
      badge: "Objet",
      accent: "#a06ad7",
      score: 998,
    });
  }
  if (topProduction) {
    rows.push({
      type: "daily-production",
      player: dailyAggregatePlayersLabel(topProduction, 1).split(" ")[0] || "Base",
      time: "Bilan",
      headline: `${topProduction.name} ressort en production`,
      body: `${dailyAggregateQuantityLabel(topProduction)} · ${dailyAggregatePlayersLabel(topProduction, 3)}`,
      badge: "Ressource",
      accent: "#ef7164",
      score: 997,
    });
  }
  if (topPal) {
    rows.push({
      type: "daily-pal",
      player: dailyAggregatePlayersLabel(topPal, 1).split(" ")[0] || "Pals",
      time: "Bilan",
      headline: `${topPal.name} ressort côté Pals`,
      body: `${dailyAggregateQuantityLabel(topPal)} · ${dailyAggregatePlayersLabel(topPal, 3)}`,
      badge: "Pal",
      accent: "#40c875",
      score: 996,
    });
  }
  return rows;
}

function dailyCuratedEventHighlights(summary, limit = 10) {
  const selected = [];
  const typeCounts = new Map();
  const playerCounts = new Map();
  const primary = summary.highlights.filter((highlight) => !["recovery", "death"].includes(highlight.type));
  const fallback = summary.highlights.filter((highlight) => ["recovery", "death"].includes(highlight.type));
  for (const highlight of [...primary, ...fallback]) {
    const typeCount = typeCounts.get(highlight.type) || 0;
    const playerCount = playerCounts.get(highlight.player) || 0;
    if (typeCount >= 3 || playerCount >= 4) continue;
    selected.push(highlight);
    typeCounts.set(highlight.type, typeCount + 1);
    playerCounts.set(highlight.player, playerCount + 1);
    if (selected.length >= limit) break;
  }
  return selected;
}

function dailyHighlightMatchesFilter(highlight, filter) {
  if (!filter) return true;
  const type = String(highlight?.type || "");
  if (filter === "pal") return ["capture", "collection", "daily-pal"].includes(type);
  if (filter === "craft") return ["craft", "daily-craft"].includes(type);
  if (filter === "production") return ["production", "daily-production"].includes(type);
  return type === filter;
}

function dailyHighlightFilterLabel(filter) {
  if (filter === "craft") return "les fabrications";
  if (filter === "production") return "les productions";
  if (filter === "pal") return "les Pals";
  return "ce filtre";
}

function renderDailyHighlights(summary) {
  const allHighlights = [
    ...dailySyntheticHighlights(summary),
    ...dailyCuratedEventHighlights(summary, 10),
  ];
  const highlights = allHighlights
    .filter((highlight) => dailyHighlightMatchesFilter(highlight, dailyHighlightTypeFilter))
    .slice(0, 14);
  if (!highlights.length && dailyHighlightTypeFilter) {
    return `<li class="daily-empty">Rien de notable pour ${escapeHtml(dailyHighlightFilterLabel(dailyHighlightTypeFilter))} dans les moments retenus. <button type="button" class="daily-filter-reset" data-daily-filter-reset>Revoir toute la journée</button></li>`;
  }
  if (!highlights.length) return '<li class="daily-empty">Aucun moment marquant détecté pour cette journée.</li>';
  return highlights.map((highlight) => {
    const badge = highlight.confidence === "derived" ? "Rattaché à la guilde" : highlight.badge;
  const badgeTitle = highlight.confidence === "derived" ? ' title="Cet écho vient de la guilde; le joueur affiché est le meilleur repère disponible."' : "";
    return `
    <li class="daily-highlight" style="--highlight-color:${escapeHtml(highlight.accent)}">
      <time>${escapeHtml(highlight.time)}</time>
      <span>
        <b>${escapeHtml(highlight.player)}</b>
        <strong>${escapeHtml(highlight.headline)}</strong>
        <small>${escapeHtml(highlight.body)}</small>
      </span>
      ${badge ? `<em${badgeTitle}>${escapeHtml(badge)}</em>` : ""}
    </li>`;
  }).join("");
}

function renderDailyDigest(summary) {
  if (!dailyMetrics) return;
  if (dailyCurrentSummary?.dateKey !== summary.dateKey) dailyHighlightTypeFilter = "";
  dailyCurrentSummary = summary;
  const totals = summary.totals;
  if (dailyStatus) {
    dailyStatus.textContent = totals.eventCount || (summary.presenceAvailable !== false && totals.presenceSessions)
      ? `${dailyPlural(totals.activePlayers, summary.presenceAvailable === false ? "joueur dans le journal" : "joueur actif", summary.presenceAvailable === false ? "joueurs dans le journal" : "joueurs actifs")} · journée prête`
      : summary.presenceAvailable === false ? "Aucun moment publié pour cette journée" : "Aucun fait ni présence pour cette journée";
  }
  if (dailyUpdatedAt) {
    dailyUpdatedAt.textContent = eventsIndexSnapshot?.updatedAt
      ? `Journal actualisé ${formatRelativeAge(eventsIndexSnapshot.updatedAt)}`
      : "Synchronisation en attente";
  }
  const leader = summary.players.filter((player) => dailyPlayerHasActivity(player) && player.name !== "Monde")
    .sort((left, right) => Number(right.score || 0) - Number(left.score || 0)
      || String(left.name).localeCompare(String(right.name), "fr-CA"))[0];
  const topCraft = dailyTopAggregates(summary.craftedItems, 1)[0];
  const topProduction = dailyTopAggregates(summary.producedItems, 1)[0];
  const topPal = dailyTopAggregates(dailyConsolidatedPalFinds(summary), 1)[0];
  const palSignals = dailyPalSignalTotal(summary);
  const topLevelPlayer = summary.players.filter((player) => Number(player.metrics?.levelUps || 0) > 0)
    .sort((left, right) => Number(right.metrics?.levelUps || 0) - Number(left.metrics?.levelUps || 0)
      || Number(right.score || 0) - Number(left.score || 0)
      || String(left.name).localeCompare(String(right.name), "fr-CA"))[0];
  const factTotal = dailyFactTotal(totals);
  const palMetricDetail = topPal
    ? dailyTopAggregateLabel(topPal, "Aucun Pal dominant", { withDont: true })
    : palSignals
      ? "Captures et collections repérées dans la journée"
      : "Aucun Pal dominant";
  dailyMetrics.innerHTML = [
    renderDailyMetric("Joueur du jour", leader?.name || "--", leader ? dailyPlayerReasons(leader) : "Aucune activité joueur", "events", "Score pondéré par niveaux, captures, fabrications, productions, bases et faits non routiniers."),
    renderDailyMetric("Objets fabriqués", formatInteger(totals.craft), dailyTopAggregateLabel(topCraft, "Aucun objet dominant", { withDont: true }), "craft", "Somme des quantités ajoutées par les fabrications du jour."),
    renderDailyMetric("Ressources produites", formatInteger(totals.production), dailyTopAggregateLabel(topProduction, "Aucune ressource dominante", { withDont: true }), "production", "Somme des ressources prêtes dans les productions du jour."),
    renderDailyMetric("Pals repérés", formatInteger(palSignals), palMetricDetail, "capture", "Captures et ajouts de collection regroupés par Pal."),
    renderDailyMetric("Niveaux gagnés", formatInteger(totals.levelUps), topLevelPlayer ? `dont ${topLevelPlayer.name} · ${dailyPlural(topLevelPlayer.metrics.levelUps, "niveau gagné", "niveaux gagnés")}` : "Aucune montée détectée", "level", "Montées de niveau détectées pendant la journée."),
    renderDailyMetric("Structures", formatInteger(totals.build), `dont ${dailyPlural(totals.repair, "structure réparée", "structures réparées")}`, "base", "Structures ajoutées et réparations détectées dans les bases."),
    renderDailyMetric("Faits divers", formatInteger(factTotal), `dont ${dailyPlural(totals.boss, "boss", "boss")} · ${dailyPlural(totals.discovery, "découverte")}`, "rare", "Boss, découvertes, défis, mutations, notes, pêche et autres faits moins routiniers."),
  ].join("");
  if (dailyBrief) dailyBrief.innerHTML = renderDailyBrief(summary);
  if (dailyHourly) dailyHourly.innerHTML = renderDailyHourly(summary);
  if (dailyTypes) dailyTypes.innerHTML = renderDailyTypes(summary);
  if (dailyPlayers) {
    const playerCards = summary.players.filter((player) => player.name !== "Monde");
    dailyPlayers.innerHTML = playerCards.length
      ? playerCards.map(renderDailyPlayerCard).join("")
      : '<p class="daily-empty">Aucun joueur actif repéré pour cette journée.</p>';
  }
  if (dailyHighlights) dailyHighlights.innerHTML = renderDailyHighlights(summary);
}

function dailyV6Map(value) {
  const rows = Array.isArray(value)
    ? value
    : value && typeof value === "object"
      ? Object.entries(value).map(([key, row]) => typeof row === "object" ? { key, ...row } : { key, name: key, quantity: row })
      : [];
  return new Map(rows.map((row, index) => {
    const players = row?.players instanceof Map
      ? row.players
      : new Map(Object.entries(row?.players || {}));
    const key = String(row?.key || row?.name || index);
    const normalized = {
      ...row,
      key,
      name: String(row?.name || row?.label || row?.species || row?.key || "Pal").trim() || "Pal",
      quantity: Math.max(0, dailyNumber(row?.quantity ?? row?.count ?? row?.total ?? row?.captures ?? row?.added ?? 0)),
      players,
    };
    return [key, normalized];
  }).filter(([, row]) => row.quantity > 0 || row.name));
}

function normalizeDailyV6Digest(payload) {
  const digest = payload?.digest;
  if (!digest?.totals || !Array.isArray(digest.hourly) || !Array.isArray(digest.players)) return null;
  const metricDefaults = {
    craft: 0, production: 0, build: 0, repair: 0, capture: 0, collection: 0,
    fishing: 0, levelUps: 0, boss: 0, discovery: 0, progress: 0, challenge: 0,
    quest: 0, loot: 0, note: 0, mutation: 0, death: 0, recovery: 0, adventure: 0, rare: 0,
  };
  const players = digest.players.map((player) => {
    const eventCount = Number(player.eventCount ?? player.echoes ?? 0);
    return {
      ...createDailyPlayerSummary(player),
      ...player,
      presenceAvailable: false,
      eventCount,
      score: Number(player.score ?? eventCount),
      metrics: { ...metricDefaults, ...(player.metrics || {}) },
      typeCounts: dailyV6Map(player.typeCounts || player.types),
      craftedItems: dailyV6Map(player.craftedItems),
      producedItems: dailyV6Map(player.producedItems),
      palFinds: dailyV6Map(player.palFinds),
      highlights: (Array.isArray(player.highlights) ? player.highlights : []).map((highlight) => ({
        ...highlight,
        time: highlight.time || formatTime(highlight.occurredAt),
        timestamp: Number(highlight.timestamp || parseDate(highlight.occurredAt)?.getTime() || 0),
      })),
    };
  });
  const latestHighlights = sortEventsNewestFirst(
    (payload.latest || []).filter(eventCanBePublished),
    { canonical: true },
  ).map((event) => {
    const quantities = dailyEventQuantities(event);
    return dailyHighlightFromEvent(event, quantities);
  });
  const digestHighlights = (digest.highlights || []).filter(eventCanBePublished).map((highlight) => ({
    ...highlight,
    time: highlight.time || formatTime(highlight.occurredAt),
    timestamp: Number(highlight.timestamp || parseDate(highlight.occurredAt)?.getTime() || 0),
    accent: highlight.accent || (highlight.player ? playerColor(highlight.player) : eventTypeMeta[highlight.type]?.color || "#77a7be"),
    badge: highlight.badge || eventTypeMeta[highlight.type]?.label || "Écho",
  }));
  return {
    dateKey: payload.date,
    presenceAvailable: false,
    events: [],
    totals: {
      eventCount: Number(payload.counts?.echoes || digest.totals.eventCount || 0),
      activePlayers: Number(digest.totals.activePlayers || players.length),
      onlineSeconds: 0,
      presenceSessions: 0,
      ...metricDefaults,
      ...digest.totals,
    },
    typeCounts: dailyV6Map(digest.typeCounts || digest.types || payload.types),
    craftedItems: dailyV6Map(digest.craftedItems),
    producedItems: dailyV6Map(digest.producedItems),
    palFinds: dailyV6Map(digest.palFinds),
    hourly: digest.hourly.map((entry, hour) => ({ hour: Number(entry?.hour ?? hour), count: Number(entry?.count || 0) })),
    players,
    highlights: digestHighlights.length ? digestHighlights : latestHighlights,
  };
}

function renderDailyV6Basic(payload) {
  const types = payload?.types || payload?.digest?.types || {};
  const players = Array.isArray(payload?.players) ? payload.players : [];
  const echoes = Number(payload?.counts?.echoes || 0);
  const represented = Number(payload?.counts?.representedEvents || 0);
  const derived = Number(payload?.counts?.derivedEchoes || 0);
  const typeRows = Object.entries(types)
    .map(([type, count]) => ({ type, count: Number(typeof count === "object" ? count.count : count || 0) }))
    .filter((entry) => entry.count > 0)
    .sort((left, right) => right.count - left.count);
  if (dailyStatus) dailyStatus.textContent = derived
    ? `${dailyPlural(players.length, "joueur dans le journal", "joueurs dans le journal")} · quelques actions rattachées à la guilde`
    : `${dailyPlural(players.length, "joueur dans le journal", "joueurs dans le journal")} · journée prête`;
  if (dailyUpdatedAt) dailyUpdatedAt.textContent = `Journal actualisé ${formatRelativeAge(payload.sourceUpdatedAt || payload.generatedAt)}`;
  if (dailyMetrics) dailyMetrics.innerHTML = [
    renderDailyMetric("Moments du jour", formatInteger(echoes), derived ? `${dailyPlural(derived, "action rattachée à la guilde", "actions rattachées à la guilde")}` : "Journée prête à lire", "events"),
    renderDailyMetric("Actions regroupées", formatInteger(represented), "Actions proches réunies pour garder une lecture claire", "rare"),
    renderDailyMetric("Aventuriers", formatInteger(players.length), "Joueurs présents dans le journal du jour", "capture"),
    ...typeRows.slice(0, 4).map((entry) => renderDailyMetric(eventTypeMeta[entry.type]?.label || entry.type, formatInteger(entry.count), "Moments de cette catégorie", entry.type)),
  ].join("");
  if (dailyBrief) dailyBrief.innerHTML = `
    <div class="daily-brief__lead"><strong>${escapeHtml(dailyDisplayDate(payload.date))}</strong><span>${dailyPlural(echoes, "moment retenu", "moments retenus")} · ${dailyPlural(represented, "action regroupée", "actions regroupées")}${derived ? ` · quelques rattachements à la guilde` : ""}</span></div>
    <ul class="daily-brief__list">${typeRows.slice(0, 6).map((entry) => `<li><b>${escapeHtml(eventTypeMeta[entry.type]?.label || entry.type)}</b><span>${dailyPlural(entry.count, "moment", "moments")}</span></li>`).join("") || "<li><span>Rien de notable publié pour cette journée.</span></li>"}</ul>`;
  if (dailyHourly) dailyHourly.innerHTML = '<p class="daily-empty">Le rythme détaillé arrivera avec le prochain bilan complet.</p>';
  if (dailyTypes) dailyTypes.innerHTML = typeRows.length
    ? `<article class="daily-tangible-card" style="--tangible-color:#176d70"><header><span>Ce qui a bougé</span><strong>${formatInteger(echoes)}</strong></header><ol class="daily-item-list">${typeRows.slice(0, 10).map((entry) => `<li><span><b>${escapeHtml(eventTypeMeta[entry.type]?.label || entry.type)}</b><small>Moments de la journée</small></span><strong>${formatInteger(entry.count)}</strong></li>`).join("")}</ol></article>`
    : '<p class="daily-empty">Aucune catégorie notable pour cette journée.</p>';
  if (dailyPlayers) dailyPlayers.innerHTML = players.length
    ? players.map((player) => `<article class="daily-player-card" style="--player-color:${escapeHtml(playerColor(player.name))};--card-accent:${escapeHtml(playerColor(player.name))}"><header><span class="daily-player-card__avatar">${escapeHtml(playerInitials(player.name))}</span><span><strong>${escapeHtml(player.name)}</strong><small>${dailyPlural(Number(player.echoes || 0), "moment", "moments")}</small></span></header></article>`).join("")
    : '<p class="daily-empty">Aucun joueur présent dans le journal de cette journée.</p>';
  const latest = Array.isArray(payload.latest)
    ? sortEventsNewestFirst(payload.latest.filter(eventCanBePublished), { canonical: true })
    : [];
  if (dailyHighlights) dailyHighlights.innerHTML = latest.length
    ? latest.map((event) => {
      const meta = eventTypeMeta[event.type] || eventTypeMeta.server;
      const badge = event.confidence === "derived" ? "Rattaché à la guilde" : meta.label;
      const badgeTitle = event.confidence === "derived" ? ' title="Cet écho vient de la guilde; le joueur affiché est le meilleur repère disponible."' : "";
      return `<li class="daily-highlight" style="--highlight-color:${escapeHtml(event.player ? playerColor(event.player) : meta.color)}"><time>${escapeHtml(formatTime(event.occurredAt))}</time><span><b>${escapeHtml(event.player || "Palpagos")}</b><strong>${escapeHtml(event.display?.headline || event.title || meta.label)}</strong><small>${escapeHtml(event.display?.body || event.message || "Moment publié")}</small></span><em${badgeTitle}>${escapeHtml(badge)}</em></li>`;
    }).join("")
    : '<li class="daily-empty">Aucun moment marquant publié pour cette journée.</li>';
}

async function loadDailyV6Payload(dateKey, manifest = eventsManifestV6) {
  const entry = v6DayEntry(dateKey, manifest);
  const generationId = String(entry?.dailyGenerationId || entry?.fragmentGenerationId || entry?.generationId || manifest?.generationId || "");
  if (!generationId || !v6DateCanBeOpened(dateKey, manifest)) throw new Error("v6-daily-unavailable");
  if (!entry) {
    return {
      schemaVersion: 6,
      ok: true,
      generationId,
      date: dateKey,
      generatedAt: manifest.generatedAt,
      sourceUpdatedAt: manifest.sourceUpdatedAt,
      freshness: manifest.freshness,
      sourceStatus: manifest.sourceStatus,
      cursor: { minId: 0, maxId: 0 },
      counts: { echoes: 0, representedEvents: 0, confirmedEchoes: 0, derivedEchoes: 0 },
      contentHash: `empty:${dateKey}`,
      digest: {
        totals: { eventCount: 0, activePlayers: 0, onlineSeconds: 0, presenceSessions: 0 },
        hourly: Array.from({ length: 24 }, (_, hour) => ({ hour, count: 0 })),
        types: {}, players: [], highlights: [], craftedItems: [], producedItems: [], palFinds: [],
      },
      latest: [],
    };
  }
  const path = v6PublicDataPath(entry.dailyPath || `data/public-daily/${generationId}/${dateKey}.json`, "data/public-daily/");
  if (!path) throw new Error("invalid-v6-daily-path");
  const cacheKey = `${generationId}:${path}:${dateKey}`;
  let payload = dailyV6Cache.get(cacheKey);
  if (!payload) {
    payload = await readJson(path, { immutable: true, expectedSha256: entry.dailySha256 });
    if (!v6GenerationIsValid(payload, generationId) || payload.date !== dateKey || !payload.digest) {
      throw new Error("mixed-v6-daily-generation");
    }
    dailyV6Cache.set(cacheKey, payload);
  }
  return payload;
}

async function renderDailyV6Candidate(candidate) {
  const availableDateKeys = v6NavigableDates(candidate.manifest);
  const requestedDate = dailySelectedDateKey || dailyRequestedDateKey();
  const selectedDate = availableDateKeys.includes(requestedDate) ? requestedDate : availableDateKeys[0];
  const { payload, state } = await stageAndCommitV6Candidate(
    candidate,
    () => loadDailyV6Payload(selectedDate, candidate.manifest),
    commitEventsV6Candidate,
  );
  if (state.generationChanged) clearV6GenerationCaches();
  dailyAvailableDateKeys = availableDateKeys;
  dailySelectedDateKey = selectedDate;
  renderDailyDateControls(selectedDate);
  registerPayloadDataUpdate("events", payload);
  const summary = normalizeDailyV6Digest(payload);
  if (summary) renderDailyDigest(summary);
  else renderDailyV6Basic(payload);
  const signature = `${payload.generationId}|${selectedDate}|${payload.contentHash || payload.generatedAt || ""}`;
  const changed = state.changed || signature !== dailyLastSignature;
  dailyLastSignature = signature;
  dailyRenderedGenerationId = String(candidate.manifest.generationId || "");
  return { ok: true, changed, stale: state.stale, mode: "v6" };
}

async function loadDailyDigest(silent = false) {
  if (!isDailyDigestRoute()) return { ok: true, changed: false };
  try {
    if (!silent && dailyStatus) dailyStatus.textContent = "Compilation de la journée...";
    const rollbackState = captureV6State();
    const candidate = await fetchEventsV6Candidate(true, true);
    if (candidate.ok) {
      try {
        return await renderDailyV6Candidate(candidate);
      } catch {
        const restored = restoreV6State(rollbackState);
        const previousGeneration = String(eventsManifestV6?.generationId || "");
        if (restored && dailyRenderedGenerationId && dailyRenderedGenerationId === previousGeneration) {
          return { ok: true, changed: false, stale: true, mode: "v6" };
        }
        if (restored && previousGeneration) {
          try {
            return {
              ...(await renderDailyV6Candidate({
                ok: true,
                manifest: eventsManifestV6,
                head: eventsHeadV6,
                generationId: previousGeneration,
                stale: true,
              })),
              changed: false,
              stale: true,
            };
          } catch {
            // Le repli v5 reste disponible si l’ancienne génération n’est plus lisible.
          }
        }
      }
    }
    eventsContractMode = "v5";
    const [indexResult] = await Promise.all([
      loadEventsIndex(true),
      loadDailyRoster(),
    ]);
    if (!eventsIndexSnapshot || !indexResult.ok) throw new Error("events-index-unavailable");
    dailyAvailableDateKeys = dailyAvailableKeysFromIndex();
    const selectedDate = dailyResolveSelectedDate();
    dailySelectedDateKey = selectedDate;
    renderDailyDateControls(selectedDate);
    const events = await loadDailyEventsForDate(selectedDate);
    const summary = buildDailyDigest(selectedDate, events);
    renderDailyDigest(summary);
    const signature = [
      eventsIndexSnapshot.revision || "",
      selectedDate,
      events.length,
      events[0]?.key || "",
      events.at(-1)?.key || "",
      dailyRosterPlayers.length,
      dailyStatsUpdatedAt,
    ].join("|");
    const changed = signature !== dailyLastSignature;
    dailyLastSignature = signature;
    dailyRenderedGenerationId = "";
    return { ok: true, changed };
  } catch {
    if (dailyStatus) dailyStatus.textContent = "Résumé quotidien momentanément indisponible";
    if (dailyMetrics) dailyMetrics.innerHTML = "";
    if (dailyBrief) dailyBrief.innerHTML = '<p class="daily-empty">Les données du jour seront réessayées au prochain rafraîchissement.</p>';
    return { ok: false, changed: false };
  }
}

async function selectDailyDate(key, updateUrl = true) {
  if (!isDailyDateKey(key)) return;
  dailySelectedDateKey = key;
  if (updateUrl) dailySetUrlDate(key);
  renderDailyDateControls(key);
  await loadDailyDigest(true);
  trackVirtualPageView();
}

function renderEventSummaryCards(payload) {
  const events = dedupeSessionFallbackEvents(payload?.events);
  if (eventsState) {
    const totalEvents = Number(payload?.summary?.totalEvents || events.length);
    if (totalEvents > events.length && payload?.recent) {
      eventsState.textContent = `${totalEvents.toLocaleString("fr-CA")} écho${totalEvents > 1 ? "s" : ""}`;
    } else if (payload?.truncated && totalEvents > events.length) {
      eventsState.textContent = `${events.length} échos affichés sur ${totalEvents.toLocaleString("fr-CA")}`;
    } else {
      eventsState.textContent = `${events.length} écho${events.length > 1 ? "s" : ""}`;
    }
    eventsState.dataset.state = "live";
  }
  registerPayloadDataUpdate("events", payload);
  renderWorldContractStatus();
}

function renderEventSnapshot(payload) {
  eventsSnapshot = payload?.recent
    ? mergeEventPayloads(payload, payload)
    : mergeEventPayloads(payload, eventsRecentSnapshot);
  renderEventSummaryCards(eventsSnapshot);
  renderEventSyncStatus(new Date(), eventsSnapshot.updatedAt);
  if (eventsDisclosure?.open) {
    renderEventFilters(eventsSnapshot.events || []);
    renderEvents();
  }
}

function renderEventSyncStatus(value, dataUpdatedAt = eventsSnapshot?.updatedAt) {
  if (!eventSyncStatus) return;
  const date = parseDate(value);
  if (!date) {
    eventSyncStatus.textContent = "Synchronisation en attente";
    return;
  }
  eventSyncStatus.textContent = `Synchro ${date.toLocaleTimeString("fr-CA", {
    hour: "2-digit",
    minute: "2-digit",
  })}`;
  eventSyncStatus.dateTime = date.toISOString();
  const dataDate = parseDate(dataUpdatedAt);
  eventSyncStatus.dataset.tooltip = dataDate
    ? `Derniers échos le ${formatDateTime(dataDate)}`
    : "Flux des échos synchronisé";
}

function gameImage(path, alt, className = "game-icon") {
  if (!path) {
    const fallback = String(alt || "?").trim().charAt(0).toLocaleUpperCase("fr-CA") || "?";
    return `<span class="${className} ${className}--empty game-asset--empty" ${alt ? `role="img" aria-label="Image indisponible pour ${escapeHtml(alt)}"` : 'aria-hidden="true"'}>${escapeHtml(fallback)}</span>`;
  }
  return `<img class="${className} game-asset" src="${escapeHtml(versionedGameAsset(path))}" alt="${escapeHtml(alt)}" loading="lazy" decoding="async">`;
}

function translateItemCategory(value) {
  const categories = {
    Armor: "Armure",
    Consumable: "Consommable",
    Essential: "Important",
    Food: "Nourriture",
    Glider: "Planeur",
    Material: "Matériau",
    Weapon: "Arme",
  };
  return categories[value] || value || "Objet";
}

function switchDetailTab(name, updateRoute = true) {
  let activeTab = null;
  document.querySelectorAll("[data-detail-tab]").forEach((button) => {
    const isActive = button.dataset.detailTab === name;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-selected", String(isActive));
    if (isActive) activeTab = button;
  });
  document.querySelectorAll("[data-detail-panel]").forEach((panel) => {
    panel.hidden = panel.dataset.detailPanel !== name;
  });
  if (!renderedPlayerTabs.has(name)) {
    if (name === "paldex") renderPaldexExplorer();
    if (name === "pals") {
      renderPalCollection();
      const playerAtRequest = selectedPlayer;
      hydratePlayerFromPublicCatalogs(playerAtRequest).then((changed) => {
        if (changed && selectedPlayer === playerAtRequest) renderPalCollection();
      }).catch(() => {});
    }
    if (name === "inventory") renderInventory(selectedPlayer);
    if (name === "bases") {
      if (currentBasesSnapshot()) renderSelectedPlayerBases();
      else loadBases(true).then(() => renderSelectedPlayerBases());
    }
    renderedPlayerTabs.add(name);
  }
  if (updateRoute && selectedPlayer) {
    history.replaceState(null, "", playerRoute(selectedPlayer, name));
    trackVirtualPageView();
  }
  if (updateRoute) {
    expeditionShell.scrollTo({ top: 0, behavior: prefersReducedMotion.matches ? "auto" : "smooth" });
  }
  const tabs = document.querySelector(".detail-tabs");
  window.requestAnimationFrame(() => {
    if (!tabs || !activeTab) return;
    const left = activeTab.offsetLeft - (tabs.clientWidth - activeTab.offsetWidth) / 2;
    tabs.scrollTo({ left: Math.max(0, left), behavior: prefersReducedMotion.matches ? "auto" : "smooth" });
  });
}

function renderPlayerHeader(player) {
  const portraits = playerTeamPals(player).slice(0, 3);
  expeditionPlayerEmblem.innerHTML = portraits.length
    ? portraits.map((pal) => gameImage(pal.icon, pal.name || pal.species || "Pal", "player-emblem-pal")).join("")
    : `<span class="player-emblem-fallback">${escapeHtml(playerInitials(player.name))}</span>`;
  expeditionPlayerMeta.textContent = player.provisional
      ? `Niveau ${player.level == null ? "à préciser" : Number(player.level)} · progression en cours de sauvegarde`
    : `Niveau ${Number(player.level || 0)} · ${Number(player.pals?.total || 0)} Pals · ${player.guild || "Sans guilde"}`;
}

function renderPlayerUpdatedAt(profileUpdatedAt) {
  const updates = [];
  if (profileUpdatedAt) updates.push(`Profil actualisé le ${formatDateTime(profileUpdatedAt)}`);
  if (statsSnapshot?.updatedAt) updates.push(`activité actualisée le ${formatDateTime(statsSnapshot.updatedAt)}`);
  expeditionPlayerUpdated.textContent = updates.length ? updates.join(" · ") : "Actualisation en attente";
}

function updateSelectedPlayerActivity() {
  if (!selectedPlayer) return;

  const values = getPlayerActivityValues(selectedPlayer);
  setTextIfChanged(expeditionProfile.querySelector('[data-profile-activity="sessions"]'), values.sessions);
  setTextIfChanged(expeditionProfile.querySelector('[data-profile-activity="playtime"]'), values.playtime);
  setTextIfChanged(expeditionProfile.querySelector('[data-profile-activity="lastSeen"]'), values.lastSeen);
  setTextIfChanged(expeditionProfile.querySelector('[data-profile-activity="ping"]'), values.ping);
  setTextIfChanged(expeditionProfile.querySelector('[data-profile-activity-note="lastSeen"]'), values.lastSeenNote);
}

function paldexEntryKey(row) {
  return `${Number(row.index || 0)}|${String(row.name || "")}`;
}

function paldexEntryStatus(row) {
  if (row.captured) {
    const captures = Number(row.captureCount || 0);
    const challenge = Number(row.challengeCount || 0);
    const target = Number(row.challengeTarget || 5);
    return {
      key: "captured",
      label: "Capturé",
      note: `${captures} capture${captures > 1 ? "s" : ""} · défi ${challenge} / ${target}`,
    };
  }
  if (row.encountered) return { key: "encountered", label: "Rencontré", note: "Pas encore capturé" };
  return { key: "unknown", label: "À découvrir", note: "Cette silhouette reste un mystère" };
}

function paldexDisplayNumber(row) {
  const index = Number(row.index || 0);
  return index > 0 ? `Nº ${String(index).padStart(3, "0")}` : "Entrée secrète";
}

function paldexCardMarkup(row) {
  const status = paldexEntryStatus(row);
  const known = status.key !== "unknown";
  const name = known ? row.name : "Espèce inconnue";
  const key = paldexEntryKey(row);
  return `
    <button class="paldex-card paldex-card--${status.key}${key === selectedPaldexKey ? " is-selected" : ""}" type="button" data-paldex-entry="${escapeHtml(key)}" aria-label="${escapeHtml(`${paldexDisplayNumber(row)}, ${name}, ${status.label}`)}">
      <span class="paldex-card__number">${escapeHtml(paldexDisplayNumber(row))}</span>
      <span class="paldex-card__portrait">${gameImage(row.icon, known ? row.name : "", "paldex-card__image")}</span>
      <span class="paldex-card__copy"><strong>${escapeHtml(name)}</strong><small>${escapeHtml(status.label)}</small></span>
      ${row.captured ? `<span class="paldex-card__challenge${row.challengeComplete ? " is-complete" : ""}">${Number(row.challengeCount || 0)} / ${Number(row.challengeTarget || 5)}</span>` : ""}
      <span class="paldex-card__marker" aria-hidden="true">${status.key === "captured" ? "✓" : status.key === "encountered" ? "•" : "?"}</span>
    </button>
  `;
}

function paldexFocusMarkup(row) {
  if (!row) return '<p class="detail-empty">Aucune entrée ne correspond à ces filtres.</p>';
  const status = paldexEntryStatus(row);
  const known = status.key !== "unknown";
  const challenge = Number(row.challengeCount || 0);
  const challengeTarget = Number(row.challengeTarget || 5);
  const challengePercent = Math.max(0, Math.min(100, challenge / Math.max(1, challengeTarget) * 100));
  return `
    <div class="paldex-focus__portrait paldex-focus__portrait--${status.key}">
      ${gameImage(row.icon, known ? row.name : "", "paldex-focus__image")}
      <span>${escapeHtml(paldexDisplayNumber(row))}</span>
    </div>
    <div class="paldex-focus__copy">
      <span class="paldex-focus__status paldex-focus__status--${status.key}">${escapeHtml(status.label)}</span>
      <h5>${escapeHtml(known ? row.name : "Une espèce reste à découvrir")}</h5>
      <p>${escapeHtml(status.note)}</p>
      ${row.captured ? `
        <div class="paldex-focus__challenge" aria-label="Défi de capture: ${challenge} sur ${challengeTarget}">
          <span><b>Défi de capture</b><strong>${challenge} / ${challengeTarget}</strong></span>
          <i><span style="width:${challengePercent}%"></span></i>
        </div>` : ""}
      ${known ? `<small>Entrée ${escapeHtml(paldexDisplayNumber(row).replace("Nº ", "#"))} du Paldex</small>` : ""}
    </div>
  `;
}

function renderPaldexExplorer() {
  const explorer = expeditionPaldex.querySelector("[data-paldex-explorer]");
  if (!explorer || !selectedPlayer) return;
  const paldex = selectedPlayer.progress?.paldex || {};
  const rows = Array.isArray(paldex.species) ? [...paldex.species] : [];
  rows.sort((left, right) => Number(left.index || 0) - Number(right.index || 0) || String(left.name || "").localeCompare(String(right.name || ""), "fr-CA"));
  const query = String(explorer.querySelector("[data-paldex-search]")?.value || "").trim().toLocaleLowerCase("fr-CA");
  const counts = {
    all: rows.length,
    captured: rows.filter((row) => row.captured).length,
    encountered: rows.filter((row) => row.encountered && !row.captured).length,
    unknown: rows.filter((row) => !row.encountered).length,
  };
  const filtered = rows.filter((row) => {
    const status = paldexEntryStatus(row).key;
    const matchesStatus = paldexStatusFilter === "all" || status === paldexStatusFilter;
    const searchable = row.encountered ? `${row.name} ${paldexDisplayNumber(row)}`.toLocaleLowerCase("fr-CA") : paldexDisplayNumber(row).toLocaleLowerCase("fr-CA");
    return matchesStatus && (!query || searchable.includes(query));
  });
  const pageCount = Math.max(1, Math.ceil(filtered.length / paldexPageSize));
  paldexCurrentPage = Math.min(paldexCurrentPage, pageCount);
  const start = (paldexCurrentPage - 1) * paldexPageSize;
  const visible = filtered.slice(start, start + paldexPageSize);
  if (!selectedPaldexKey || !rows.some((row) => paldexEntryKey(row) === selectedPaldexKey)) {
    selectedPaldexKey = paldexEntryKey(rows.find((row) => row.captured) || rows.find((row) => row.encountered) || rows[0] || {});
  }
  const selected = visible.find((row) => paldexEntryKey(row) === selectedPaldexKey) || visible[0] || null;
  selectedPaldexKey = selected ? paldexEntryKey(selected) : "";

  explorer.querySelectorAll("[data-paldex-status]").forEach((button) => {
    const active = button.dataset.paldexStatus === paldexStatusFilter;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
    const count = button.querySelector("b");
    if (count) count.textContent = counts[button.dataset.paldexStatus] ?? 0;
  });
  const resultCount = explorer.querySelector("[data-paldex-count]");
  if (resultCount) {
    resultCount.textContent = filtered.length
      ? `${filtered.length} entrée${filtered.length > 1 ? "s" : ""} · page ${paldexCurrentPage} sur ${pageCount}`
      : "Aucune entrée ne correspond à cette recherche.";
  }
  const focus = explorer.querySelector("[data-paldex-focus]");
  if (focus) focus.innerHTML = paldexFocusMarkup(selected);
  const grid = explorer.querySelector("[data-paldex-grid]");
  if (grid) grid.innerHTML = visible.length ? visible.map(paldexCardMarkup).join("") : '<p class="detail-empty paldex-grid__empty">Essaie un autre numéro, statut ou nom de Pal.</p>';
  const pagination = explorer.querySelector("[data-paldex-pagination]");
  if (pagination) {
    pagination.innerHTML = pageCount > 1 ? [
      `<button type="button" data-paldex-page="${paldexCurrentPage - 1}" ${paldexCurrentPage === 1 ? "disabled" : ""} aria-label="Page précédente">Précédente</button>`,
      ...stockPageNumbers(paldexCurrentPage, pageCount).map((page) => page === "ellipsis"
        ? '<span aria-hidden="true">…</span>'
        : `<button type="button" data-paldex-page="${page}" class="${page === paldexCurrentPage ? "is-active" : ""}" ${page === paldexCurrentPage ? 'aria-current="page"' : ""}>${page}</button>`),
      `<button type="button" data-paldex-page="${paldexCurrentPage + 1}" ${paldexCurrentPage === pageCount ? "disabled" : ""} aria-label="Page suivante">Suivante</button>`,
    ].join("") : "";
  }
}

function renderPlayerDiscoveryProgress(progress) {
  const paldex = progress?.paldex;
  if (!paldex) return "";
  const bosses = progress.bosses || {};
  const exploration = progress.exploration || {};
  const relics = progress.relics || {};
  const quests = progress.quests || {};
  const challenges = progress.challenges || {};
  const records = progress.records || {};
  const knownBosses = Array.isArray(bosses.known) ? bosses.known : [];
  const relicCategories = Array.isArray(relics.categories) ? relics.categories.filter((row) => Number(row.rank || 0) > 0) : [];
  const technologies = Array.isArray(progress.technologies) ? progress.technologies : [];
  const completedQuests = Array.isArray(quests.completed) ? quests.completed : [];
  const activeQuests = Array.isArray(quests.active) ? quests.active : [];
  const completedChallenges = Array.isArray(challenges.completed) ? challenges.completed : [];
  const bossPreview = knownBosses.slice(0, 12)
    .map((row) => `<span class="discovery-chip">${gameImage(row.icon, "", "discovery-chip__icon")}<strong>${escapeHtml(row.name)}</strong></span>`)
    .join("");
  const relicPreview = relicCategories
    .map((row) => `<span class="progress-pill"><strong>${escapeHtml(row.name)}</strong><small>Rang ${Number(row.rank || 0)}${row.maxRank ? ` / ${Number(row.maxRank)}` : ""}</small></span>`)
    .join("");

  return `
    <section class="player-kpi-group player-kpi-group--discoveries">
      <header><div><span>Exploration</span><h4>Découvertes de l'aventurier</h4></div><p>Progression relevée directement dans la dernière sauvegarde du monde.</p></header>
      <div class="profile-stat-grid profile-stat-grid--discoveries">
        <article class="profile-stat"><span>Paldex capturé</span><strong>${Number(paldex.capturedSpecies || 0)}<em> / ${Number(paldex.totalSpecies || 0)}</em></strong><small>${formatProgressPercent(paldex.completionPercent)} complété</small></article>
        <article class="profile-stat"><span>Captures totales</span><strong>${Number(paldex.totalCaptures || 0).toLocaleString("fr-CA")}</strong><small>${Number(paldex.encounteredSpecies || 0)} espèces rencontrées</small></article>
        <article class="profile-stat"><span>Boss vaincus</span><strong>${Number(bosses.defeated || 0)}</strong><small>Dont ${Number(bosses.towerDefeated || 0)} boss de tour</small></article>
        <article class="profile-stat"><span>Voyages rapides</span><strong>${Number(exploration.fastTravelUnlocked || 0)}<em> / ${Number(exploration.fastTravelTotal || 0)}</em></strong><small>${Number(exploration.areasDiscovered || 0)} zones découvertes</small></article>
        <article class="profile-stat"><span>Exploration</span><strong>${formatProgressPercent(exploration.completionPercent)}</strong><small>Zones et points de voyage connus</small></article>
        <article class="profile-stat"><span>Reliques</span><strong>${Number(relics.totalRanks || 0)}</strong><small>Rangs de bonus permanents</small></article>
      </div>
      <section class="paldex-explorer" data-paldex-explorer>
        <header class="paldex-explorer__heading">
          <div><span>Paldex personnel</span><h4>Les espèces de Palpagos</h4><p>Explore les captures, les défis 5/5, les rencontres et les silhouettes qui restent à identifier.</p></div>
          <div class="paldex-progress" style="--paldex-progress:${Math.max(0, Math.min(100, Number(paldex.completionPercent || 0)))}%" aria-label="${formatProgressPercent(paldex.completionPercent)} du Paldex capturé"><strong>${formatProgressPercent(paldex.completionPercent)}</strong><small>complété</small></div>
        </header>
        <div class="paldex-explorer__stage">
          <aside class="paldex-focus" data-paldex-focus></aside>
          <div class="paldex-catalogue">
            <div class="paldex-toolbar">
              <label><span>Rechercher</span><input type="search" data-paldex-search placeholder="Nom ou numéro du Paldex..." autocomplete="off"></label>
              <div class="paldex-statuses" role="group" aria-label="Filtrer le Paldex par statut">
                <button class="is-active" type="button" data-paldex-status="all" aria-pressed="true">Tous <b>0</b></button>
                <button type="button" data-paldex-status="captured" aria-pressed="false">Capturés <b>0</b></button>
                <button type="button" data-paldex-status="encountered" aria-pressed="false">Rencontrés <b>0</b></button>
                <button type="button" data-paldex-status="unknown" aria-pressed="false">À découvrir <b>0</b></button>
              </div>
            </div>
            <p class="paldex-result-count" data-paldex-count aria-live="polite"></p>
            <div class="paldex-grid" data-paldex-grid></div>
            <nav class="paldex-pagination" data-paldex-pagination aria-label="Pages du Paldex"></nav>
          </div>
        </div>
      </section>
      <details class="discovery-details">
        <summary><span>Parcourir les autres découvertes</span><small>Boss, reliques et technologies</small></summary>
        <div class="discovery-details__groups">
          <section><h5>Boss identifiés</h5><div class="discovery-chip-grid">${bossPreview || "<p>Aucun boss catalogué pour l'instant.</p>"}</div></section>
          <section><h5>Bonus permanents</h5><div class="progress-pill-grid">${relicPreview || "<p>Aucune relique détaillée pour l'instant.</p>"}</div></section>
          <section class="technology-explorer" data-technology-explorer>
            <header><div><h5>Technologies débloquées</h5><p>Parcours les plans et améliorations appris par cet aventurier.</p></div><strong data-technology-count>${technologies.length} technologies</strong></header>
            <div class="technology-toolbar">
              <label><span>Rechercher</span><input type="search" data-technology-search placeholder="Arme, bâtiment, équipement..." autocomplete="off"></label>
              <label><span>Type</span><select data-technology-type><option value="all">Toutes</option><option value="normale">Normales</option><option value="ancienne">Anciennes</option></select></label>
            </div>
            <div class="technology-grid" data-technology-grid><p>Ouvre cette section pour parcourir les technologies.</p></div>
          </section>
        </div>
      </details>
      <details class="journey-details">
        <summary>
          <span><b>Quêtes, défis et exploits</b><small>${completedQuests.length} quêtes documentées · ${completedChallenges.length} défis réussis</small></span>
          <span aria-hidden="true">⌄</span>
        </summary>
        <div class="journey-details__content">
          <div class="journey-record-grid">
            <article><strong>${Number(paldex.captureChallengesCompleted || 0)}</strong><span>défis de capture 5/5</span></article>
            <article><strong>${Number(records.treasuresFound || 0)}</strong><span>trésors trouvés</span></article>
            <article><strong>${Number(records.normalDungeonsCleared || 0) + Number(records.fixedDungeonsCleared || 0)}</strong><span>donjons terminés</span></article>
            <article><strong>${Number(records.fishCaught || 0)}</strong><span>prises de pêche</span></article>
            <article><strong>${Number(records.oilRigsCleared || 0)}</strong><span>plateformes nettoyées</span></article>
            <article><strong>${Number(records.itemsCrafted || 0).toLocaleString("fr-CA")}</strong><span>objets fabriqués</span></article>
            <article><strong>${Number(records.uniqueItemsPickedUp || 0).toLocaleString("fr-CA")}</strong><span>objets uniques découverts</span></article>
            <article><strong>${Number(records.notesFound || 0).toLocaleString("fr-CA")}</strong><span>notes trouvées</span></article>
            <article><strong>${Number(records.arenaSoloClears || 0).toLocaleString("fr-CA")}</strong><span>arènes solo terminées</span></article>
            <article><strong>${Number(records.raidBossDefeats || 0).toLocaleString("fr-CA")}</strong><span>boss de raid vaincus</span></article>
            <article><strong>${Number(records.towerBossDefeats || bosses.towerDefeated || 0).toLocaleString("fr-CA")}</strong><span>boss de tour vaincus</span></article>
            <article><strong>${Number(records.palRankups || 0).toLocaleString("fr-CA")}</strong><span>améliorations de Pals</span></article>
        <article><strong>${Number(records.mutations || 0).toLocaleString("fr-CA")}</strong><span>mutations notées</span></article>
          </div>
          <section><h5>Quêtes en cours</h5><div class="journey-chip-grid">${activeQuests.length ? activeQuests.map((row) => `<span>${escapeHtml(row.name)}</span>`).join("") : "<p>Aucune quête active documentée.</p>"}</div></section>
          <section><h5>Quêtes terminées</h5><div class="journey-chip-grid">${completedQuests.length ? completedQuests.map((row) => `<span>${escapeHtml(row.name)}</span>`).join("") : "<p>Aucune quête publique documentée.</p>"}</div></section>
          <section><h5>Défis Palworld réussis</h5><div class="journey-chip-grid journey-chip-grid--challenges">${completedChallenges.length ? completedChallenges.map((row) => `<span><b>${escapeHtml(row.category || "Défi")}</b><small>Palier ${Number(row.tier || 0)}</small></span>`).join("") : "<p>Aucune récompense de défi enregistrée.</p>"}</div></section>
        </div>
      </details>
    </section>
  `;
}

function renderPlayerTechnologies() {
  const explorer = expeditionProfile.querySelector("[data-technology-explorer]");
  const grid = explorer?.querySelector("[data-technology-grid]");
  if (!explorer || !grid || explorer.dataset.rendered === "true" || !selectedPlayer) return;
  const technologies = Array.isArray(selectedPlayer.progress?.technologies)
    ? [...selectedPlayer.progress.technologies]
    : [];
  technologies.sort((left, right) => Number(right.level || 0) - Number(left.level || 0)
    || String(left.name || "").localeCompare(String(right.name || ""), "fr-CA"));
  grid.innerHTML = technologies.length ? technologies.map((row) => `
    <article class="technology-card" data-technology-card data-technology-name="${escapeHtml(String(row.name || "").toLocaleLowerCase("fr-CA"))}" data-technology-type="${escapeHtml(row.type || "normale")}">
      ${gameImage(row.icon, row.name, "technology-card__icon")}
      <span><strong>${escapeHtml(row.name)}</strong><small>Niveau ${Number(row.level || 0)} · ${row.type === "ancienne" ? "Technologie ancienne" : "Technologie normale"}</small></span>
    </article>
  `).join("") : "<p>Aucune technologie détaillée pour l'instant.</p>";
  explorer.dataset.rendered = "true";
  filterPlayerTechnologies();
}

function filterPlayerTechnologies() {
  const explorer = expeditionProfile.querySelector("[data-technology-explorer]");
  if (!explorer) return;
  const query = String(explorer.querySelector("[data-technology-search]")?.value || "")
    .trim()
    .toLocaleLowerCase("fr-CA");
  const type = explorer.querySelector("[data-technology-type]")?.value || "all";
  let visible = 0;
  explorer.querySelectorAll("[data-technology-card]").forEach((card) => {
    const matches = (!query || card.dataset.technologyName.includes(query))
      && (type === "all" || card.dataset.technologyType === type);
    card.hidden = !matches;
    if (matches) visible += 1;
  });
  const count = explorer.querySelector("[data-technology-count]");
  if (count) count.textContent = `${visible} technologie${visible > 1 ? "s" : ""}`;
}

function renderPlayerPosition(position, pending = false) {
  const value = position
    ? `${isWorldMapPosition(position) ? "Carte" : "Zone non cartographiée ·"} X ${Number(position.mapX || 0).toLocaleString("fr-CA")}, Y ${Number(position.mapY || 0).toLocaleString("fr-CA")}`
    : (pending ? "En attente de la première sauvegarde" : "Position encore inconnue");
  expeditionPosition.innerHTML = `
    <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a7 7 0 0 0-7 7c0 5.4 7 13 7 13s7-7.6 7-13a7 7 0 0 0-7-7Zm0 10.2A3.2 3.2 0 1 1 12 5.8a3.2 3.2 0 0 1 0 6.4Z"/></svg>
    <span><small>Dernière position connue</small><strong>${escapeHtml(value)}</strong></span>
  `;
}

function renderPlayerProfile(player) {
  const character = player.character || {};
  const experienceProgress = character.experienceProgress || null;
  const progress = player.progress || {};
  const activity = getPlayerActivityValues(player);
  const position = player.position;
  const guildBases = player.guildBases != null && Number.isFinite(Number(player.guildBases))
    ? Number(player.guildBases)
    : null;
  const campLevel = player.campLevel != null && Number.isFinite(Number(player.campLevel))
    ? Number(player.campLevel)
    : null;
  if (player.provisional) {
    expeditionProfile.innerHTML = `
      <section class="player-kpi-group player-kpi-group--pending">
        <header><div><span>Nouvel aventurier</span><h4>La fiche de ${escapeHtml(player.name)} se prépare</h4></div><p>Palworld a détecté la connexion, mais n'a pas encore créé la sauvegarde complète du personnage.</p></header>
        <div class="profile-pending-message">
          <strong>Rien n'est perdu ni bloqué.</strong>
          <span>Les Pals, l'inventaire, les technologies et les campements apparaîtront automatiquement après l'entrée complète dans le monde et la première sauvegarde.</span>
        </div>
      </section>
      <section class="player-kpi-group player-kpi-group--activity">
        <header><div><span>Activité</span><h4>Présence déjà observée</h4></div><p>Ces données sont disponibles avant la sauvegarde du personnage.</p></header>
        <div class="profile-stat-grid profile-stat-grid--activity">
          <article class="profile-stat profile-stat--sessions"><span>Connexions</span><strong data-profile-activity="sessions">${activity.sessions}</strong><small>Sessions observées</small></article>
          <article class="profile-stat profile-stat--playtime"><span>Temps observé</span><strong data-profile-activity="playtime">${activity.playtime}</strong><small>Présence cumulée</small></article>
          <article class="profile-stat profile-stat--last-seen"><span>Dernière vue</span><strong data-profile-activity="lastSeen">${activity.lastSeen}</strong><small data-profile-activity-note="lastSeen">${activity.lastSeenNote}</small></article>
          <article class="profile-stat profile-stat--ping"><span>Dernier ping</span><strong data-profile-activity="ping">${activity.ping}</strong><small>Dernière latence relevée</small></article>
        </div>
      </section>
    `;
    expeditionPaldex.replaceChildren();
    expeditionAllocations.innerHTML = '<p class="detail-empty">Les attributs apparaîtront avec la première sauvegarde.</p>';
    expeditionShortcuts.innerHTML = "";
    renderPlayerPosition(null, true);
    return;
  }
  expeditionProfile.innerHTML = `
    <section class="player-kpi-group player-kpi-group--activity">
      <header><div><span>Activité</span><h4>Présence sur le serveur</h4></div><p>Ces durées sont estimées à partir des observations régulières du serveur.</p></header>
      <div class="profile-stat-grid profile-stat-grid--activity">
        <article class="profile-stat profile-stat--sessions"><span>Connexions</span><strong data-profile-activity="sessions">${activity.sessions}</strong><small>Sessions observées</small></article>
        <article class="profile-stat profile-stat--playtime"><span>Temps total joué</span><strong data-profile-activity="playtime">${activity.playtime}</strong><small>Temps cumulé estimé</small></article>
        <article class="profile-stat profile-stat--last-seen"><span>Dernière vue</span><strong data-profile-activity="lastSeen">${activity.lastSeen}</strong><small data-profile-activity-note="lastSeen">${activity.lastSeenNote}</small></article>
        <article class="profile-stat profile-stat--ping"><span>Dernier ping</span><strong data-profile-activity="ping">${activity.ping}</strong><small>Dernière latence relevée</small></article>
      </div>
    </section>
    <section class="player-kpi-group player-kpi-group--progression">
      <header><div><span>Progression</span><h4>Parcours du personnage</h4></div><p>Les valeurs permanentes enregistrées dans la sauvegarde.</p></header>
      <div class="profile-stat-grid">
        <article class="profile-stat profile-stat--level"><span>Niveau du personnage</span><strong>${Number(player.level || 0)}</strong><small>Niveau atteint</small></article>
        <article class="profile-stat profile-stat--xp"><span>Expérience enregistrée</span><strong>${Number(character.experience || 0).toLocaleString("fr-CA")}</strong><small>${experienceProgress ? `${Number(experienceProgress.remaining || 0).toLocaleString("fr-CA")} EXP avant le niveau ${Number(experienceProgress.nextLevel || player.level + 1)} · ${Number(experienceProgress.percent || 0).toLocaleString("fr-CA")} %` : "EXP dans la sauvegarde"}</small></article>
        <article class="profile-stat profile-stat--points"><span>Points disponibles</span><strong>${Number(character.unusedStatusPoints || 0)}</strong><small>Pas encore attribués</small></article>
      </div>
    </section>
    <section class="player-kpi-group player-kpi-group--camp">
      <header><div><span>Guilde et camp</span><h4>Développement des bases</h4></div><p>Ces valeurs sont communes à tous les membres de la guilde.</p></header>
      <div class="profile-stat-grid profile-stat-grid--camp">
        <article class="profile-stat profile-stat--bases"><span>Bases de la guilde</span><strong>${guildBases ?? "--"}</strong><small>Camps actuellement établis</small></article>
        <article class="profile-stat profile-stat--camp"><span>Niveau du camp</span><strong>${campLevel ?? "--"}</strong><small>Progression commune de la guilde</small></article>
      </div>
    </section>
    <section class="player-kpi-group player-kpi-group--state">
      <header><div><span>Dernier relevé</span><h4>État du personnage</h4></div><p>Une photographie de l'état au moment de la sauvegarde, pas les maximums possibles.</p></header>
      <div class="profile-stat-grid">
        <article class="profile-stat profile-stat--health"><span>Points de vie actuels</span><strong>${Number(character.hp || 0).toLocaleString("fr-CA")}</strong><small>PV au dernier relevé</small></article>
        <article class="profile-stat profile-stat--shield"><span>Bouclier actuel</span><strong>${Number(character.shield || 0).toLocaleString("fr-CA")}</strong><small>Protection au dernier relevé</small></article>
        <article class="profile-stat profile-stat--hunger"><span>Satiété actuelle</span><strong>${Math.round(Number(character.hunger || 0))}<em>%</em></strong><small>Jauge au dernier relevé</small></article>
      </div>
    </section>
    <section class="player-kpi-group player-kpi-group--milestones">
      <header><div><span>Avancées</span><h4>Découvertes et récompenses</h4></div><p>Ce qui a été débloqué ou demeure disponible.</p></header>
      <div class="player-milestone-grid">
        <article><strong>${Number(progress.technologyPoints || 0)}</strong><span>points de technologie</span></article>
        <article><strong>${Number(progress.bossTechnologyPoints || 0)}</strong><span>points de technologie ancienne</span></article>
        <article><strong>${Number(progress.unlockedTechnologies || 0)}</strong><span>technologies débloquées</span></article>
        <article><strong>${Number(progress.completedQuests || 0)}</strong><span>quêtes terminées</span></article>
      </div>
    </section>
    ${renderPlayerDiscoveryProgress(progress)}
  `;
  expeditionPaldex.replaceChildren();
  const paldexExplorer = expeditionProfile.querySelector("[data-paldex-explorer]");
  if (paldexExplorer) expeditionPaldex.append(paldexExplorer);
  const allocations = Array.isArray(character.allocations) ? character.allocations : [];
  const totalInvested = allocations.reduce((sum, row) => sum + Number(row.points || 0), 0);
  const allocationDescriptions = {
    "Santé": "Bonus de points de vie",
    "Endurance": "Capacité d'endurance",
    "Attaque": "Dégâts du personnage",
    "Poids": "Capacité de transport",
    "Capture": "Efficacité de capture",
    "Travail": "Vitesse de travail",
    "Vitesse": "Vitesse de déplacement",
    "Réduction de la faim": "Consommation de satiété",
    "Vitesse de nage": "Déplacement dans l'eau",
    "Guidage des sphères": "Précision des Pal Spheres",
  };
  expeditionAllocations.innerHTML = allocations.length
    ? `
      <div class="allocation-summary">
        <span><strong>${totalInvested}</strong> points attribués</span>
        <span><strong>${Number(character.unusedStatusPoints || 0)}</strong> points disponibles</span>
      </div>
      <div class="attribute-grid">
        ${allocations.map((row) => {
          const points = Number(row.points || 0);
          return `
            <article class="attribute-card${points > 0 ? " is-invested" : ""}">
              <span><b>${escapeHtml(row.name)}</b><small>${escapeHtml(allocationDescriptions[row.name] || "Bonus du personnage")}</small></span>
              <strong>${points > 0 ? "+" : ""}${points}</strong>
            </article>
          `;
        }).join("")}
      </div>
    `
    : '<p class="detail-empty">Aucun point de statistique enregistré.</p>';

  const pals = Array.isArray(player.pals?.collection) ? player.pals.collection : [];
  const inventoryItems = (player.inventory || []).flatMap((section) => section.items || []);
  const previewImages = (rows, className) => rows.slice(0, 3)
    .map((row) => gameImage(row.icon, row.species || row.name, className))
    .join("");
  expeditionShortcuts.innerHTML = `
    <button type="button" data-shortcut-tab="paldex">
      <span class="shortcut-preview shortcut-preview--paldex" aria-hidden="true">PX</span>
      <span><small>Découvertes personnelles</small><strong>Ouvrir le Paldex</strong></span>
      <b>Explorer →</b>
    </button>
    <button type="button" data-shortcut-tab="pals">
      <span class="shortcut-preview">${previewImages(pals, "shortcut-icon")}</span>
      <span><small>Collection personnelle</small><strong>Voir les ${pals.length} Pals</strong></span>
      <b>Explorer →</b>
    </button>
    <button type="button" data-shortcut-tab="inventory">
      <span class="shortcut-preview">${previewImages(inventoryItems, "shortcut-icon")}</span>
      <span><small>Sac et équipement</small><strong>Voir les ${inventoryItems.length} objets</strong></span>
      <b>Explorer →</b>
    </button>
    <button type="button" data-shortcut-tab="bases">
      <span class="shortcut-preview shortcut-preview--camp" aria-hidden="true">⌂</span>
      <span><small>Vie de la guilde</small><strong>Voir les ${Number(player.guildBases || 0)} campements</strong></span>
      <b>Explorer →</b>
    </button>
  `;
  renderPlayerPosition(position);
}

function renderInventory(player) {
  const sections = Array.isArray(player.inventory) ? player.inventory : [];
  const allItems = sections.flatMap((section) => section.items || []);
  const totalQuantity = allItems.reduce((sum, item) => sum + Number(item.count || 0), 0);
  const totalWeight = allItems.reduce((sum, item) => sum + Number(item.totalWeight || 0), 0);
  const equippedItems = sections
    .filter((section) => ["weapons", "armor", "food"].includes(section.key))
    .flatMap((section) => (section.items || []).map((item) => ({ ...item, sectionLabel: section.label })));
  inventoryOverview.innerHTML = `
    <span><strong>${allItems.length}</strong> types d'objets</span>
    <span><strong>${totalQuantity.toLocaleString("fr-CA")}</strong> unités au total<small>Somme des quantités de toutes les piles</small></span>
    ${totalWeight > 0 ? `<span><strong>${totalWeight.toLocaleString("fr-CA", { maximumFractionDigits: 1 })}</strong> poids estimé<small>D'après le catalogue du jeu</small></span>` : ""}
    <span><strong>${equippedItems.length}</strong> types équipés</span>
  `;
  inventoryEquipped.innerHTML = `
    <div class="inventory-equipped__heading">
      <span>Équipement actuellement porté</span>
      <small>Armes, armure, accessoires et nourriture équipée</small>
    </div>
    <div class="inventory-equipped__list">
      ${equippedItems.length ? equippedItems.map((item) => `
        <span class="inventory-equipped__item rarity-${Math.min(5, Number(item.rarity || 0))}">
          ${gameImage(item.icon, "", "inventory-equipped__icon")}
          <span><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.sectionLabel)}${Number(item.count || 0) > 1 ? ` · ×${Number(item.count).toLocaleString("fr-CA")}` : ""}</small></span>
        </span>
      `).join("") : '<span class="detail-empty">Aucun équipement détecté.</span>'}
    </div>
  `;

  const query = inventorySearch.value.trim().toLocaleLowerCase("fr-CA");
  const selectedSection = inventorySectionFilter.value;
  const visibleSections = sections
    .filter((section) => selectedSection === "all" || section.key === selectedSection)
    .map((section) => ({
      ...section,
      items: (section.items || []).filter((item) => {
        const searchable = `${item.name || ""} ${translateItemCategory(item.category)}`.toLocaleLowerCase("fr-CA");
        return !query || searchable.includes(query);
      }),
    }))
    .filter((section) => section.items.length || (!query && selectedSection !== "all"));

  expeditionInventory.innerHTML = visibleSections.length ? visibleSections.map((section) => {
    const items = section.items;
    return `
      <section class="inventory-section">
        <header><div><span class="inventory-section__index">${String(sections.findIndex((item) => item.key === section.key) + 1).padStart(2, "0")}</span><h3>${escapeHtml(section.label)}</h3></div><span>${items.length} type${items.length > 1 ? "s" : ""} d'objet${items.length > 1 ? "s" : ""}</span></header>
        <div class="inventory-grid">
          ${items.length ? items.map((item) => `
            <article class="inventory-item rarity-${Math.min(5, Number(item.rarity || 0))}">
              ${gameImage(item.icon, item.name)}
              <div><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(translateItemCategory(item.category))}</small></div>
              <b>×${Number(item.count || 0).toLocaleString("fr-CA")}</b>
            </article>
          `).join("") : '<p class="detail-empty">Aucun objet dans cette section.</p>'}
        </div>
      </section>
    `;
  }).join("") : '<p class="detail-empty detail-empty--large">Aucun objet ne correspond à cette recherche.</p>';
}

function palTalentScore(pal) {
  const talents = pal.talents || {};
  return (Number(talents.hp || 0) + Number(talents.attack || 0) + Number(talents.defense || 0)) / 3;
}

function renderPalCollection() {
  if (!selectedPlayer) return;
  const collection = Array.isArray(selectedPlayer.pals?.collection) ? selectedPlayer.pals.collection : [];
  const partyCount = collection.filter((pal) => pal.container === "party").length;
  const palboxCount = collection.filter((pal) => pal.container === "palbox").length;
  palCollectionOverview.innerHTML = `
    <span><strong>${collection.length}</strong> Pals</span>
    <span><strong>${partyCount}</strong> en équipe</span>
    <span><strong>${palboxCount}</strong> en Palbox</span>
    <span><strong>${Number(selectedPlayer.pals?.highestLevel || 0)}</strong> niveau max</span>
  `;
  const query = palSearch.value.trim().toLocaleLowerCase("fr-CA");
  const container = palContainerFilter.value;
  const pals = collection.filter((pal) => {
    if (container !== "all" && pal.container !== container) return false;
    const searchable = [
      pal.name,
      pal.species,
      ...(pal.passives || []).map((skill) => skill.name),
      ...(pal.activeSkills || []).map((skill) => skill.name),
    ].join(" ").toLocaleLowerCase("fr-CA");
    return !query || searchable.includes(query);
  });
  const sortMode = palSort.value;
  pals.sort((a, b) => {
    if (sortMode === "name") return String(a.name).localeCompare(String(b.name), "fr-CA");
    if (sortMode === "talent") return palTalentScore(b) - palTalentScore(a) || Number(b.level || 0) - Number(a.level || 0);
    return Number(b.level || 0) - Number(a.level || 0) || palTalentScore(b) - palTalentScore(a);
  });
  const visiblePals = pals.slice(0, palVisibleLimit);
  palResultCount.textContent = visiblePals.length < pals.length
    ? `${visiblePals.length} sur ${pals.length}`
    : `${pals.length} ${pals.length === 1 ? "résultat" : "résultats"}`;
  palLoadMore.hidden = visiblePals.length >= pals.length;
  palLoadMore.textContent = `Afficher ${Math.min(24, pals.length - visiblePals.length)} Pals de plus`;
  expeditionPals.innerHTML = visiblePals.length ? visiblePals.map((pal) => {
    const passives = (pal.passives || []).map((skill) => {
      const description = formatTooltipText(skill.description);
      return `<span tabindex="0" data-tooltip="${escapeHtml(description)}">${escapeHtml(skill.name)}</span>`;
    }).join("");
    const skills = (pal.activeSkills || []).map((skill) => escapeHtml(skill.name)).join(" · ");
    const learnedSkills = (pal.learnedSkills || []).map((skill) => {
      const details = [skill.element, skill.power ? `Puissance ${skill.power}` : "", skill.cooldown != null ? `${skill.cooldown} s` : ""]
        .filter(Boolean)
        .join(" · ");
      return `<span><strong>${escapeHtml(skill.name)}</strong>${details ? `<small>${escapeHtml(details)}</small>` : ""}</span>`;
    }).join("");
    const nextLearnedSkills = (pal.nextLearnedSkills || []).map((skill) => `
      <span><strong>Niv. ${Number(skill.level || 0)} · ${escapeHtml(skill.name)}</strong><small>${escapeHtml([skill.element, skill.power ? `Puissance ${skill.power}` : ""].filter(Boolean).join(" · ") || "Compétence à venir")}</small></span>
    `).join("");
    const workSuitabilities = (pal.workSuitabilityBonuses || []).map((work) => `
      <span><strong>${escapeHtml(work.name)}</strong><b>${Number(work.level || 0)}</b>${Number(work.bonus || 0) > 0 ? `<small>+${Number(work.bonus)} bonus</small>` : ""}</span>
    `).join("");
    const badges = [
      pal.lucky ? "Lucky" : "",
      pal.boss ? "Boss" : "",
      pal.awakening ? "Éveillé" : "",
      pal.favorite ? "Favori" : "",
      pal.imported ? "Importé" : "",
    ].filter(Boolean);
    const souls = pal.souls || {};
    const computed = pal.computedStats || {};
    const containerLabel = pal.container === "party" ? "Équipe" : pal.container === "palbox" ? "Palbox" : "Monde";
    const gender = pal.gender === "Male" ? "Mâle" : pal.gender === "Female" ? "Femelle" : pal.gender || "-";
    const talentScore = Math.round(palTalentScore(pal));
    const palExperience = pal.experienceProgress || null;
    const friendshipProgress = pal.friendshipProgress || null;
    return `
      <article class="pal-detail-card">
        <div class="pal-detail-card__portrait">
          ${gameImage(pal.icon, pal.species, "pal-portrait")}
          <span>${containerLabel}</span>
        </div>
        <div class="pal-detail-card__body">
          <header><div><small>${escapeHtml(pal.species)}</small><h3>${escapeHtml(pal.name)}</h3></div><b>Niv. ${Number(pal.level || 0)}</b></header>
          ${badges.length || pal.rank != null || pal.rarity != null ? `<div class="pal-badges">${badges.map((badge) => `<span>${badge}</span>`).join("")}${pal.rank != null ? `<span>Condensation ${Number(pal.rank)}</span>` : ""}${pal.rarity != null ? `<span>Rareté ${Number(pal.rarity)}</span>` : ""}</div>` : ""}
          <div class="pal-vitals"><span>PV ${Number(pal.hp || 0).toLocaleString("fr-CA")}${pal.maxHp ? ` / ${Number(pal.maxHp).toLocaleString("fr-CA")}` : ""}</span><span>Amitié ${Number(pal.friendship || 0).toLocaleString("fr-CA")}${friendshipProgress ? ` · rang ${Number(friendshipProgress.rank || 0)}` : ""}</span><span>${escapeHtml(gender)}</span>${pal.sanity != null ? `<span>SAN ${Math.round(Number(pal.sanity))}%</span>` : ""}</div>
          ${palExperience ? `<div class="pal-progression"><span><small>Prochain niveau</small><strong>${Number(palExperience.remaining || 0).toLocaleString("fr-CA")} EXP</strong></span><i aria-label="${Number(palExperience.percent || 0)} % vers le niveau ${Number(palExperience.nextLevel || pal.level + 1)}"><em style="width:${Math.max(0, Math.min(100, Number(palExperience.percent || 0)))}%"></em></i></div>` : ""}
          <div class="pal-talent-score"><span>Potentiel</span><b>${talentScore}</b><i><em style="width:${talentScore}%"></em></i></div>
          <div class="talent-bars">
            <span style="--talent:${Number(pal.talents?.hp || 0)}%">Santé ${Number(pal.talents?.hp || 0)}</span>
            <span style="--talent:${Number(pal.talents?.attack || 0)}%">Attaque ${Number(pal.talents?.attack || 0)}</span>
            <span style="--talent:${Number(pal.talents?.defense || 0)}%">Défense ${Number(pal.talents?.defense || 0)}</span>
          </div>
          <div class="pal-abilities">
            <small>Passifs</small>
            <div class="pal-passives">${passives || "<span>Aucun passif</span>"}</div>
            <small>Compétences</small>
            <p class="pal-skills">${skills || "À découvrir"}</p>
          </div>
          ${(computed.attack != null || computed.defense != null || computed.workSpeed != null) ? `
            <div class="pal-computed-stats" aria-label="Statistiques calculées">
              <span><small>Attaque</small><strong>${computed.attack ?? "--"}</strong></span>
              <span><small>Défense</small><strong>${computed.defense ?? "--"}</strong></span>
              <span><small>Travail</small><strong>${computed.workSpeed ?? "--"}</strong></span>
            </div>
          ` : ""}
          <div class="pal-souls">
            <small>Améliorations par âmes</small>
            <span>PV +${Number(souls.hp || 0)}</span><span>ATQ +${Number(souls.attack || 0)}</span><span>DEF +${Number(souls.defense || 0)}</span><span>Travail +${Number(souls.workSpeed || 0)}</span>
          </div>
          ${workSuitabilities ? `<div class="pal-work"><small>Aptitudes de travail</small><div>${workSuitabilities}</div></div>` : ""}
          ${learnedSkills ? `<details class="pal-learned"><summary>${(pal.learnedSkills || []).length} attaque${(pal.learnedSkills || []).length > 1 ? "s" : ""} apprise${(pal.learnedSkills || []).length > 1 ? "s" : ""}</summary><div>${learnedSkills}</div></details>` : ""}
          ${nextLearnedSkills ? `<details class="pal-learned pal-learned--next"><summary>Prochaines compétences</summary><div>${nextLearnedSkills}</div></details>` : ""}
          <div class="pal-breeding" data-breeding-result>
            <button type="button" data-load-breeding data-species="${escapeHtml(pal.species)}">Voir des combinaisons d'élevage</button>
          </div>
          ${(pal.healthStatus || pal.ownedAt) ? `<div class="pal-footnotes">${pal.healthStatus ? `<span>État: ${escapeHtml(pal.healthStatus)}</span>` : ""}${pal.ownedAt ? `<span>Acquis le ${escapeHtml(formatDateTime(pal.ownedAt))}</span>` : ""}</div>` : ""}
        </div>
      </article>
    `;
  }).join("") : '<p class="detail-empty detail-empty--large">Aucun Pal ne correspond à cette recherche.</p>';
}

async function ensurePublicCatalogManifest() {
  if (publicCatalogManifest) return publicCatalogManifest;
  if (!publicCatalogManifestPromise) {
    publicCatalogManifestPromise = readJson("data/public-catalogs-manifest.json", { revalidate: true })
      .then((manifest) => {
        if (!manifest?.ok || Number(manifest.schemaVersion) !== 1 || !/^[A-Za-z0-9._-]+$/.test(String(manifest.generationId || ""))) {
          throw new Error("invalid-catalog-manifest");
        }
        publicCatalogManifest = manifest;
        registerPayloadDataUpdate("catalog", manifest);
        return manifest;
      })
      .catch((error) => {
        registerSourceHealth("catalog", "transient-error", "stale");
        throw error;
      })
      .finally(() => {
        publicCatalogManifestPromise = null;
      });
  }
  return publicCatalogManifestPromise;
}

async function ensurePublicCatalog(name) {
  const manifest = await ensurePublicCatalogManifest();
  const entry = manifest?.files?.[name];
  const path = String(entry?.path || "");
  const expectedPrefix = `public-catalogs/${manifest.generationId}/`;
  if (!path.startsWith(expectedPrefix) || !new RegExp(`/${name}\\.json$`).test(path) || !v6Sha256IsValid(entry?.sha256)) {
    throw new Error("invalid-catalog-entry");
  }
  const key = `${manifest.generationId}:${name}`;
  if (!publicCatalogCache.has(key)) {
    publicCatalogCache.set(key, readJson(`data/${path}`, {
      immutable: true,
      expectedSha256: entry.sha256,
    }).then((payload) => {
      if (
        Number(payload?.schemaVersion) !== 1
        || String(payload?.generationId || "") !== String(manifest.generationId)
      ) throw new Error("mixed-catalog-generation");
      return payload;
    }).catch((error) => {
      publicCatalogCache.delete(key);
      throw error;
    }));
  }
  return publicCatalogCache.get(key);
}

function catalogExperienceProgress(level, experience, table, pal = false) {
  const current = table?.[String(Math.max(1, Number(level || 1)))];
  const nextLevel = Math.max(1, Number(level || 1)) + 1;
  const following = table?.[String(nextLevel)];
  const totalKey = pal ? "PalTotalEXP" : "TotalEXP";
  if (!current || !following) return null;
  const currentTotal = Math.max(0, Number(current[totalKey] || 0));
  const nextTotal = Math.max(currentTotal, Number(following[totalKey] || currentTotal));
  const required = nextTotal - currentTotal;
  if (required <= 0) return null;
  const gained = Math.min(required, Math.max(0, Number(experience || 0) - currentTotal));
  return {
    level: Number(level || 1),
    nextLevel,
    gained,
    required,
    remaining: Math.max(0, nextTotal - Number(experience || 0)),
    percent: Math.round((gained / required) * 1000) / 10,
  };
}

function catalogFriendshipProgress(points, table) {
  const rows = Object.values(table || {})
    .filter((row) => row && Number.isFinite(Number(row.RequiredPoint)))
    .sort((left, right) => Number(left.RequiredPoint) - Number(right.RequiredPoint));
  if (!rows.length) return null;
  const value = Number(points || 0);
  const current = [...rows].reverse().find((row) => Number(row.RequiredPoint) <= value) || rows[0];
  const following = rows.find((row) => Number(row.RequiredPoint) > value) || null;
  const start = Number(current.RequiredPoint || 0);
  const end = following ? Number(following.RequiredPoint || start) : start;
  const span = Math.max(0, end - start);
  return {
    points: value,
    rank: Number(current.FriendshipRank || 0),
    nextRank: following ? Number(following.FriendshipRank || 0) : null,
    remaining: following ? Math.max(0, end - value) : 0,
    percent: span ? Math.round((Math.min(span, Math.max(0, value - start)) / span) * 1000) / 10 : 100,
  };
}

async function hydratePlayerFromPublicCatalogs(player) {
  if (!player || player.provisional || catalogHydratedPlayers.has(player)) return false;
  await ensurePublicCatalogManifest();
  const pals = Array.isArray(player.pals?.collection) ? player.pals.collection : [];
  const needsProgression = !player.character?.experienceProgress
    || pals.some((pal) => !pal.experienceProgress || !pal.friendshipProgress);
  const needsLearnsets = pals.some((pal) => !Array.isArray(pal.nextLearnedSkills));
  const [progression, learnsets] = await Promise.all([
    needsProgression ? ensurePublicCatalog("progression") : null,
    needsLearnsets ? ensurePublicCatalog("learnsets") : null,
  ]);
  let changed = false;
  if (progression && player.character && !player.character.experienceProgress) {
    player.character.experienceProgress = catalogExperienceProgress(
      player.level,
      player.character.experience,
      progression.experience,
    );
    changed = Boolean(player.character.experienceProgress) || changed;
  }
  const skillIndex = new Map((learnsets?.skills || []).map((skill) => [String(skill.asset || "").toLocaleLowerCase("en-CA"), skill]));
  pals.forEach((pal) => {
    if (progression && !pal.experienceProgress) {
      pal.experienceProgress = catalogExperienceProgress(pal.level, pal.experience, progression.experience, true);
      changed = Boolean(pal.experienceProgress) || changed;
    }
    if (progression && !pal.friendshipProgress) {
      pal.friendshipProgress = catalogFriendshipProgress(pal.friendship, progression.friendship);
      changed = Boolean(pal.friendshipProgress) || changed;
    }
    if (learnsets && !Array.isArray(pal.nextLearnedSkills)) {
      const rows = learnsets.learnset?.[pal.species] || [];
      pal.nextLearnedSkills = rows
        .filter((row) => Number(row.level || 0) > Number(pal.level || 0))
        .sort((left, right) => Number(left.level || 0) - Number(right.level || 0))
        .slice(0, 3)
        .map((row) => {
          const asset = String(row.WazaID || "").replace(/^EPalWazaID::/, "");
          return { level: Number(row.level || 0), ...(skillIndex.get(asset.toLocaleLowerCase("en-CA")) || { name: asset }) };
        });
      changed = true;
    }
  });
  catalogHydratedPlayers.add(player);
  return changed;
}

async function renderBreedingOptions(button) {
  const container = button.closest("[data-breeding-result]");
  if (!container) return;
  button.disabled = true;
  button.textContent = "Chargement des combinaisons…";
  try {
    const catalog = await ensurePublicCatalog("breeding");
    const species = String(button.dataset.species || "");
    const palInfo = catalog.pal_info || {};
    const asset = Object.entries(palInfo).find(([, info]) => String(info?.name || "").localeCompare(species, "fr-CA", { sensitivity: "base" }) === 0)?.[0];
    const rows = asset ? [
      ...(catalog.child_to_parents_unique?.[asset] || []),
      ...(catalog.child_to_parents_formula?.[asset] || []),
      ...(catalog.child_to_parents_ignore?.[asset] || []),
    ] : [];
    const seen = new Set();
    const combinations = rows.filter((row) => {
      const key = [row.parent_a, row.parent_b].sort().join("|");
      if (!row.parent_a || !row.parent_b || seen.has(key)) return false;
      seen.add(key);
      return true;
    }).slice(0, 8);
    container.innerHTML = combinations.length ? `
      <details open><summary>${combinations.length} combinaisons d'élevage</summary><ul>${combinations.map((row) => `
        <li>${escapeHtml(palInfo[row.parent_a]?.name || row.parent_a)} <span>×</span> ${escapeHtml(palInfo[row.parent_b]?.name || row.parent_b)}</li>
      `).join("")}</ul></details>
    ` : "<p>Aucune combinaison documentée pour ce Pal.</p>";
  } catch {
    button.disabled = false;
    button.textContent = "Réessayer les combinaisons d'élevage";
  }
}

async function ensureFullSaveSnapshot() {
  const generationId = await ensureActiveSaveGeneration();
  if (saveGenerationIsValid(fullSaveSnapshot, generationId)) return fullSaveSnapshot;
  if (!fullSaveSnapshotPromise || fullSaveSnapshotPromiseGenerationId !== generationId) {
    fullSaveSnapshotPromiseGenerationId = generationId;
    const request = readJson("data/public-save-snapshot.json")
      .then((payload) => {
        assertActiveSaveGeneration(payload, "snapshot", generationId);
        fullSaveSnapshot = payload;
        return payload;
      })
      .finally(() => {
        if (fullSaveSnapshotPromise === request) {
          fullSaveSnapshotPromise = null;
          fullSaveSnapshotPromiseGenerationId = "";
        }
      });
    fullSaveSnapshotPromise = request;
  }
  return fullSaveSnapshotPromise;
}

async function ensurePlayerSnapshot(indexedPlayer) {
  const slug = playerSlug(indexedPlayer?.name);
  const revision = await ensureActiveSaveGeneration();
  const promiseKey = `${revision}:${slug}`;
  const cached = playerSnapshotCache.get(promiseKey);
  if (cached) return cached;
  if (playerSnapshotPromises.has(promiseKey)) return playerSnapshotPromises.get(promiseKey);

  const promise = readJson(`data/players/${slug}.json`)
    .then((payload) => {
      if (!payload?.ok || !payload.player) throw new Error("Invalid player snapshot");
      assertActiveSaveGeneration(payload, "player", revision);
      playerSnapshotCache.set(promiseKey, payload);
      return payload;
    })
    .catch(async () => {
      const payload = await ensureFullSaveSnapshot();
      const player = (payload?.players || []).find((row) => playerSlug(row.name) === slug);
      if (!player) throw new Error("Player profile unavailable");
      const fallback = {
        ok: true,
        generationId: revision,
        updatedAt: payload.updatedAt,
        version: payload.version ?? null,
        provenance: payload.provenance || null,
        player,
      };
      playerSnapshotCache.set(promiseKey, fallback);
      return fallback;
    })
    .finally(() => playerSnapshotPromises.delete(promiseKey));
  playerSnapshotPromises.set(promiseKey, promise);
  return promise;
}

async function openPlayerDetails(index, tab = "profile", updateRoute = true) {
  const indexedPlayers = Array.isArray(saveSnapshot?.players) ? saveSnapshot.players : [];
  const indexedPlayer = indexedPlayers[index];
  if (!indexedPlayer) return;

  let payload = null;
  if (indexedPlayer.provisional) {
    selectedPlayer = indexedPlayer;
    selectedPlayerSnapshotPayload = {
      ok: true,
      generationId: activeSaveGenerationId(),
      updatedAt: saveSnapshot?.updatedAt || statsSnapshot?.updatedAt || null,
      version: saveSnapshot?.version ?? null,
      provenance: saveSnapshot?.provenance || null,
      player: indexedPlayer,
    };
  } else {
    try {
      payload = await ensurePlayerSnapshot(indexedPlayer);
    } catch {
      saveState.textContent = "Fiches momentanément indisponibles";
      return;
    }
    selectedPlayer = payload.player;
    selectedPlayerSnapshotPayload = payload;
    if (!selectedPlayer) return;
  }
  expeditionPlayerName.textContent = selectedPlayer.name || "Aventurier";
  expeditionPlayerGuild.textContent = selectedPlayer.guild || "Aventurier indépendant";
  renderPlayerHeader(selectedPlayer);
  renderPlayerUpdatedAt(selectedPlayer.provisional ? statsSnapshot?.updatedAt : (payload?.updatedAt || saveSnapshot?.updatedAt));
  palSearch.value = "";
  palContainerFilter.value = "all";
  palSort.value = "level";
  palVisibleLimit = 24;
  paldexCurrentPage = 1;
  paldexStatusFilter = "all";
  selectedPaldexKey = "";
  inventorySearch.value = "";
  baseSearch.value = "";
  stockSearch.value = "";
  stockCategory.value = "all";
  stockSource = "all";
  stockCurrentPage = 1;
  inventorySectionFilter.innerHTML = '<option value="all">Toutes les sections</option>' + (selectedPlayer.inventory || [])
    .map((section) => `<option value="${escapeHtml(section.key)}">${escapeHtml(section.label)}</option>`)
    .join("");
  inventorySectionFilter.value = "all";
  expeditionShare.textContent = "Partager la fiche";
  expeditionShare.classList.remove("is-success", "is-error");
  const palCount = Number(selectedPlayer.pals?.total || 0);
  const inventoryCount = (selectedPlayer.inventory || []).reduce((sum, section) => sum + (section.items || []).length, 0);
  const paldexCount = Number(selectedPlayer.progress?.paldex?.capturedSpecies || 0);
  detailTabPaldex.innerHTML = `<span>02</span> Mon Paldex <b>${selectedPlayer.provisional ? "--" : paldexCount}</b>`;
  detailTabPals.innerHTML = `<span>03</span> Mes Pals <b>${selectedPlayer.provisional ? "--" : palCount}</b>`;
  detailTabInventory.innerHTML = `<span>04</span> Mon inventaire <b>${selectedPlayer.provisional ? "--" : inventoryCount}</b>`;
  detailTabBases.innerHTML = `<span>05</span> Bases et campements <b>${selectedPlayer.provisional ? "--" : Number(selectedPlayer.guildBases || 0)}</b>`;
  [detailTabPaldex, detailTabPals, detailTabInventory, detailTabBases].forEach((button) => {
    button.disabled = Boolean(selectedPlayer.provisional);
  });
  renderedPlayerTabs.clear();
  renderedPlayerTabs.add("profile");
  renderPlayerProfile(selectedPlayer);
  resetPlayerExportButtons();
  expeditionPals.innerHTML = '<p class="detail-empty detail-empty--large">La collection sera préparée à l’ouverture de cet onglet.</p>';
  expeditionInventory.innerHTML = '<p class="detail-empty detail-empty--large">L’inventaire sera préparé à l’ouverture de cet onglet.</p>';
  const activeTab = selectedPlayer.provisional ? "profile" : tab;
  switchDetailTab(activeTab, false);
  const willOpenDialog = !expeditionDialog.open;
  if (willOpenDialog) {
    playerDialogReturnFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    lockPlayerView();
  }
  if (updateRoute) history.replaceState(null, "", playerRoute(selectedPlayer, activeTab));
  if (willOpenDialog) {
    expeditionDialog.showModal();
    window.requestAnimationFrame(() => expeditionBack?.focus({ preventScroll: true }));
  }
  trackVirtualPageView();
}

function lockPlayerView() {
  if (playerViewLocked) return;
  backgroundScrollY = window.scrollY;
  playerReturnUrl = location.hash.startsWith("#joueur/")
    ? `${location.pathname}${location.search}`
    : `${location.pathname}${location.search}${location.hash}`;
  playerViewLocked = true;
  document.body.style.top = `-${backgroundScrollY}px`;
  document.body.classList.add("player-view-open");
}

function unlockPlayerView() {
  if (!playerViewLocked) return;
  const restoreY = backgroundScrollY;
  const root = document.documentElement;
  const previousScrollBehavior = root.style.scrollBehavior;
  playerViewLocked = false;
  document.body.classList.remove("player-view-open");
  document.body.style.removeProperty("top");
  root.style.scrollBehavior = "auto";
  window.scrollTo({ top: restoreY, behavior: "auto" });
  window.requestAnimationFrame(() => {
    window.requestAnimationFrame(() => {
      window.scrollTo({ top: restoreY, behavior: "auto" });
      root.style.scrollBehavior = previousScrollBehavior;
    });
  });
}

function openPlayerFromRoute() {
  if (!expeditionDialog) return;
  const match = location.hash.match(/^#joueur\/([^/]+)(?:\/(profile|paldex|pals|inventory|bases))?$/);
  if (!match || !saveSnapshot) {
    if (!match && expeditionDialog.open) expeditionDialog.close();
    if (!match) unlockPlayerView();
    if (!match) selectedPlayer = null;
    return;
  }
  const players = Array.isArray(saveSnapshot.players) ? saveSnapshot.players : [];
  const index = players.findIndex((player) => playerSlug(player.name) === match[1]);
  if (index >= 0) openPlayerDetails(index, match[2] || "profile", false);
}

function closePlayerDetails() {
  if (expeditionDialog?.open) expeditionDialog.close();
  selectedPlayer = null;
  selectedPlayerSnapshotPayload = null;
  selectedPlayerBases = [];
  history.replaceState(null, "", playerReturnUrl || `${location.pathname}${location.search}`);
  trackVirtualPageView();
  unlockPlayerView();
  const returnFocus = playerDialogReturnFocus;
  playerDialogReturnFocus = null;
  window.requestAnimationFrame(() => {
    if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
  });
}

let activeTooltipTarget = null;

function positionContextTooltip(target) {
  const text = target?.dataset.tooltip;
  if (!text) return;
  const title = target.dataset.tooltipTitle || "";
  contextTooltip.innerHTML = title
    ? `<span class="context-tooltip__title">${escapeHtml(title)}</span><span class="context-tooltip__body">${escapeHtml(text)}</span>`
    : `<span class="context-tooltip__body">${escapeHtml(text)}</span>`;
  contextTooltip.hidden = false;
  contextTooltip.dataset.placement = target.dataset.tooltipPlacement || "top";

  const targetRect = target.getBoundingClientRect();
  const tooltipRect = contextTooltip.getBoundingClientRect();
  const gap = 10;
  let left = targetRect.left + targetRect.width / 2 - tooltipRect.width / 2;
  let top = targetRect.top - tooltipRect.height - gap;

  if (contextTooltip.dataset.placement === "left") {
    left = targetRect.left - tooltipRect.width - gap;
    top = targetRect.top + targetRect.height / 2 - tooltipRect.height / 2;
  }
  if (top < 8) top = targetRect.bottom + gap;
  left = Math.max(8, Math.min(left, window.innerWidth - tooltipRect.width - 8));
  top = Math.max(8, Math.min(top, window.innerHeight - tooltipRect.height - 8));
  contextTooltip.style.left = `${Math.round(left)}px`;
  contextTooltip.style.top = `${Math.round(top)}px`;
}

function showContextTooltip(target) {
  if (!target?.dataset.tooltip) return;
  activeTooltipTarget = target;
  target.setAttribute("aria-describedby", "context-tooltip");
  positionContextTooltip(target);
}

function hideContextTooltip() {
  if (activeTooltipTarget) activeTooltipTarget.removeAttribute("aria-describedby");
  activeTooltipTarget = null;
  contextTooltip.hidden = true;
}

function updateContextTooltipAfterScroll() {
  if (!activeTooltipTarget) return;
  const rect = activeTooltipTarget.getBoundingClientRect();
  if (rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth) {
    hideContextTooltip();
    return;
  }
  positionContextTooltip(activeTooltipTarget);
}

function clearSearchOnEscape(event) {
  if (event.key !== "Escape" || !event.currentTarget.value) return;
  event.currentTarget.value = "";
  event.currentTarget.dispatchEvent(new Event("input", { bubbles: true }));
}

async function readJson(path, options = {}) {
  const source = path.startsWith("/") ? path : `/${path}`;
  const requestSource = options.revalidate || options.immutable
    ? source
    : `${source}${source.includes("?") ? "&" : "?"}ts=${Date.now()}`;
  const response = await fetch(requestSource, {
    cache: options.immutable ? "force-cache" : options.revalidate ? "no-cache" : "no-store",
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  if (!options.expectedSha256) return response.json();
  if (!window.crypto?.subtle) throw new Error("sha256-unavailable");
  const bytes = await response.arrayBuffer();
  const digest = await window.crypto.subtle.digest("SHA-256", bytes);
  const actual = [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
  const expected = String(options.expectedSha256).replace(/^sha256:/i, "").toLocaleLowerCase("en-CA");
  if (actual !== expected) throw new Error("sha256-mismatch");
  return JSON.parse(new TextDecoder("utf-8").decode(bytes));
}

function isNewDataRevision(source, payload) {
  const revision = String(payload?.revision || payload?.generationId || payload?.updatedAt || "");
  if (revision && dataRevisions[source] === revision) return false;
  dataRevisions[source] = revision;
  return true;
}

async function loadMetrics(silent = false) {
  try {
    const payload = await readJson("data/public-metrics.json");
    const changed = isNewDataRevision("metrics", payload);
    if (changed) renderMetrics(payload);
    return { ok: true, changed };
  } catch {
    registerSourceHealth("metrics", "transient-error", "stale");
    if (!silent) {
      playersList.textContent = "Les données apparaîtront automatiquement au prochain passage du collecteur.";
      headerPlayers.dataset.tooltip = playersList.textContent;
    }
    return { ok: false, changed: false };
  }
}

async function loadStats(silent = false) {
  try {
    const payload = await readJson("data/public-stats.json");
    const changed = isNewDataRevision("stats", payload);
    if (changed) renderStats(payload);
    return { ok: payload?.ok !== false, changed };
  } catch {
    registerSourceHealth("stats", "transient-error", "stale");
    return { ok: false, changed: false };
  }
}

async function loadUptime(silent = false) {
  try {
    const payload = await readJson("data/public-uptime.json");
    const changed = isNewDataRevision("uptime", payload);
    if (changed) renderUptime(payload);
    return { ok: true, changed };
  } catch {
    registerSourceHealth("uptime", "transient-error", "stale");
    if (!silent) {
      uptimeSummary.textContent = "La disponibilité apparaîtra automatiquement après le prochain passage du collecteur.";
      uptimeBars.innerHTML = createPlaceholderBars();
    }
    return { ok: false, changed: false };
  }
}

async function loadSaveSnapshot(silent = false, syncRoute = true) {
  if (!saveIndexPromise) {
    const request = readJson("data/public-save-index.json")
      .then((payload) => {
        const generationId = publicSaveGenerationId(payload);
        if (!payload?.ok || !generationId) throw new Error("invalid-save-generation:index");
        const changed = isNewDataRevision("save", payload);
        if (changed) {
          renderSaveSnapshot(payload, syncRoute);
        }
        return { ok: true, changed };
      })
      .catch(() => {
        registerSourceHealth("save", "transient-error", "stale");
        if (!silent && saveState) saveState.textContent = "En attente";
        return { ok: false, changed: false };
      })
      .finally(() => {
        if (saveIndexPromise === request) saveIndexPromise = null;
      });
    saveIndexPromise = request;
  }
  return saveIndexPromise;
}

async function loadSaveDiagnostics(silent = false) {
  try {
    const generationId = await ensureActiveSaveGeneration();
    const payload = await readJson("data/public-save-diagnostics.json");
    assertActiveSaveGeneration(payload, "diagnostics", generationId);
    const changed = isNewDataRevision("diagnostics", payload);
    if (changed) renderSaveDiagnostics(payload);
    return { ok: true, changed };
  } catch {
    registerSourceHealth("diagnostics", "transient-error", "stale");
    if (!silent && worldDataState) worldDataState.textContent = "En attente";
    return { ok: false, changed: false };
  }
}

async function loadBases(silent = false) {
  basesGenerationRequested = true;
  try {
    const generationId = await ensureActiveSaveGeneration();
    const payload = await readJson("data/public-save-bases.json");
    assertActiveSaveGeneration(payload, "bases", generationId);
    const changed = isNewDataRevision("bases", payload);
    if (changed) renderBaseSnapshot(payload);
    return { ok: true, changed };
  } catch {
    registerSourceHealth("bases", "transient-error", "stale");
    if (!silent) {
      if (basesState) basesState.textContent = "En attente";
      if (baseResultCount) baseResultCount.textContent = "Les données des bases arriveront au prochain passage du collecteur.";
    }
    return { ok: false, changed: false };
  }
}

async function loadEventsFreshness(silent = true, force = false) {
  try {
    const candidate = await fetchEventsV6Candidate(silent, force);
    if (candidate.ok) return commitEventsV6Candidate(candidate);
    registerSourceHealth("events", "transient-error", "stale");
    return { ok: false, changed: false };
  } catch {
    registerSourceHealth("events", "transient-error", "stale");
    return { ok: false, changed: false };
  }
}

async function loadCatalogFreshness() {
  try {
    await ensurePublicCatalogManifest();
    return { ok: true, changed: false };
  } catch {
    return { ok: false, changed: false };
  }
}

async function loadPortalFreshnessSources(options = {}) {
  const tasks = [
    loadMetrics(true),
    loadStats(true),
    loadUptime(true),
    loadSaveSnapshot(true, false),
    loadSaveDiagnostics(true),
    loadCatalogFreshness(),
  ];
  if (options.includeEvents !== false) tasks.push(loadEventsFreshness(true));
  return Promise.all(tasks);
}

function flattenLoadResults(results) {
  return results.flatMap((result) => Array.isArray(result) ? result : [result]);
}

function setupLazyBaseData() {
  if (currentBasesSnapshot()) return;
  const targets = [document.querySelector("#carte")].filter(Boolean);
  if (!("IntersectionObserver" in window)) {
    loadBases(true);
    return;
  }
  const observer = new IntersectionObserver((entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return;
    observer.disconnect();
    loadBases(true);
  }, { rootMargin: "500px 0px" });
  targets.forEach((target) => observer.observe(target));
}

function renderEventIndexSnapshot(payload) {
  eventsIndexSnapshot = payload;
  const currentPayload = v5TailReplacementWindow(payload, eventsRecentSnapshot)
    ? eventsRecentSnapshot
    : payload;
  registerPayloadDataUpdate("events", currentPayload);
  renderEventSyncStatus(new Date(), currentPayload?.updatedAt);
  if (eventIndexTotalEvents()) void loadEventExportPage(1).catch(() => {});
  if (eventsDisclosure?.open) renderEventFiltersFromFacets(payload);
}

async function loadEvents(silent = false) {
  if (eventsFullLoadPromise) return eventsFullLoadPromise;

  eventsFullLoadPromise = (async () => {
    try {
      const payload = await readJson("data/public-events.json");
      const changed = isNewDataRevision("events", payload);
      eventsFullLoaded = true;
      if (changed || !eventsSnapshot) renderEventSnapshot(payload);
      return { ok: true, changed };
    } catch {
      if (!silent) {
        if (eventsState) eventsState.textContent = "En attente";
        if (eventResultCount) eventResultCount.textContent = "Historique momentanément indisponible";
        if (eventStream) eventStream.innerHTML = '<li class="event-stream__empty">Les événements apparaîtront après le prochain passage du collecteur.</li>';
      }
      return { ok: false, changed: false };
    }
  })();

  const result = await eventsFullLoadPromise;
  if (!result.ok) eventsFullLoadPromise = null;
  return result;
}

async function loadEventsIndex(silent = false) {
  const recentSnapshot = loadEventsRecent(true, { snapshotOnly: true });
  try {
    const payload = await readJson("data/public-events-index.json");
    const recentResult = await recentSnapshot;
    const previousIndex = eventsIndexSnapshot;
    const previousRevision = eventsIndexSnapshot?.revision || "";
    const changed = isNewDataRevision("eventsIndex", payload);
    if (changed || previousRevision !== payload?.revision) {
      invalidateChangedEventPages(previousIndex, payload);
    }
    renderEventIndexSnapshot(payload);
    return { ok: true, changed: changed || recentResult.changed };
  } catch {
    await recentSnapshot;
    return loadEventsWithRecentOverlay(silent);
  }
}

function mergeEventPayload(payload) {
  return mergeEventPayloads(eventsSnapshot || {}, payload);
}

async function loadEventsRecent(silent = true, options = {}) {
  if (Date.now() - lastEventRecentRefreshAt < refreshEveryMs - 500 && eventsSnapshot) {
    return { ok: true, changed: false };
  }
  try {
    const previousRecentRevision = String(eventsRecentSnapshot?.revision || "");
    const payload = await readJson("data/public-events-recent.json");
    const recentPayload = {
      ...payload,
      recent: true,
      events: sortEventsNewestFirst(payload?.events || []),
    };
    eventsRecentSnapshot = recentPayload;
    lastEventRecentRefreshAt = Date.now();
    const snapshotChanged = previousRecentRevision !== String(recentPayload.revision || "");
    if (options.snapshotOnly) return { ok: true, changed: snapshotChanged };
    if (!eventsFullLoaded) {
      const changed = isNewDataRevision("events", recentPayload);
      if (changed) renderEventSnapshot(recentPayload);
      return { ok: true, changed };
    }

    const previousRevision = eventsSnapshot?.revision || "";
    const merged = mergeEventPayload(recentPayload);
    const changed = merged.revision !== previousRevision || merged.events.length !== (eventsSnapshot?.events || []).length;
    const scrollY = window.scrollY;
    eventsSnapshot = merged;
    renderEventSummaryCards(merged);
    renderEventSyncStatus(new Date(), merged.updatedAt);
    if (eventsDisclosure?.open) {
      renderEventFilters(merged.events || []);
      if (!isTerminalRoute() || eventCurrentPage === 1) {
        renderEvents(false, { preserveDom: true, preserveViewport: true });
        window.scrollTo({ top: scrollY, behavior: "auto" });
      }
    }
    return { ok: true, changed };
  } catch {
    return { ok: !silent, changed: false };
  }
}

async function loadEventsWithRecentOverlay(silent = false) {
  const results = await Promise.all([
    loadEventsRecent(true),
    loadEvents(silent),
  ]);
  return {
    ok: results.some((result) => result.ok),
    changed: results.some((result) => result.changed),
  };
}

async function refreshDataInBackground() {
  if (refreshPending) return;

  refreshPending = true;
  renderNextUpdate();
  if (isHeaderOnlyRoute()) {
    const results = flattenLoadResults(await loadPortalFreshnessSources());
    const synchronizedSources = results.filter((result) => result.ok).length;
    const changedSources = results.filter((result) => result.changed).length;
    nextRefreshAt = Date.now() + refreshEveryMs;
    refreshPending = false;
    refreshMessageState = synchronizedSources ? "updated" : "error";
    const refreshTime = new Date().toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
    refreshMessage = synchronizedSources ? `À jour · ${refreshTime}` : "Nouvel essai bientôt";
    if (changedSources) announceDataUpdate("Les données du portail ont été actualisées.");
    refreshMessageUntil = Date.now() + 6500;
    renderNextUpdate();
    return;
  }
  if (isDailyDigestRoute()) {
    const results = flattenLoadResults(await Promise.all([
      loadPortalFreshnessSources({ includeEvents: false }),
      loadDailyDigest(true),
    ]));
    const synchronizedSources = results.filter((result) => result.ok).length;
    const changedSources = results.filter((result) => result.changed).length;
    nextRefreshAt = Date.now() + refreshEveryMs;
    refreshPending = false;
    refreshMessageState = synchronizedSources ? "updated" : "error";
    const refreshTime = new Date().toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
    refreshMessage = synchronizedSources
      ? `À jour · ${refreshTime}`
      : "Nouvel essai bientôt";
    if (changedSources) announceDataUpdate("Le résumé quotidien a été actualisé.");
    refreshMessageUntil = Date.now() + 6500;
    renderNextUpdate();
    return;
  }
  if (isTerminalRoute()) {
    const eventRefresh = loadTerminalEventsPreferred(true);
    const results = flattenLoadResults(await Promise.all([
      loadPortalFreshnessSources({ includeEvents: false }),
      eventRefresh,
    ]));
    const synchronizedSources = results.filter((result) => result.ok).length;
    const changedSources = results.filter((result) => result.changed).length;
    nextRefreshAt = Date.now() + refreshEveryMs;
    refreshPending = false;
    refreshMessageState = synchronizedSources ? "updated" : "error";
    const refreshTime = new Date().toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
    refreshMessage = synchronizedSources
      ? `À jour · ${refreshTime}`
      : "Nouvel essai bientôt";
    if (changedSources) announceDataUpdate("De nouveaux échos sont disponibles.");
    refreshMessageUntil = Date.now() + 6500;
    renderNextUpdate();
    return;
  }
  const results = flattenLoadResults(await Promise.all([
    loadPortalFreshnessSources({ includeEvents: false }),
    basesGenerationRequested ? loadBases(true) : Promise.resolve({ ok: true, changed: false }),
    loadHomeEchoes(true),
  ]));
  const synchronizedSources = results.filter((result) => result.ok).length;
  const changedSources = results.filter((result) => result.changed).length;

  nextRefreshAt = Date.now() + refreshEveryMs;
  refreshPending = false;
  refreshMessageState = synchronizedSources ? "updated" : "error";
  const refreshTime = new Date().toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
  refreshMessage = synchronizedSources
      ? `À jour · ${refreshTime}`
    : "Nouvel essai bientôt";
  if (changedSources) announceDataUpdate("Les données du portail ont été actualisées.");
  refreshMessageUntil = Date.now() + 6500;
  renderNextUpdate();
}

readTerminalState();
syncTerminalView();
if (isTerminalRoute()) {
  if (eventsDisclosure) eventsDisclosure.open = true;
  const terminalEventsLoad = loadTerminalEventsPreferred();
  Promise.all([
    loadPortalFreshnessSources({ includeEvents: false }),
    terminalEventsLoad,
  ]).then(() => {
    document.documentElement.classList.add("data-loaded");
    if (eventsContractMode === "v6" && eventsSnapshot) {
      renderEventFiltersFromFacets(eventsIndexSnapshot);
      if (!eventFiltersRequireFullHistory() && !eventsFullLoaded && eventCurrentPage > 1) {
        void renderPagedTerminalEventsV6().then(() => writeTerminalState());
      } else {
        renderEvents();
        writeTerminalState();
      }
    } else if (eventsFullLoaded && eventsSnapshot) {
      renderEventFilters(eventsSnapshot.events || []);
      renderEvents();
      writeTerminalState();
    } else if (eventsIndexSnapshot) {
      renderEventFiltersFromFacets(eventsIndexSnapshot);
      void renderPagedTerminalEvents(false).then(() => writeTerminalState());
    }
  });
} else if (isDailyDigestRoute()) {
  Promise.all([
    loadPortalFreshnessSources({ includeEvents: false }),
    loadDailyDigest(),
  ]).then(() => {
    document.documentElement.classList.add("data-loaded");
  });
} else if (isLeaderboardRoute()) {
  loadPortalFreshnessSources().then(() => {
    document.documentElement.classList.add("data-loaded");
  });
} else if (isMapRoute()) {
  Promise.all([
    loadPortalFreshnessSources(),
    loadBases(true),
  ]).then(() => {
    loadDeferredImage(globalMapImage);
    window.requestAnimationFrame(restoreGlobalMapView);
    document.documentElement.classList.add("data-loaded");
  });
} else if (isHeaderOnlyRoute()) {
  loadPortalFreshnessSources().then(() => {
    document.documentElement.classList.add("data-loaded");
  });
} else {
  if (location.hash === "#carte" && mapDisclosure) mapDisclosure.open = true;
  if (location.hash === "#classements" && leaderboardDisclosure) leaderboardDisclosure.open = true;
  if (location.hash === "#evenements" && eventsDisclosure) eventsDisclosure.open = true;

  const initialBaseLoad = location.hash === "#carte"
    ? loadBases()
    : Promise.resolve({ ok: true, changed: false });
  const initialEventsLoad = loadHomeEchoes(true);

  Promise.all([loadPortalFreshnessSources({ includeEvents: false }), initialBaseLoad, initialEventsLoad]).then(() => {
    document.documentElement.classList.add("data-loaded");
    setupLazyBaseData();
    const initialSection = ["chroniques", "classements", "carte", "evenements"]
      .find((section) => location.hash === `#${section}`);
    if (initialSection) {
      if (initialSection === "carte" && mapDisclosure) mapDisclosure.open = true;
      if (initialSection === "evenements" && eventsDisclosure) eventsDisclosure.open = true;
      window.requestAnimationFrame(() => {
        document.getElementById(initialSection)?.scrollIntoView({ behavior: "auto", block: "start" });
      });
    }
  });
  renderServerRealDays();
}
renderNextUpdate();
startRefreshClock();
trackVirtualPageView();
updateActiveNavigation();

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    renderNextUpdate();
  }
});

window.addEventListener("pageshow", (event) => {
  if (event.persisted) {
    nextRefreshAt = Date.now() + refreshEveryMs;
    refreshPending = false;
    refreshMessage = "";
    renderNextUpdate();
    startRefreshClock();
  }
});

window.addEventListener("pagehide", () => {
  window.clearInterval(clockTimer);
  if (isTerminalRoute() && eventsContractMode === "v6") markTerminalEchoesSeen();
});

if (isDashboardRoute()) {
playerVisibilityToggle?.addEventListener("click", () => {
  showInactivePlayers = !showInactivePlayers;
  syncPlayerVisibilityToggle(Boolean(savePlayers?.querySelector('[data-player-visibility="inactive"]')));
});
savePlayers.addEventListener("click", (event) => {
  const link = event.target.closest("[data-player-index]");
  if (link) {
    event.preventDefault();
    openPlayerDetails(Number(link.dataset.playerIndex));
  }
});

document.querySelector(".archipelago-overview")?.addEventListener("click", (event) => {
  const link = event.target.closest("[data-player-index]");
  if (link) {
    event.preventDefault();
    openPlayerDetails(Number(link.dataset.playerIndex));
    return;
  }
});

document.querySelector('a[href="#chroniques"]')?.addEventListener("click", () => {
  const chroniclesDisclosure = document.querySelector('[data-disclosure-key^="chronicles-content"]');
  if (chroniclesDisclosure) chroniclesDisclosure.open = true;
});

document.querySelectorAll('a[href="#classements"]').forEach((link) => {
  link.addEventListener("click", () => {
    if (leaderboardDisclosure) leaderboardDisclosure.open = true;
  });
});

document.querySelectorAll('a[href="#evenements"]').forEach((link) => {
  link.addEventListener("click", () => {
    if (eventsDisclosure) eventsDisclosure.open = true;
  });
});

eventsDisclosure?.addEventListener("toggle", () => {
  if (location.hash === "#terminal" && !eventsDisclosure.open) {
    eventsDisclosure.open = true;
    return;
  }
  if (!eventsDisclosure.open) return;
  if (eventsContractMode === "v6") {
    if (eventFiltersRequireFullHistory() && !eventsFullLoaded) {
      if (eventResultCount) eventResultCount.textContent = "Chargement de l'historique complet...";
      void loadFullTerminalEventsV6().then(() => {
        if (!eventsDisclosure.open || !eventsSnapshot) return;
        renderEventFiltersFromFacets(eventsIndexSnapshot);
        renderEvents();
      });
      return;
    }
    if (!eventsSnapshot) return;
    renderEventFiltersFromFacets(eventsIndexSnapshot);
    void updateTerminalEvents(false);
    return;
  }
  if (eventFiltersRequireFullHistory() && !eventsFullLoaded) {
    if (eventResultCount) eventResultCount.textContent = "Chargement de l'historique complet...";
    void loadEventsWithRecentOverlay(true).then(() => {
      if (!eventsDisclosure.open || !eventsSnapshot) return;
      renderEventFilters(eventsSnapshot.events || []);
      renderEvents();
    });
    return;
  }
  if (!eventsSnapshot) {
    void loadEventsRecent(true).then(() => {
      if (!eventsDisclosure.open || !eventsSnapshot) return;
      renderEventFilters(eventsSnapshot.events || []);
      renderEvents();
    });
    return;
  }
  if (!eventsSnapshot) return;
  renderEventFilters(eventsSnapshot.events || []);
  renderEvents();
});

leaderboardDisclosure?.addEventListener("click", (event) => {
  const link = event.target.closest("[data-player-index]");
  if (!link) return;
  event.preventDefault();
  openPlayerDetails(Number(link.dataset.playerIndex));
});

leaderboardSearch?.addEventListener("input", renderLeaderboards);
leaderboardPresence?.addEventListener("change", renderLeaderboards);
leaderboardCategory?.addEventListener("change", () => {
  const definition = leaderboardCategories[leaderboardCategory.value] || leaderboardCategories.progression;
  leaderboardSortKey = definition.primary;
  leaderboardSortDirection = "desc";
  renderLeaderboards();
});
leaderboardHead?.addEventListener("click", (event) => {
  const button = event.target.closest("[data-leaderboard-sort]");
  if (!button) return;
  const key = button.dataset.leaderboardSort;
  if (leaderboardSortKey === key) leaderboardSortDirection = leaderboardSortDirection === "desc" ? "asc" : "desc";
  else {
    leaderboardSortKey = key;
    leaderboardSortDirection = "desc";
  }
  renderLeaderboards();
});

document.querySelectorAll('a[href="#carte"]').forEach((link) => {
  link.addEventListener("click", () => {
    if (mapDisclosure) mapDisclosure.open = true;
    if (!currentBasesSnapshot()) loadBases(true);
  });
});

mapDisclosure?.addEventListener("toggle", () => {
  if (!mapDisclosure.open) return;
  loadDeferredImage(globalMapImage);
  if (!currentBasesSnapshot()) loadBases(true);
  window.requestAnimationFrame(restoreGlobalMapView);
});

mapBaseToggle?.addEventListener("click", async () => {
  const shouldShow = !showMapBases;
  if (shouldShow && !currentBasesSnapshot()) await loadBases(true);
  showMapBases = shouldShow;
  renderGlobalPlayerMap(saveSnapshot?.players || [], currentBasesSnapshot()?.bases || []);
});

baseSearch?.addEventListener("input", filterBases);
stockSearch?.addEventListener("input", () => {
  stockCurrentPage = 1;
  renderStockExplorer();
});
stockCategory?.addEventListener("change", () => {
  stockCurrentPage = 1;
  renderStockExplorer();
});
stockSourceButtons.forEach((button) => {
  button.addEventListener("click", () => {
    stockSource = button.dataset.stockSource || "all";
    stockCurrentPage = 1;
    renderStockExplorer();
  });
});
stockPagination?.addEventListener("click", (event) => {
  const button = event.target.closest("[data-stock-page]");
  if (!button || button.disabled) return;
  stockCurrentPage = Number(button.dataset.stockPage || 1);
  renderStockExplorer();
  document.querySelector(".stock-explorer__heading")?.scrollIntoView({
    behavior: prefersReducedMotion.matches ? "auto" : "smooth",
    block: "start",
  });
});
expeditionProfile.addEventListener("input", (event) => {
  if (event.target.matches("[data-technology-search]")) filterPlayerTechnologies();
});
expeditionProfile.addEventListener("change", (event) => {
  if (event.target.matches("[data-technology-type]")) filterPlayerTechnologies();
});
expeditionProfile.addEventListener("toggle", (event) => {
  if (event.target.matches(".discovery-details") && event.target.open) renderPlayerTechnologies();
}, true);
expeditionPaldex.addEventListener("input", (event) => {
  if (event.target.matches("[data-paldex-search]")) {
    paldexCurrentPage = 1;
    renderPaldexExplorer();
  }
});
expeditionPaldex.addEventListener("click", (event) => {
  const status = event.target.closest("[data-paldex-status]");
  if (status) {
    paldexStatusFilter = status.dataset.paldexStatus || "all";
    paldexCurrentPage = 1;
    renderPaldexExplorer();
    return;
  }
  const entry = event.target.closest("[data-paldex-entry]");
  if (entry) {
    selectedPaldexKey = entry.dataset.paldexEntry || "";
    renderPaldexExplorer();
    return;
  }
  const page = event.target.closest("[data-paldex-page]");
  if (page && !page.disabled) {
    paldexCurrentPage = Number(page.dataset.paldexPage || 1);
    renderPaldexExplorer();
    expeditionPaldex.querySelector(".paldex-explorer__heading")?.scrollIntoView({
      behavior: prefersReducedMotion.matches ? "auto" : "smooth",
      block: "start",
    });
  }
});
expeditionPaldex.addEventListener("keydown", (event) => {
  if (event.target.matches("[data-paldex-search]")) clearSearchOnEscape(event);
});

document.querySelectorAll("[data-detail-tab]").forEach((button) => {
  button.addEventListener("click", () => switchDetailTab(button.dataset.detailTab));
  button.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const tabs = [...document.querySelectorAll("[data-detail-tab]")];
    const currentIndex = tabs.indexOf(button);
    const nextIndex = event.key === "Home"
      ? 0
      : event.key === "End"
        ? tabs.length - 1
        : (currentIndex + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length;
    tabs[nextIndex].focus();
    switchDetailTab(tabs[nextIndex].dataset.detailTab);
  });
});

expeditionDialog.addEventListener("click", (event) => {
  if (event.target === expeditionDialog) closePlayerDetails();
});
expeditionDialog.addEventListener("cancel", (event) => {
  event.preventDefault();
  closePlayerDetails();
});
expeditionClose.addEventListener("click", closePlayerDetails);
expeditionBack.addEventListener("click", closePlayerDetails);
expeditionShortcuts.addEventListener("click", (event) => {
  const shortcut = event.target.closest("[data-shortcut-tab]");
  if (shortcut) switchDetailTab(shortcut.dataset.shortcutTab);
});
expeditionShare.addEventListener("click", async () => {
  try {
    const tab = location.hash.match(/\/(profile|paldex|pals|inventory|bases)$/)?.[1] || "profile";
    await navigator.clipboard.writeText(playerShareRoute(selectedPlayer, tab));
    expeditionShare.textContent = "Lien public copié";
    expeditionShare.classList.add("is-success");
    expeditionShare.classList.remove("is-error");
    window.setTimeout(() => {
      expeditionShare.textContent = "Partager la fiche";
      expeditionShare.classList.remove("is-success");
    }, 3000);
  } catch {
    expeditionShare.textContent = "Copie impossible";
    expeditionShare.classList.add("is-error");
    expeditionShare.classList.remove("is-success");
    window.setTimeout(() => {
      expeditionShare.textContent = "Partager la fiche";
      expeditionShare.classList.remove("is-error");
    }, 3500);
  }
});
document.querySelector("#expedition-export")?.addEventListener("click", () => {
  void exportSelectedPlayerAnalysisJson();
});
palSearch.addEventListener("input", () => { palVisibleLimit = 24; renderPalCollection(); });
palContainerFilter.addEventListener("change", () => { palVisibleLimit = 24; renderPalCollection(); });
palSort.addEventListener("change", () => { palVisibleLimit = 24; renderPalCollection(); });
palLoadMore.addEventListener("click", () => { palVisibleLimit += 24; renderPalCollection(); });
expeditionPals?.addEventListener("click", (event) => {
  const button = event.target.closest("[data-load-breeding]");
  if (button) renderBreedingOptions(button);
});
inventorySearch.addEventListener("input", () => renderInventory(selectedPlayer));
}

if (isLeaderboardRoute()) {
  leaderboardSearch?.addEventListener("input", renderLeaderboards);
  leaderboardPresence?.addEventListener("change", renderLeaderboards);
  leaderboardCategory?.addEventListener("change", () => {
    const definition = leaderboardCategories[leaderboardCategory.value] || leaderboardCategories.progression;
    leaderboardSortKey = definition.primary;
    leaderboardSortDirection = "desc";
    renderLeaderboards();
  });
  leaderboardHead?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-leaderboard-sort]");
    if (!button) return;
    const key = button.dataset.leaderboardSort;
    if (leaderboardSortKey === key) leaderboardSortDirection = leaderboardSortDirection === "desc" ? "asc" : "desc";
    else {
      leaderboardSortKey = key;
      leaderboardSortDirection = "desc";
    }
    renderLeaderboards();
  });
}

if (isMapRoute()) {
  mapPlayerToggle?.addEventListener("click", () => {
    showMapPlayers = !showMapPlayers;
    renderGlobalPlayerMap(saveSnapshot?.players || [], currentBasesSnapshot()?.bases || []);
  });
  mapBaseToggle?.addEventListener("click", async () => {
    const shouldShow = !showMapBases;
    if (shouldShow && !currentBasesSnapshot()) await loadBases(true);
    showMapBases = shouldShow;
    renderGlobalPlayerMap(saveSnapshot?.players || [], currentBasesSnapshot()?.bases || []);
  });
  mapLegendToggle?.addEventListener("click", () => {
    showMapLegend = !showMapLegend;
    renderGlobalPlayerMap(saveSnapshot?.players || [], currentBasesSnapshot()?.bases || []);
  });
}

eventSearch?.addEventListener("input", () => { eventCurrentPage = 1; eventCursor = ""; syncEventControlsState(); void updateTerminalEvents(); });
eventTypeFilter?.addEventListener("change", () => { eventCurrentPage = 1; eventCursor = ""; syncEventControlsState(); void updateTerminalEvents(); });
eventPlayerFilter?.addEventListener("change", () => { eventCurrentPage = 1; eventCursor = ""; syncEventControlsState(); void updateTerminalEvents(); });
eventControls?.addEventListener("toggle", () => {
  if (isTerminalRoute() && eventsContractMode !== "v6" && (eventsSnapshot || eventsIndexSnapshot) && updateTerminalPageSize(true)) {
    void updateTerminalEvents(false);
  }
});
eventPagination?.addEventListener("click", (event) => {
  const button = event.target.closest("[data-event-page], [data-event-cursor]");
  if (!button || button.disabled) return;
  if (eventsContractMode === "v6") {
    eventCursor = button.dataset.eventCursor || "";
    eventCurrentPage = Number(button.dataset.eventPage) || 1;
  } else {
    eventCurrentPage = Number(button.dataset.eventPage) || 1;
  }
  void updateTerminalEvents().then(() => {
    document.querySelector("#event-stream").scrollIntoView({ behavior: prefersReducedMotion.matches ? "auto" : "smooth", block: "start" });
  });
});
eventPagination?.addEventListener("change", (event) => {
  const input = event.target.closest(".event-pagination__page-input");
  if (!input) return;
  const max = Math.max(1, Number(input.max || 1));
  const nextPage = clamp(Number(input.value || 1), 1, max);
  input.value = String(nextPage);
  if (nextPage === eventCurrentPage) return;
  eventCurrentPage = nextPage;
  eventCursor = "";
  void updateTerminalEvents().then(() => {
    document.querySelector("#event-stream").scrollIntoView({ behavior: prefersReducedMotion.matches ? "auto" : "smooth", block: "start" });
  });
});
eventPagination?.addEventListener("keydown", (event) => {
  const input = event.target.closest(".event-pagination__page-input");
  if (!input || event.key !== "Enter") return;
  event.preventDefault();
  input.blur();
});
eventDateInput?.addEventListener("change", () => {
  void selectEventDate(eventDateInput.value);
});
eventDatePrevious?.addEventListener("click", () => {
  const dates = v6NavigableDates();
  const index = dates.indexOf(eventSelectedDateKey);
  if (index >= 0 && dates[index + 1]) void selectEventDate(dates[index + 1]);
});
eventDateNext?.addEventListener("click", () => {
  const dates = v6NavigableDates();
  const index = dates.indexOf(eventSelectedDateKey);
  if (index > 0) void selectEventDate(dates[index - 1]);
});
eventDateToday?.addEventListener("click", () => {
  const today = dailyDateKeyFromDate(new Date());
  if (today) void selectEventDate(today);
});
eventUnseen?.addEventListener("click", () => {
  window.clearTimeout(terminalUnseenHideTimer);
  eventUnseen.hidden = true;
  markTerminalEchoesSeen();
  eventCursor = "";
  eventCurrentPage = 1;
  if (eventsContractMode === "v6") {
    renderEvents(false);
    writeTerminalState();
    document.querySelector("#event-stream")?.scrollIntoView({ behavior: prefersReducedMotion.matches ? "auto" : "smooth", block: "start" });
  }
});
dailyDateInput?.addEventListener("change", () => {
  void selectDailyDate(dailyDateInput.value);
});
dailyPrevious?.addEventListener("click", () => {
  const index = dailyAvailableDateKeys.indexOf(dailySelectedDateKey);
  const nextKey = index >= 0 ? dailyAvailableDateKeys[index + 1] : "";
  if (nextKey) void selectDailyDate(nextKey);
});
dailyNext?.addEventListener("click", () => {
  const index = dailyAvailableDateKeys.indexOf(dailySelectedDateKey);
  const nextKey = index > 0 ? dailyAvailableDateKeys[index - 1] : "";
  if (nextKey) void selectDailyDate(nextKey);
});
dailyToday?.addEventListener("click", () => {
  const today = dailyDateKeyFromDate(new Date());
  if (today) void selectDailyDate(today);
});
dailyTypes?.addEventListener("click", (event) => {
  const card = event.target.closest("[data-daily-type-filter]");
  if (!card || !dailyCurrentSummary) return;
  dailyHighlightTypeFilter = dailyHighlightTypeFilter === card.dataset.dailyTypeFilter ? "" : card.dataset.dailyTypeFilter;
  dailyTypes.innerHTML = renderDailyTypes(dailyCurrentSummary);
  if (dailyHighlights) dailyHighlights.innerHTML = renderDailyHighlights(dailyCurrentSummary);
});
dailyTypes?.addEventListener("keydown", (event) => {
  if (!["Enter", " "].includes(event.key)) return;
  const card = event.target.closest("[data-daily-type-filter]");
  if (!card) return;
  event.preventDefault();
  card.click();
});
dailyHighlights?.addEventListener("click", (event) => {
  if (!event.target.closest("[data-daily-filter-reset]") || !dailyCurrentSummary) return;
  dailyHighlightTypeFilter = "";
  if (dailyTypes) dailyTypes.innerHTML = renderDailyTypes(dailyCurrentSummary);
  dailyHighlights.innerHTML = renderDailyHighlights(dailyCurrentSummary);
});
palSearch?.addEventListener("keydown", clearSearchOnEscape);
inventorySearch?.addEventListener("keydown", clearSearchOnEscape);
eventSearch?.addEventListener("keydown", clearSearchOnEscape);
stockSearch?.addEventListener("keydown", clearSearchOnEscape);
inventorySectionFilter?.addEventListener("change", () => renderInventory(selectedPlayer));
backToTop?.addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: prefersReducedMotion.matches ? "auto" : "smooth" });
});
footerBackToTop?.addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: prefersReducedMotion.matches ? "auto" : "smooth" });
});
function syncBackToTop() {
  if (!backToTop || !siteFooter) return;
  const isVisible = window.scrollY > 520;
  const footerIsVisible = siteFooter.getBoundingClientRect().top < window.innerHeight;
  backToTop.classList.toggle("is-visible", isVisible);
  backToTop.classList.toggle("is-near-footer", footerIsVisible);
  backToTop.tabIndex = isVisible && !footerIsVisible ? 0 : -1;
}
syncBackToTop();
window.addEventListener("scroll", () => {
  syncBackToTop();
  updateContextTooltipAfterScroll();
  scheduleActiveNavigationUpdate();
}, { passive: true });
document.addEventListener("scroll", () => {
  updateContextTooltipAfterScroll();
}, { capture: true, passive: true });
document.addEventListener("pointerover", (event) => {
  const target = event.target.closest("[data-tooltip]");
  if (target && target !== activeTooltipTarget) showContextTooltip(target);
});
document.addEventListener("pointerout", (event) => {
  if (activeTooltipTarget && activeTooltipTarget.contains(event.target) && !activeTooltipTarget.contains(event.relatedTarget)) {
    hideContextTooltip();
  }
});
document.addEventListener("focusin", (event) => {
  const target = event.target.closest("[data-tooltip]");
  if (target) showContextTooltip(target);
});
document.addEventListener("focusout", (event) => {
  if (activeTooltipTarget && event.target === activeTooltipTarget) hideContextTooltip();
});
window.addEventListener("resize", () => {
  if (activeTooltipTarget) positionContextTooltip(activeTooltipTarget);
  syncBackToTop();
  if (isTerminalRoute() && (eventsSnapshot || eventsIndexSnapshot) && updateTerminalPageSize(true)) {
    void updateTerminalEvents(false);
  }
  scheduleActiveNavigationUpdate();
});
document.addEventListener("click", (event) => {
  const communityLink = event.target.closest("[data-analytics-link]");
  if (communityLink) trackCommunityLink(communityLink);
});
window.addEventListener("hashchange", () => {
  const nextLegacyRoute = legacyHashRoute();
  if (nextLegacyRoute) {
    location.replace(nextLegacyRoute);
    return;
  }
  syncTerminalView(true);
  if (location.hash === "#classements" && leaderboardDisclosure) leaderboardDisclosure.open = true;
  if (location.hash === "#evenements" && eventsDisclosure) eventsDisclosure.open = true;
  if (location.hash === "#carte" && mapDisclosure) {
    mapDisclosure.open = true;
    if (!currentBasesSnapshot()) loadBases(true);
  }
  openPlayerFromRoute();
  trackVirtualPageView();
  scheduleActiveNavigationUpdate();
});
window.addEventListener("popstate", () => {
  if (isDailyDigestRoute()) {
    dailySelectedDateKey = dailyRequestedDateKey();
    void loadDailyDigest(true);
  }
  openPlayerFromRoute();
  trackVirtualPageView();
});
document.addEventListener("error", (event) => {
  if (event.target instanceof HTMLImageElement && event.target.matches(".game-asset")) {
    const fallback = document.createElement("span");
    const label = String(event.target.alt || "Image").trim();
    fallback.className = [...event.target.classList]
      .filter((name) => name !== "game-asset")
      .concat("game-asset--empty")
      .join(" ");
    fallback.textContent = label.charAt(0).toLocaleUpperCase("fr-CA") || "?";
    if (event.target.alt) {
      fallback.setAttribute("role", "img");
      fallback.setAttribute("aria-label", `Image indisponible pour ${label}`);
    } else {
      fallback.setAttribute("aria-hidden", "true");
    }
    event.target.replaceWith(fallback);
  }
}, true);
