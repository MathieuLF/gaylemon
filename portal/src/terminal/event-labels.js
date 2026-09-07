export function publicEventOrderRank(event) {
  const source = String(event?.source || "");
  const type = String(event?.type || "");
  if (["journal", "players"].includes(source) && type === "leave") return 0;
  if (["journal", "players"].includes(source) && ["join", "reconnect"].includes(type)) return 2;
  return 1;
}

export function eventAggregationWindowMinutes(event) {
  const minutes = Number(event?.details?.windowMinutes || 0);
  return Number.isFinite(minutes) && minutes > 0 ? Math.round(minutes) : 0;
}

export function eventAggregationWindowLabel(event) {
  const minutes = eventAggregationWindowMinutes(event);
  if (!minutes) return "";
  return minutes === 1 ? "1 min" : `${minutes} min`;
}

export function eventAggregationHeadline(event, fallbackHeadline) {
  const minutes = eventAggregationWindowMinutes(event);
  if (!minutes) return fallbackHeadline;
  const labels = {
    activity: "Activité relevée",
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
