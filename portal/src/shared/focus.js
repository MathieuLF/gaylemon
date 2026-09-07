const identityAttributes = ["id", "href", "data-player-slug", "data-player-index", "data-daily-type-filter", "data-leaderboard-sort"];

export function captureFocus(element = document.activeElement) {
  if (!(element instanceof HTMLElement) || element === document.body || element === document.documentElement) return null;
  const identity = identityAttributes.find((name) => element.hasAttribute(name));
  return { element, identity, value: identity ? element.getAttribute(identity) : null };
}

export function restoreFocus(token, root = document, fallback = null) {
  const replacement = token?.identity
    ? [...root.querySelectorAll(`[${token.identity}]`)].find((element) => element.getAttribute(token.identity) === token.value && element.getClientRects().length)
    : null;
  const target = token?.element?.isConnected && token.element.getClientRects().length ? token.element : replacement;
  (target || fallback)?.focus({ preventScroll: true });
}

export function replaceContentPreservingFocus(container, markup) {
  const token = container.contains(document.activeElement) ? captureFocus() : null;
  container.innerHTML = markup;
  if (token) restoreFocus(token, container);
}
