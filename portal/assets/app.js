const uptimeSummary = document.querySelector("#uptime-summary");
const uptimeBars = document.querySelector("#uptime-bars");
const playersList = document.querySelector("#players-list");
const headerPlayers = document.querySelector("#header-players");
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
const eventPageSizeControl = document.querySelector("#event-page-size");
const eventResultCount = document.querySelector("#event-result-count");
const eventStream = document.querySelector("#event-stream");
const eventPagination = document.querySelector("#event-pagination");
const globalPlayerMarkers = document.querySelector("#global-player-markers");
const globalPlayerLegend = document.querySelector("#global-player-legend");
const globalMapCaption = document.querySelector("#global-map-caption");
const globalMapViewport = document.querySelector("#global-map-viewport");
const globalMapScene = document.querySelector("#global-map-scene");
const globalMapImage = globalMapScene.querySelector("img[data-src]");
const globalMapZoom = document.querySelector("#global-map-zoom");
const mapBaseToggle = document.querySelector("#map-base-toggle");
const mapBaseCount = document.querySelector("#map-base-count");
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

const refreshEveryMs = 15000;
const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let nextRefreshAt = Date.now() + refreshEveryMs;
let refreshPending = false;
let refreshMessage = "";
let refreshMessageUntil = 0;
let refreshMessageState = "updated";
let clockTimer;
let saveSnapshot = null;
let statsSnapshot = null;
let fullSaveSnapshot = null;
let fullSaveSnapshotPromise = null;
const playerSnapshotCache = new Map();
const playerSnapshotPromises = new Map();
const renderedPlayerTabs = new Set();
let basesSnapshot = null;
let selectedPlayerBases = [];
let selectedPlayerStock = [];
let stockSource = "all";
let stockCurrentPage = 1;
const stockPageSize = 24;
let showMapBases = false;
let selectedPlayer = null;
let palVisibleLimit = 24;
let paldexCurrentPage = 1;
let paldexStatusFilter = "all";
let selectedPaldexKey = "";
const paldexPageSize = 30;
let playerActivityByName = new Map();
let eventsSnapshot = null;
let eventCurrentPage = 1;
const allowedTerminalPageSizes = new Set([25, 50, 100, 250]);
let terminalEventPageSize = Number(localStorage.getItem("gaylemon-terminal-page-size") || 25);
if (!allowedTerminalPageSizes.has(terminalEventPageSize)) terminalEventPageSize = 25;
eventPageSizeControl.value = String(terminalEventPageSize);
let leaderboardSortKey = "level";
let leaderboardSortDirection = "desc";
let backgroundScrollY = 0;
let playerViewLocked = false;
let playerReturnUrl = "";
let lastTrackedLocation = "";
let navUpdatePending = false;
const sourceUpdatedAt = new Map();
const dataRevisions = {
  metrics: "",
  stats: "",
  uptime: "",
  save: "",
  bases: "",
  diagnostics: "",
  events: "",
};

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

function currentDocumentTitle() {
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
  if (location.hash === "#terminal") {
    return "Journal des échos | Gaylémon Palworld";
  }
  return "Gaylémon Palworld | Progression, statistiques et serveur";
}

function currentDocumentDescription() {
  if (location.hash === "#terminal") {
    return "Le journal complet des arrivées, captures, défis, quêtes et aventures du serveur Gaylémon Palworld.";
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
  return `#joueur/${playerSlug(player?.name)}/${tab}`;
}

function playerShareRoute(player, tab = "profile") {
  return `${location.origin}/joueur/${playerSlug(player?.name)}/${tab}/`;
}

function parseDate(value) {
  if (!value) {
    return null;
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
  });
}

function registerDataUpdate(source, value) {
  const date = parseDate(value);
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
  siteLastUpdated.title = `Dernières données reçues le ${formatDateTime(latest)}`;
}

