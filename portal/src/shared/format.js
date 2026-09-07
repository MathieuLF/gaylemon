export function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}

export function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

export function escapeRegExp(value) {
  return String(value ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function playerSlug(name) {
  return String(name || "joueur")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("fr-CA")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "") || "joueur";
}

export function playerInitials(name) {
  const parts = String(name || "Joueur").split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  if (parts.length > 1) {
    return parts.slice(0, 2).map((part) => part[0]).join("").toLocaleUpperCase("fr-CA");
  }
  return (parts[0] || "J").slice(0, 2).toLocaleUpperCase("fr-CA");
}

export function parseDate(value) {
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

export function formatInteger(value) {
  return Number(value || 0).toLocaleString("fr-CA");
}

export function formatCompactDuration(seconds) {
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

export function formatPercent(value) {
  if (value == null || Number.isNaN(Number(value))) {
    return "--";
  }

  const number = Number(value);
  return `${number.toLocaleString("fr-CA", {
    minimumFractionDigits: number === 100 ? 0 : 2,
    maximumFractionDigits: 2,
  })} %`;
}

export function formatProgressPercent(value) {
  if (value == null || Number.isNaN(Number(value))) return "--";
  return `${Number(value).toLocaleString("fr-CA", { maximumFractionDigits: 1 })} %`;
}

export function formatBytes(value) {
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

export function normalizeEventSearch(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("fr-CA");
}
