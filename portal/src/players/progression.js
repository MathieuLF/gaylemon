export function catalogExperienceProgress(level, experience, table, pal = false) {
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

export function catalogFriendshipProgress(points, table) {
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
