import { playerSlug } from "./format.js";

const playerColorCache = new Map();
const assignedPlayerHues = [];

export function hueDistance(first, second) {
  const distance = Math.abs(first - second) % 360;
  return Math.min(distance, 360 - distance);
}

export function playerColor(playerOrName) {
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

export function playerColorInk(color) {
  const [hue, saturation, lightness] = color.match(/[\d.]+/g).map(Number);
  const s = saturation / 100;
  const l = lightness / 100;
  const channel = (n) => {
    const k = (n + hue / 30) % 12;
    const value = l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1));
    return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
  };
  const luminance = .2126 * channel(0) + .7152 * channel(8) + .0722 * channel(4);
  return luminance > .179 ? "#000" : "#fff";
}