function updateActiveNavigation() {
  navUpdatePending = false;
  if (location.hash === "#terminal") {
    siteNavLinks.forEach((link) => {
      const isActive = link.dataset.sectionLink === "evenements";
      link.classList.toggle("is-active", isActive);
      if (isActive) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
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
  const active = location.hash === "#terminal";
  document.body.classList.toggle("terminal-view", active);
  if (active) {
    eventsDisclosure.open = true;
    if (eventsSnapshot) {
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

function renderSaveDiagnostics(payload) {
  if (!payload?.ok || !worldDataGrid) return;
  registerDataUpdate("diagnostics", payload.updatedAt);
  const save = payload.save || {};
  const parse = payload.parse || {};
  const output = payload.output || {};
  const publicOutput = payload.publicOutput || {};
  const assets = payload.assets || {};
  setWorldData("level", formatBytes(save.levelBytes));
  setWorldData("players", formatBytes(save.playersBytes));
  setWorldDataNote("players", `${Number(save.playerFiles || 0)} profils analysés`);
  setWorldData("generation", formatBytes(save.generationBytes));
  setWorldData("snapshot", formatBytes(publicOutput.snapshotBytes || output.snapshotBytes));
  setWorldData("bases", formatBytes(publicOutput.basesBytes || output.basesBytes));
  setWorldDataNote("bases", `${formatBytes(output.basesGzipBytes)} compressées · chargées dans la section Bases`);
  setWorldData("index", formatBytes(publicOutput.indexBytes));
  setWorldData("duration", parse.durationMs == null ? "--" : `${(Number(parse.durationMs) / 1000).toLocaleString("fr-CA", { maximumFractionDigits: 2 })} s`);
  const age = Number(save.backupAgeSeconds || 0);
  setWorldDataNote("freshness", age < 60 ? `Sauvegarde âgée de ${age} s lors de l'analyse` : `Sauvegarde âgée de ${Math.round(age / 60)} min lors de l'analyse`);
  setWorldData("map", `${Number(assets.worldMapWidth || 8192).toLocaleString("fr-CA")} × ${Number(assets.worldMapHeight || 8192).toLocaleString("fr-CA")}`);
  setWorldData("parser", String(payload.parser?.commit || "--").slice(0, 12));
  setWorldDataNote("parser", "PalworldSaveTools · catalogue synchronisé");
  worldDataState.textContent = parse.status === "ok" ? "Analyse saine" : "Analyse à surveiller";
  worldDataState.dataset.state = parse.status === "ok" ? "up" : "warning";
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

  return [...playersBySlug.values()];
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
              <i class="${activity?.isOnline ? "is-online" : ""}" title="${activity?.isOnline ? "En ligne" : "Hors ligne"}"></i>
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
    refreshStatus.dataset.state = "syncing";
    refreshProgress.style.transform = "scaleX(1)";
    return;
  }

  if (refreshMessage && Date.now() < refreshMessageUntil) {
    nextUpdate.textContent = refreshMessage;
    refreshStatus.dataset.state = refreshMessageState;
    refreshProgress.style.transform = "scaleX(1)";
    return;
  }

  refreshMessage = "";
  refreshStatus.dataset.state = "countdown";
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

  if (remainingMs === 0) void refreshDataInBackground();
}

function startRefreshClock() {
  window.clearInterval(clockTimer);
  clockTimer = window.setInterval(renderNextUpdate, 250);
}

function renderMetrics(payload) {
  if (!payload?.ok) {
    playersList.textContent = payload?.error || "Les données du serveur ne sont pas encore disponibles.";
    headerPlayers.title = playersList.textContent;
    registerDataUpdate("metrics", payload?.updatedAt);
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

  registerDataUpdate("metrics", payload.updatedAt);
  const players = Array.isArray(payload.players) ? payload.players : [];
  playersList.textContent = players.length
    ? players.map((player) => player.name || "Joueur").join(", ")
    : "Aucun joueur connecté.";
  headerPlayers.title = playersList.textContent;
  headerPlayers.dataset.state = players.length ? "online" : "empty";
}

function renderUptime(payload) {
  if (!payload?.ok) {
    uptimeSummary.textContent = payload?.error || "La disponibilité sera affichée au prochain passage du collecteur.";
    uptimeBars.innerHTML = createPlaceholderBars();
    registerDataUpdate("uptime", payload?.updatedAt);
    return;
  }

  const monitor = Array.isArray(payload.monitors) ? payload.monitors[0] : null;
  const summary = payload.summary || {};
  const status = monitor?.status || summary.status || "unknown";
  const uptime = monitor?.uptime24h ?? summary.uptime24hAverage;
  const ping = monitor?.ping;

  registerDataUpdate("uptime", payload.updatedAt);
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
      return "Vérification en cours";
    default:
      return "Synchronisation en cours";
  }
}

function createPlaceholderBars() {
  return Array.from({ length: 24 }, () => '<span class="uptime-segment uptime-segment--unknown"></span>').join("");
}

function renderStats(payload) {
  if (!payload?.ok) {
    statsSnapshot = null;
    return;
  }

  registerDataUpdate("stats", payload.updatedAt);

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

function renderGlobalPlayerMap(players, bases = basesSnapshot?.bases || []) {
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
    return;
  }

  const playerMarkers = positioned.map(({ player, index }, markerIndex) => {
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
  }).join("");
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

  const playerLegend = positioned.map(({ player, index }) => {
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
  }).join("");
  const unchartedLegend = uncharted.map(({ player, index }) => {
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
  }).join("");
  const baseLegend = showMapBases && positionedBases.length ? `
    <div class="global-base-legend">
      <strong>${positionedBases.length} base${positionedBases.length > 1 ? "s" : ""} cartographiée${positionedBases.length > 1 ? "s" : ""}</strong>
      <span>${[...new Set(positionedBases.map((base) => base.guild))].length} guildes établies sur l'archipel</span>
      <span>Ouvre la fiche d'un aventurier pour explorer ses campements.</span>
    </div>
  ` : "";
  globalPlayerLegend.innerHTML = playerLegend + unchartedLegend + baseLegend;
  const unchartedNote = uncharted.length
    ? ` · ${uncharted.length} en zone non cartographiée`
    : "";
  globalMapCaption.textContent = (showMapBases
    ? `${positioned.length} aventurier${positioned.length > 1 ? "s" : ""} et ${positionedBases.length} base${positionedBases.length > 1 ? "s" : ""} sur la carte`
    : `${positioned.length} aventurier${positioned.length > 1 ? "s" : ""} sur la carte · les bases sont masquées`) + unchartedNote;
  const visibleBaseCount = basesSnapshot
    ? positionedBases.length
    : Number(saveSnapshot?.summary?.bases || 0);
  if (mapBaseCount) mapBaseCount.textContent = visibleBaseCount;
  if (mapBaseToggle) {
    mapBaseToggle.setAttribute("aria-pressed", String(showMapBases));
    mapBaseToggle.classList.toggle("is-active", showMapBases);
    const label = mapBaseToggle.querySelector("b");
    if (label) label.textContent = showMapBases ? "Masquer les bases" : "Afficher les bases";
    mapBaseToggle.title = showMapBases ? "Masquer les bases de la carte" : "Afficher les bases sur la carte";
  }
}

function updateGlobalPlayerActivity() {
  if (!saveSnapshot) return;

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
  if (!saveSnapshot) return;

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
    saveState.textContent = "En attente";
    return;
  }

  const summary = payload.summary || {};
  const players = getDisplayPlayers(payload);
  saveSnapshot = { ...payload, players };
  saveState.textContent = "Données synchronisées";
  registerDataUpdate("save", payload.updatedAt);
  const summaryValues = {
    players: players.length,
    pals: Number(summary.pals || 0),
    guilds: Number(summary.guilds || 0),
    bases: Number(summary.bases || 0),
    levels: players.reduce((total, player) => total + Number(player.level || 0), 0),
    technologies: players.reduce((total, player) => total + Number(player.progress?.unlockedTechnologies || 0), 0),
  };
  Object.entries(summaryValues).forEach(([key, value]) => {
    const element = saveSummary.querySelector(`[data-save-summary="${key}"]`);
    if (element) element.textContent = value.toLocaleString("fr-CA");
  });
  renderGlobalPlayerMap(players);

  if (!players.length) {
    savePlayers.innerHTML = '<p class="save-empty">Aucun aventurier n\'a encore laissé sa marque dans les sauvegardes.</p>';
    return;
  }

  savePlayers.innerHTML = players.map((player, index) => {
    const pals = player.pals || {};
    const progress = player.progress || {};
    const activity = getPlayerActivityValues(player);
    const favorites = Array.isArray(pals.favorites) ? pals.favorites : [];
    const cardAccent = playerColor(player);
    if (player.provisional) {
      const level = player.level == null ? "--" : Number(player.level);
      return `
        <article class="adventurer-card adventurer-card--provisional" data-player-slug="${playerSlug(player.name)}" style="--card-order: ${index};--card-accent:${cardAccent}">
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
          <div class="adventurer-card__activity" aria-label="Activité de ${escapeHtml(player.name || "ce joueur")}">
            <span><small>Connexions</small><strong data-player-activity="sessions">${activity.sessions}</strong></span>
            <span><small>Temps joué</small><strong data-player-activity="playtime">${activity.playtime}</strong></span>
            <span><small>Dernière vue</small><strong data-player-activity="lastSeen">${activity.lastSeen}</strong></span>
            <span><small>Dernier ping</small><strong data-player-activity="ping">${activity.ping}</strong></span>
          </div>
          <a class="adventurer-card__open" href="${playerRoute(player)}" data-player-index="${index}">Voir la fiche de ${escapeHtml(player.name || "ce joueur")}</a>
        </article>
      `;
    }
    const favoritePortraits = favorites.length
      ? favorites.slice(0, 3).map((pal) => gameImage(pal.icon, pal.name, "adventurer-card__pal")).join("")
      : `<span class="adventurer-card__pal adventurer-card__pal--empty">${escapeHtml(playerInitials(player.name))}</span>`;
    const favoriteMarkup = favorites.length
      ? favorites.map((pal) => `<span>${escapeHtml(pal.name)}${Number(pal.count || 0) > 1 ? ` ×${Number(pal.count)}` : ""}</span>`).join("")
      : "<span>À découvrir</span>";

    return `
      <article class="adventurer-card" data-player-slug="${playerSlug(player.name)}" style="--card-order: ${index};--card-accent:${cardAccent}">
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
          <div class="adventurer-card__portraits" aria-label="Pals favoris de ${escapeHtml(player.name || "ce joueur")}">
            ${favoritePortraits}
          </div>
        </div>
        <div class="adventurer-card__numbers">
          <span><strong>${Number(pals.total || 0)}</strong>Pals</span>
          <span><strong>${Number(pals.uniqueSpecies || 0)}</strong>espèces</span>
          <span><strong>${Number(pals.highestLevel || 0)}</strong>meilleur niveau</span>
        </div>
        <div class="pal-favorites">
          <small>Compagnons les plus présents</small>
          <div>${favoriteMarkup}</div>
        </div>
        <div class="adventurer-card__progress">
          ${progress.paldex ? `
            <span>${Number(progress.paldex.capturedSpecies || 0)} / ${Number(progress.paldex.totalSpecies || 0)} au Paldex</span>
            <span>${Number(progress.bosses?.defeated || 0)} boss vaincus</span>
            <span>${formatProgressPercent(progress.exploration?.completionPercent)} exploré</span>
          ` : `
            <span>${Number(progress.unlockedTechnologies || 0)} technologies</span>
            <span>${Number(progress.completedQuests || 0)} quêtes</span>
            <span>${Number(pals.party || 0)} dans l'équipe</span>
          `}
        </div>
        <div class="adventurer-card__activity" aria-label="Activité de ${escapeHtml(player.name || "ce joueur")}">
          <span><small>Connexions</small><strong data-player-activity="sessions">${activity.sessions}</strong></span>
          <span><small>Temps joué</small><strong data-player-activity="playtime">${activity.playtime}</strong></span>
          <span><small>Dernière vue</small><strong data-player-activity="lastSeen">${activity.lastSeen}</strong></span>
          <span><small>Dernier ping</small><strong data-player-activity="ping">${activity.ping}</strong></span>
        </div>
        <a class="adventurer-card__open" href="${playerRoute(player)}" data-player-index="${index}">Voir la fiche de ${escapeHtml(player.name || "ce joueur")}</a>
      </article>
    `;
  }).join("");
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
        <span title="Satiété"><small>Faim</small><b>${Math.round(Number(worker.hunger || 0))}</b></span>
        <span title="Santé mentale"><small>SAN</small><b>${worker.sanity == null ? "--" : Math.round(Number(worker.sanity))}</b></span>
        <span title="Vitesse de travail calculée"><small>Travail</small><b>${worker.computedStats?.workSpeed ?? "--"}</b></span>
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
  (Array.isArray(basesSnapshot?.guildStorage) ? basesSnapshot.guildStorage : [])
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
        <strong title="${escapeHtml(item.name)}">${escapeHtml(item.name)}</strong>
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
  selectedPlayerBases = (Array.isArray(basesSnapshot?.bases) ? basesSnapshot.bases : [])
    .filter((base) => baseBelongsToPlayer(base, selectedPlayer));
  selectedPlayerStock = buildSelectedPlayerStock();
  const workers = selectedPlayerBases.reduce((total, base) => total + Number(base.workers?.assigned || 0), 0);
  const busyWorkers = selectedPlayerBases.reduce((total, base) => total + Number(base.workers?.busy || 0), 0);
  const guildStorageUnits = (Array.isArray(basesSnapshot?.guildStorage) ? basesSnapshot.guildStorage : [])
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
  basesState.textContent = basesSnapshot ? "Campements synchronisés" : "Chargement...";
  baseGrid.innerHTML = selectedPlayerBases.length
    ? selectedPlayerBases.map(baseCardMarkup).join("")
    : '<p class="detail-empty detail-empty--large">Aucun campement n’est associé à cet aventurier.</p>';
  renderStockExplorer();
  filterBases();
}

function renderBaseSnapshot(payload) {
  if (!payload?.ok || !Array.isArray(payload.bases)) {
    basesState.textContent = "En attente";
    return;
  }
  basesSnapshot = payload;
  registerDataUpdate("bases", payload.updatedAt);
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
  collection: { label: "Collections", token: "PAL", color: "#4da2dd" },
  level: { label: "Niveaux", token: "LVL", color: "#f1b94f" },
  progress: { label: "Progression", token: "XP", color: "#b88bdd" },
  camp: { label: "Camps et bases", token: "BASE", color: "#79b85a" },
  discovery: { label: "Découvertes", token: "NEW", color: "#e96c9b" },
  maintenance: { label: "Maintenances", token: "MAJ", color: "#e7a934" },
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

function renderEventFilters(events) {
  const selectedType = eventTypeFilter.value || "all";
  const selectedPlayer = eventPlayerFilter.value || "all";
  const types = [...new Set(events.map((event) => event.type).filter(Boolean))];
  const players = [...new Set(events.map((event) => event.player).filter(Boolean))]
    .sort((left, right) => left.localeCompare(right, "fr-CA"));

  eventTypeFilter.innerHTML = [
    '<option value="all">Tous les événements</option>',
    ...types.map((type) => `<option value="${escapeHtml(type)}">${escapeHtml(eventTypeMeta[type]?.label || type)}</option>`),
  ].join("");
  eventPlayerFilter.innerHTML = [
    '<option value="all">Tous les aventuriers</option>',
    ...players.map((player) => `<option value="${escapeHtml(player)}">${escapeHtml(player)}</option>`),
  ].join("");
  if (types.includes(selectedType)) eventTypeFilter.value = selectedType;
  if (players.includes(selectedPlayer)) eventPlayerFilter.value = selectedPlayer;
}

function eventPageNumbers(current, total) {
  const pages = new Set([1, total, current - 2, current - 1, current, current + 1, current + 2]);
  return [...pages].filter((page) => page >= 1 && page <= total).sort((left, right) => left - right);
}

function renderEvents() {
  const events = Array.isArray(eventsSnapshot?.events) ? eventsSnapshot.events : [];
  const query = normalizeEventSearch(eventSearch.value);
  const type = eventTypeFilter.value;
  const player = eventPlayerFilter.value;
  const filtered = events.filter((event) => {
    if (type !== "all" && event.type !== type) return false;
    if (player !== "all" && event.player !== player) return false;
    if (!query) return true;
    return normalizeEventSearch([event.player, event.title, event.message, event.type].filter(Boolean).join(" ")).includes(query);
  });
  const pageSize = location.hash === "#terminal" ? terminalEventPageSize : 5;
  const pageCount = Math.max(1, Math.ceil(filtered.length / pageSize));
  eventCurrentPage = Math.min(Math.max(1, eventCurrentPage), pageCount);
  const start = (eventCurrentPage - 1) * pageSize;
  const visible = filtered.slice(start, start + pageSize);

  const resultLabel = filtered.length === events.length
    ? `${events.length} événement${events.length > 1 ? "s" : ""} dans l'historique`
    : `${filtered.length} résultat${filtered.length > 1 ? "s" : ""} sur ${events.length}`;
  eventResultCount.textContent = `${resultLabel} · page ${eventCurrentPage} sur ${pageCount}`;

  if (!visible.length) {
    eventStream.innerHTML = '<li class="event-stream__empty">Aucun écho ne correspond à cette recherche.</li>';
  } else {
    eventStream.innerHTML = visible.map((event) => {
      const meta = eventTypeMeta[event.type] || eventTypeMeta.server;
      const timestamp = formatEventTime(event.occurredAt);
      const accent = event.player ? playerColor(event.player) : meta.color;
      const visual = event.icon
        ? gameImage(event.icon, "", "event-line__portrait")
        : `<span class="event-line__token" aria-hidden="true">${escapeHtml(meta.token)}</span>`;
      return `
        <li class="event-line event-line--${escapeHtml(event.type)}" style="--event-accent:${accent}">
          <time datetime="${escapeHtml(event.occurredAt)}"><strong>${escapeHtml(timestamp.date)} · ${escapeHtml(timestamp.time)}</strong></time>
          <span class="event-line__rail" aria-hidden="true"><i></i></span>
          <span class="event-line__visual">${visual}</span>
          <span class="event-line__content">
            <span class="event-line__meta"><b>${escapeHtml(meta.label)}</b>${event.player ? `<em>${escapeHtml(event.player)}</em>` : ""}</span>
            <strong>${escapeHtml(event.title)}</strong>
            <span>${escapeHtml(event.message)}</span>
          </span>
        </li>`;
    }).join("");
  }

  if (pageCount <= 1) {
    eventPagination.innerHTML = "";
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

function renderEventSnapshot(payload) {
  eventsSnapshot = payload;
  const events = Array.isArray(payload?.events) ? payload.events : [];
  eventsState.textContent = `${events.length} écho${events.length > 1 ? "s" : ""} surveillé${events.length > 1 ? "s" : ""}`;
  eventsState.dataset.state = "live";
  registerDataUpdate("events", payload.updatedAt);
  if (eventsDisclosure?.open) {
    renderEventFilters(events);
    renderEvents();
  }
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
    if (name === "pals") renderPalCollection();
    if (name === "inventory") renderInventory(selectedPlayer);
    if (name === "bases") {
      if (basesSnapshot) renderSelectedPlayerBases();
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
  const pals = Array.isArray(player.pals?.collection) ? player.pals.collection : [];
  const party = pals.filter((pal) => pal.container === "party");
  const portraits = [...party, ...pals].slice(0, 3);
  expeditionPlayerEmblem.innerHTML = portraits.length
    ? portraits.map((pal) => gameImage(pal.icon, "", "player-emblem-pal")).join("")
    : `<span class="player-emblem-fallback">${escapeHtml(playerInitials(player.name))}</span>`;
  expeditionPlayerMeta.textContent = player.provisional
    ? `Niveau ${player.level == null ? "à confirmer" : Number(player.level)} · progression en cours de sauvegarde`
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
        <article class="profile-stat profile-stat--xp"><span>Expérience enregistrée</span><strong>${Number(character.experience || 0).toLocaleString("fr-CA")}</strong><small>EXP dans la sauvegarde</small></article>
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
  const equippedItems = sections
    .filter((section) => ["weapons", "armor", "food"].includes(section.key))
    .flatMap((section) => (section.items || []).map((item) => ({ ...item, sectionLabel: section.label })));
  inventoryOverview.innerHTML = `
    <span><strong>${allItems.length}</strong> types d'objets</span>
    <span><strong>${totalQuantity.toLocaleString("fr-CA")}</strong> unités au total<small>Somme des quantités de toutes les piles</small></span>
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
    return `
      <article class="pal-detail-card">
        <div class="pal-detail-card__portrait">
          ${gameImage(pal.icon, pal.species, "pal-portrait")}
          <span>${containerLabel}</span>
        </div>
        <div class="pal-detail-card__body">
          <header><div><small>${escapeHtml(pal.species)}</small><h3>${escapeHtml(pal.name)}</h3></div><b>Niv. ${Number(pal.level || 0)}</b></header>
          ${badges.length || pal.rank != null ? `<div class="pal-badges">${badges.map((badge) => `<span>${badge}</span>`).join("")}${pal.rank != null ? `<span>Condensation ${Number(pal.rank)}</span>` : ""}</div>` : ""}
          <div class="pal-vitals"><span>PV ${Number(pal.hp || 0).toLocaleString("fr-CA")}${pal.maxHp ? ` / ${Number(pal.maxHp).toLocaleString("fr-CA")}` : ""}</span><span>Amitié ${Number(pal.friendship || 0)}</span><span>${escapeHtml(gender)}</span>${pal.sanity != null ? `<span>SAN ${Math.round(Number(pal.sanity))}%</span>` : ""}</div>
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
          ${(pal.healthStatus || pal.ownedAt) ? `<div class="pal-footnotes">${pal.healthStatus ? `<span>État: ${escapeHtml(pal.healthStatus)}</span>` : ""}${pal.ownedAt ? `<span>Acquis le ${escapeHtml(formatDateTime(pal.ownedAt))}</span>` : ""}</div>` : ""}
        </div>
      </article>
    `;
  }).join("") : '<p class="detail-empty detail-empty--large">Aucun Pal ne correspond à cette recherche.</p>';
}

async function ensureFullSaveSnapshot() {
  if (fullSaveSnapshot) return fullSaveSnapshot;
  if (!fullSaveSnapshotPromise) {
    fullSaveSnapshotPromise = readJson("data/public-save-snapshot.json")
      .then((payload) => {
        fullSaveSnapshot = payload;
        return payload;
      })
      .finally(() => {
        fullSaveSnapshotPromise = null;
      });
  }
  return fullSaveSnapshotPromise;
}

async function ensurePlayerSnapshot(indexedPlayer) {
  const slug = playerSlug(indexedPlayer?.name);
  const revision = String(saveSnapshot?.updatedAt || "");
  const cached = playerSnapshotCache.get(slug);
  if (cached?.revision === revision) return cached.payload;
  if (playerSnapshotPromises.has(slug)) return playerSnapshotPromises.get(slug);

  const promise = readJson(`data/players/${slug}.json`)
    .then((payload) => {
      if (!payload?.ok || !payload.player) throw new Error("Invalid player snapshot");
      playerSnapshotCache.set(slug, { revision, payload });
      return payload;
    })
    .catch(async () => {
      const payload = await ensureFullSaveSnapshot();
      const player = (payload?.players || []).find((row) => playerSlug(row.name) === slug);
      if (!player) throw new Error("Player profile unavailable");
      const fallback = { ok: true, updatedAt: payload.updatedAt, player };
      playerSnapshotCache.set(slug, { revision, payload: fallback });
      return fallback;
    })
    .finally(() => playerSnapshotPromises.delete(slug));
  playerSnapshotPromises.set(slug, promise);
  return promise;
}

async function openPlayerDetails(index, tab = "profile", updateRoute = true) {
  const indexedPlayers = Array.isArray(saveSnapshot?.players) ? saveSnapshot.players : [];
  const indexedPlayer = indexedPlayers[index];
  if (!indexedPlayer) return;

  let payload = null;
  if (indexedPlayer.provisional) {
    selectedPlayer = indexedPlayer;
  } else {
    try {
      payload = await ensurePlayerSnapshot(indexedPlayer);
    } catch {
      saveState.textContent = "Fiches momentanément indisponibles";
      return;
    }
    selectedPlayer = payload.player;
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
  expeditionPals.innerHTML = '<p class="detail-empty detail-empty--large">La collection sera préparée à l’ouverture de cet onglet.</p>';
  expeditionInventory.innerHTML = '<p class="detail-empty detail-empty--large">L’inventaire sera préparé à l’ouverture de cet onglet.</p>';
  const activeTab = selectedPlayer.provisional ? "profile" : tab;
  switchDetailTab(activeTab, false);
  const willOpenDialog = !expeditionDialog.open;
  if (willOpenDialog) lockPlayerView();
  if (updateRoute) history.replaceState(null, "", playerRoute(selectedPlayer, activeTab));
  if (willOpenDialog) expeditionDialog.showModal();
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
  if (expeditionDialog.open) expeditionDialog.close();
  selectedPlayer = null;
  selectedPlayerBases = [];
  history.replaceState(null, "", playerReturnUrl || `${location.pathname}${location.search}`);
  trackVirtualPageView();
  unlockPlayerView();
}

let activeTooltipTarget = null;

function positionContextTooltip(target) {
  const text = target?.dataset.tooltip;
  if (!text) return;
  contextTooltip.textContent = text;
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

async function readJson(path) {
  const response = await fetch(`${path}?ts=${Date.now()}`, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  return response.json();
}

function isNewDataRevision(source, payload) {
  const revision = String(payload?.revision || payload?.updatedAt || "");
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
    if (!silent) {
      playersList.textContent = "Les données apparaîtront automatiquement au prochain passage du collecteur.";
      headerPlayers.title = playersList.textContent;
    }
    return { ok: false, changed: false };
  }
}

async function loadStats(silent = false) {
  try {
    const payload = await readJson("data/public-stats.json");
    const changed = isNewDataRevision("stats", payload);
    if (changed) renderStats(payload);
    return { ok: true, changed };
  } catch {
    if (!silent) statsSnapshot = null;
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
    if (!silent) {
      uptimeSummary.textContent = "La disponibilité apparaîtra automatiquement après le prochain passage du collecteur.";
      uptimeBars.innerHTML = createPlaceholderBars();
    }
    return { ok: false, changed: false };
  }
}

async function loadSaveSnapshot(silent = false, syncRoute = true) {
  try {
    const payload = await readJson("data/public-save-index.json");
    const changed = isNewDataRevision("save", payload);
    if (changed) {
      fullSaveSnapshot = null;
      playerSnapshotCache.clear();
      renderSaveSnapshot(payload, syncRoute);
    }
    return { ok: true, changed };
  } catch {
    if (!silent) {
      saveState.textContent = "En attente";
    }
    return { ok: false, changed: false };
  }
}

async function loadSaveDiagnostics(silent = false) {
  try {
    const payload = await readJson("data/public-save-diagnostics.json");
    const changed = isNewDataRevision("diagnostics", payload);
    if (changed) renderSaveDiagnostics(payload);
    return { ok: true, changed };
  } catch {
    if (!silent && worldDataState) worldDataState.textContent = "En attente";
    return { ok: false, changed: false };
  }
}

async function loadBases(silent = false) {
  try {
    const payload = await readJson("data/public-save-bases.json");
    const changed = isNewDataRevision("bases", payload);
    if (changed) renderBaseSnapshot(payload);
    return { ok: true, changed };
  } catch {
    if (!silent) {
      basesState.textContent = "En attente";
      baseResultCount.textContent = "Les données des bases arriveront au prochain passage du collecteur.";
    }
    return { ok: false, changed: false };
  }
}

function setupLazyBaseData() {
  if (basesSnapshot) return;
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

async function loadEvents(silent = false) {
  try {
    const payload = await readJson("data/public-events.json");
    const changed = isNewDataRevision("events", payload);
    if (changed) renderEventSnapshot(payload);
    return { ok: true, changed };
  } catch {
    if (!silent) {
      eventsState.textContent = "En attente";
      eventResultCount.textContent = "Historique momentanément indisponible";
      eventStream.innerHTML = '<li class="event-stream__empty">Les événements apparaîtront après le prochain passage du collecteur.</li>';
    }
    return { ok: false, changed: false };
  }
}

async function refreshDataInBackground() {
  if (refreshPending) return;

  refreshPending = true;
  renderNextUpdate();
  const results = await Promise.all([
    loadMetrics(true),
    loadStats(true),
    loadUptime(true),
    loadSaveSnapshot(true, false),
    basesSnapshot ? loadBases(true) : Promise.resolve({ ok: true, changed: false }),
    loadSaveDiagnostics(true),
    loadEvents(true),
  ]);
  const synchronizedSources = results.filter((result) => result.ok).length;
  const changedSources = results.filter((result) => result.changed).length;

  nextRefreshAt = Date.now() + refreshEveryMs;
  refreshPending = false;
  refreshMessageState = synchronizedSources ? "updated" : "error";
  const refreshTime = new Date().toLocaleTimeString("fr-CA", { hour: "2-digit", minute: "2-digit" });
  refreshMessage = synchronizedSources
    ? (changedSources ? `À jour · ${refreshTime}` : `Vérifié · ${refreshTime}`)
    : "Nouvel essai bientôt";
  refreshMessageUntil = Date.now() + 6500;
  renderNextUpdate();
}

syncTerminalView();
if (location.hash === "#carte" && mapDisclosure) mapDisclosure.open = true;
if (location.hash === "#classements" && leaderboardDisclosure) leaderboardDisclosure.open = true;
if (location.hash === "#evenements" && eventsDisclosure) eventsDisclosure.open = true;

const initialBaseLoad = location.hash === "#carte"
  ? loadBases()
  : Promise.resolve({ ok: true, changed: false });

Promise.all([loadMetrics(), loadStats(), loadUptime(), loadSaveSnapshot(), initialBaseLoad, loadSaveDiagnostics(), loadEvents()]).then(() => {
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

window.addEventListener("pagehide", () => window.clearInterval(clockTimer));

savePlayers.addEventListener("click", (event) => {
  const link = event.target.closest("[data-player-index]");
  if (link) {
    event.preventDefault();
    openPlayerDetails(Number(link.dataset.playerIndex));
  }
});

document.querySelector(".archipelago-overview").addEventListener("click", (event) => {
  const link = event.target.closest("[data-player-index]");
  if (link) {
    event.preventDefault();
    openPlayerDetails(Number(link.dataset.playerIndex));
    return;
  }
});

document.querySelector('a[href="#chroniques"]').addEventListener("click", () => {
  document.querySelector('[data-disclosure-key^="chronicles-content"]').open = true;
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
  if (!eventsDisclosure.open || !eventsSnapshot) return;
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
    if (!basesSnapshot) loadBases(true);
  });
});

mapDisclosure?.addEventListener("toggle", () => {
  if (!mapDisclosure.open) return;
  loadDeferredImage(globalMapImage);
  if (!basesSnapshot) loadBases(true);
  window.requestAnimationFrame(restoreGlobalMapView);
});

mapBaseToggle?.addEventListener("click", async () => {
  const shouldShow = !showMapBases;
  if (shouldShow && !basesSnapshot) await loadBases(true);
  showMapBases = shouldShow;
  renderGlobalPlayerMap(saveSnapshot?.players || [], basesSnapshot?.bases || []);
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
palSearch.addEventListener("input", () => { palVisibleLimit = 24; renderPalCollection(); });
palContainerFilter.addEventListener("change", () => { palVisibleLimit = 24; renderPalCollection(); });
palSort.addEventListener("change", () => { palVisibleLimit = 24; renderPalCollection(); });
palLoadMore.addEventListener("click", () => { palVisibleLimit += 24; renderPalCollection(); });
inventorySearch.addEventListener("input", () => renderInventory(selectedPlayer));
eventSearch.addEventListener("input", () => { eventCurrentPage = 1; renderEvents(); });
eventTypeFilter.addEventListener("change", () => { eventCurrentPage = 1; renderEvents(); });
eventPlayerFilter.addEventListener("change", () => { eventCurrentPage = 1; renderEvents(); });
eventPageSizeControl.addEventListener("change", () => {
  const requested = Number(eventPageSizeControl.value);
  terminalEventPageSize = allowedTerminalPageSizes.has(requested) ? requested : 25;
  eventPageSizeControl.value = String(terminalEventPageSize);
  localStorage.setItem("gaylemon-terminal-page-size", String(terminalEventPageSize));
  eventCurrentPage = 1;
  renderEvents();
});
eventPagination.addEventListener("click", (event) => {
  const button = event.target.closest("[data-event-page]");
  if (!button || button.disabled) return;
  eventCurrentPage = Number(button.dataset.eventPage) || 1;
  renderEvents();
  document.querySelector("#event-stream").scrollIntoView({ behavior: prefersReducedMotion.matches ? "auto" : "smooth", block: "start" });
});
palSearch.addEventListener("keydown", clearSearchOnEscape);
inventorySearch.addEventListener("keydown", clearSearchOnEscape);
eventSearch.addEventListener("keydown", clearSearchOnEscape);
stockSearch?.addEventListener("keydown", clearSearchOnEscape);
inventorySectionFilter.addEventListener("change", () => renderInventory(selectedPlayer));
backToTop.addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: prefersReducedMotion.matches ? "auto" : "smooth" });
});
footerBackToTop.addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: prefersReducedMotion.matches ? "auto" : "smooth" });
});
function syncBackToTop() {
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
  scheduleActiveNavigationUpdate();
});
document.addEventListener("click", (event) => {
  const communityLink = event.target.closest("[data-analytics-link]");
  if (communityLink) trackCommunityLink(communityLink);
});
window.addEventListener("hashchange", () => {
  syncTerminalView(true);
  if (location.hash === "#classements" && leaderboardDisclosure) leaderboardDisclosure.open = true;
  if (location.hash === "#evenements" && eventsDisclosure) eventsDisclosure.open = true;
  if (location.hash === "#carte" && mapDisclosure) {
    mapDisclosure.open = true;
    if (!basesSnapshot) loadBases(true);
  }
  openPlayerFromRoute();
  trackVirtualPageView();
  scheduleActiveNavigationUpdate();
});
window.addEventListener("popstate", () => {
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
