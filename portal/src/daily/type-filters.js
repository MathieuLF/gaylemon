import { escapeHtml, formatInteger, playerInitials } from "../shared/format.js";

export function createDailyTypesRenderer({ dailyTopAggregates, dailyConsolidatedPalFinds, dailyPalSignalTotal, dailyAggregatePlayersLabel, dailyAggregateQuantityLabel, dailyAggregateShortKind, gameImage, getActiveFilter }) {
  function renderDailyTypes(summary) {
    const groups = [
      {
        title: "Objets fabriqués",
        empty: "Aucune fabrication détectée.",
        accent: "#a06ad7",
        total: summary.totals.craft,
        rows: dailyTopAggregates(summary.craftedItems, 10),
        filter: "craft",
        tooltip: "Clique pour revoir les fabrications qui ressortent dans la journée.",
      },
      {
        title: "Ressources produites",
        empty: "Aucune production détectée.",
        accent: "#ef7164",
        total: summary.totals.production,
        rows: dailyTopAggregates(summary.producedItems, 10),
        filter: "production",
        tooltip: "Clique pour revoir les productions qui ressortent dans la journée.",
      },
      {
        title: "Pals repérés",
        empty: "Des captures et collections sont comptées, mais aucun Pal ne ressort encore par nom.",
        accent: "#40c875",
        total: dailyPalSignalTotal(summary),
        rows: dailyTopAggregates(dailyConsolidatedPalFinds(summary), 10),
        filter: "pal",
        tooltip: "Clique pour revoir les captures et ajouts de Pals qui ressortent.",
      },
    ];
    return groups.map((group) => {
      const active = getActiveFilter() === group.filter;
      return `
      <article class="daily-tangible-card${active ? " is-active" : ""}" style="--tangible-color:${escapeHtml(group.accent)}" >
        <header>
          <button type="button" data-daily-type-filter="${escapeHtml(group.filter)}" aria-controls="daily-highlights" aria-pressed="${active}" data-tooltip="${escapeHtml(group.tooltip)}">${escapeHtml(group.title)}</button>
          <strong>${formatInteger(group.total)}</strong>
        </header>
        <ol class="daily-item-list">
          ${group.rows.length ? group.rows.map((row) => `
            <li data-tooltip="${escapeHtml(`${row.name}: ${dailyAggregateQuantityLabel(row)} · ${dailyAggregatePlayersLabel(row, 3)}`)}">
              ${row.icon ? gameImage(row.icon, "", "daily-item-icon") : `<span class="daily-item-icon daily-item-icon--empty">${escapeHtml(playerInitials(row.name))}</span>`}
              <span><b>${escapeHtml(row.name)}</b><small>${escapeHtml(`${dailyAggregateShortKind(row)} · ${dailyAggregatePlayersLabel(row, 2)}`)}</small></span>
              <strong>${formatInteger(row.quantity)}</strong>
            </li>`).join("") : `<li class="daily-item-list__empty">${escapeHtml(group.empty)}</li>`}
        </ol>
      </article>`;
    }).join("");
  }
  return renderDailyTypes;
}
