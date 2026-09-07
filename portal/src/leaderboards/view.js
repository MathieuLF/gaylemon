import { replaceContentPreservingFocus } from "../shared/focus.js";
import { escapeHtml, formatProgressPercent, formatCompactDuration, parseDate, normalizeEventSearch, playerInitials } from "../shared/format.js";
import { playerColor, playerColorInk } from "../shared/player-colors.js";

export function createLeaderboards({ leaderboardCategory, leaderboardSearch, leaderboardPresence, leaderboardBody, leaderboardHead, leaderboardPodium, leaderboardResultCount, getPlayerActivity, playerRoute, formatLastSeen, formatPing, getSnapshot, getSort }) {
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
    const sortColumn = rankingColumn(category, getSort().key) || definition.columns[0];
    const query = normalizeEventSearch(String(leaderboardSearch?.value || "").trim());
    const presence = leaderboardPresence?.value || "all";
    const players = (Array.isArray(getSnapshot()?.players) ? getSnapshot().players : [])
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
      const direction = getSort().direction === "asc" ? 1 : -1;
      return (firstValue - secondValue) * direction
        || String(first.name || "").localeCompare(String(second.name || ""), "fr-CA");
    });
    return { players, definition, sortColumn };
  }

  function renderLeaderboards() {
    if (!leaderboardBody || !leaderboardHead || !leaderboardPodium) return;
    const { players, definition, sortColumn } = getRankedPlayers();
    const sourcePlayers = (getSnapshot()?.players || []).filter((player) => !player.provisional);
    const podiumMetric = sortColumn;
    leaderboardResultCount.textContent = `${players.length} aventurier${players.length > 1 ? "s" : ""} sur ${sourcePlayers.length}`;

    replaceContentPreservingFocus(leaderboardHead, `
      <tr>
        <th scope="col" class="leaderboard-rank-head">Rang</th>
        <th scope="col">Aventurier</th>
        ${definition.columns.map((column) => `
          <th scope="col" class="${column.key === sortColumn.key ? "is-sorted" : ""}">
            <button type="button" data-leaderboard-sort="${column.key}" aria-pressed="${column.key === sortColumn.key}">
              ${escapeHtml(column.label)}
              <span aria-hidden="true">${column.key === sortColumn.key ? (getSort().direction === "desc" ? "↓" : "↑") : "↕"}</span>
            </button>
          </th>
        `).join("")}
        <th scope="col"><span class="visually-hidden">Ouvrir la fiche</span></th>
      </tr>`);

    leaderboardPodium.innerHTML = players.length
      ? players.slice(0, 3).map((player, index) => {
        const playerIndex = getSnapshot().players.indexOf(player);
        const activity = getPlayerActivity(player);
        return `
          <a class="leaderboard-podium-card leaderboard-podium-card--${index + 1}" href="${playerRoute(player)}" data-player-index="${playerIndex}" style="--player-color:${playerColor(player)};--player-ink:${playerColorInk(playerColor(player))}">
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
        const playerIndex = getSnapshot().players.indexOf(player);
        const activity = getPlayerActivity(player);
        return `
          <tr style="--player-color:${playerColor(player)};--player-ink:${playerColorInk(playerColor(player))}">
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

  return { renderLeaderboards, rankingColumn, leaderboardCategories };
}
