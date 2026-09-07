import { clamp } from "../shared/format.js";

export function createMapController({ globalMapViewport, globalMapScene, globalMapZoom, globalMapImage, globalMapFigure, loadDeferredImage, syncGlobalMapControls, mapState }) {
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
        mapState.expandedFallback = false;
      } else if (globalMapFigure.requestFullscreen) {
        await globalMapFigure.requestFullscreen();
        mapState.expandedFallback = false;
      } else {
        mapState.expandedFallback = !mapState.expandedFallback;
      }
    } catch {
      mapState.expandedFallback = !mapState.expandedFallback;
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

  return { applyGlobalMapView, restoreGlobalMapView, toggleGlobalMapFullscreen };
}
