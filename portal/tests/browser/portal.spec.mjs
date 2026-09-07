import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const pageErrors = new WeakMap();
test.beforeEach(async ({ page }) => {
  const errors = [];
  pageErrors.set(page, errors);
  page.on("pageerror", (error) => errors.push(error.message));
});
test.afterEach(async ({ page }) => { expect(pageErrors.get(page)).toEqual([]); });

async function accessible(page) {
  const result = await new AxeBuilder({ page }).analyze();
  expect(result.violations.map(({ id, nodes }) => ({ id, nodes: nodes.map(({ target, failureSummary }) => ({ target, failureSummary })) }))).toEqual([]);
}
async function noOverflow(page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1);
}
async function loaded(page, path = "/") {
  await page.goto(path);
  await page.waitForLoadState("networkidle");
}

test("accueil rempli, palette et navigation", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await loaded(page);
  await expect(page.locator(".adventurer-card")).toHaveCount(8);
  await page.keyboard.press("Control+K");
  await expect(page.locator(".command-palette input")).toBeFocused();
  await page.keyboard.press("Escape");
  await accessible(page);
  await noOverflow(page);
  expect(errors).toEqual([]);
});

test("fiche, progression, onglets et focus après actualisation", async ({ page }) => {
  await page.clock.install();
  await loaded(page);
  const opener = page.locator('.adventurer-card__open').first();
  const original = await opener.elementHandle();
  await opener.click();
  await expect(page.locator("#expedition-dialog")).toBeVisible();
  await page.getByRole("tab", { name: "Mes Pals" }).click();
  await expect(page.getByRole("progressbar")).toHaveCount(24);
  await expect(page.getByRole("progressbar").first()).toHaveAttribute("aria-valuenow", /\d+/);
  await expect(page.locator('[role="tab"][tabindex="0"]')).toHaveCount(1);
  await accessible(page);
  if (page.viewportSize().width === 390) {
    expect((await page.locator(".pal-detail-card").first().boundingBox()).y).toBeLessThan(620);
  }
  await page.getByRole("tab", { name: "Mes Pals" }).press("ArrowRight");
  await expect(page.getByRole("tab", { name: "Mon inventaire" })).toBeFocused();
  await expect(page.getByRole("tabpanel", { name: "Mon inventaire" })).toBeVisible();
  await page.keyboard.press("Home");
  await expect(page.getByRole("tab", { name: "Profil", exact: false })).toBeFocused();
  await page.clock.fastForward(65_000);
  await expect.poll(() => original.evaluate((node) => node.isConnected)).toBe(false);
  await page.getByRole("button", { name: "Fermer la fiche", exact: true }).click();
  await expect(opener).toBeFocused();
});

test("carte : noms accessibles et contraste des joueurs", async ({ page }) => {
  await loaded(page, "/carte");
  for (const name of ["Joueurs", "Bases", "Légende"]) await expect(page.getByRole("button", { name, exact: true })).toBeVisible();
  await expect(page.locator(".global-player-legend-row")).toHaveCount(8);
  await accessible(page);
  await noOverflow(page);
});

test("résumé : filtre clavier et journée vide compacte", async ({ page }) => {
  await loaded(page, "/resume?jour=2026-09-05");
  const filter = page.getByRole("button", { name: "Objets fabriqués", exact: true });
  await filter.focus();
  await page.keyboard.press("Enter");
  await expect(filter).toBeFocused();
  await expect(filter).toHaveAttribute("aria-pressed", "true");
  await page.keyboard.press("Space");
  await expect(filter).toHaveAttribute("aria-pressed", "false");
  await accessible(page);
  await page.locator("#daily-date").fill("2026-09-04");
  await page.locator("#daily-date").press("Tab");
  await expect(page.locator("#daily-metrics")).toContainText("Aucune activité publiée");
  await expect(page.locator("#daily-types")).toBeHidden();
  await expect(page.locator(".daily-overview")).toBeHidden();
  await noOverflow(page);
});

test("classements à 320 px et détails des sources", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 844 });
  await loaded(page, "/classements");
  await expect(page.locator("#leaderboard-body tr")).toHaveCount(8);
  await noOverflow(page);
  await page.locator(".source-freshness summary").click();
  await noOverflow(page);
  await accessible(page);
});

test("terminal rempli et pagination réelle", async ({ page }) => {
  await loaded(page, "/terminal");
  await expect(page.locator('.site-nav a[aria-current="page"]')).toHaveText("Terminal");
  const next = page.locator("#event-pagination").getByRole("button", { name: "Page suivante" });
  await expect(next).toBeEnabled();
  await next.click();
  await expect(page.locator("#event-pagination input")).toHaveValue("2");
  await accessible(page);
  await noOverflow(page);
});

test("informations et archive figée", async ({ page }) => {
  await loaded(page, "/informations");
  await accessible(page);
  await loaded(page, "/saisons/saison-2026/");
  await expect(page.locator(".season-archive-banner")).toContainText("archives figées");
  await expect(page.locator("#next-update")).toHaveText("Archive figée");
  await expect(page.locator("#header-players")).toBeHidden();
  await accessible(page);
});

test("exploitation : champs nommés et résultats annoncés", async ({ page }) => {
  await loaded(page, "/ops");
  for (const label of ["Titre de la saison", "Adresse de la saison", "Date de début", "Fréquence", "Message dans le jeu"]) await expect(page.getByLabel(label, { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Actualiser le statut" }).click();
  await expect(page.getByRole("status")).toHaveText("Aucun agent actif.");
  await accessible(page);
  await noOverflow(page);
});

test("un lien direct ouvre la bonne collection", async ({ page }) => {
  await loaded(page, "/#joueur/aurore/pals");
  await expect(page.locator("#expedition-dialog")).toBeVisible();
  await expect(page.getByRole("tab", { name: "Mes Pals" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("progressbar")).toHaveCount(24);
  await page.getByRole("button", { name: "Fermer la fiche", exact: true }).click();
  await expect(page.locator("#save-title")).toBeFocused();
});

test("rechargement hors ligne et page de secours sous CSP", async ({ page, context }) => {
  await loaded(page);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await page.waitForLoadState("networkidle");
  await expect.poll(() => page.evaluate(() => caches.keys().then(async (keys) => {
    for (const key of keys) if (await (await caches.open(key)).match("/data/public-save-index.json")) return true;
    return false;
  }))).toBe(true);
  await context.setOffline(true);
  await page.reload();
  await expect(page.locator(".adventurer-card")).toHaveCount(8);
  await page.goto("/page-jamais-consultee");
  await expect(page.getByRole("heading", { name: "Le réseau fait une pause." })).toBeVisible();
  await expect(page.locator("body")).toHaveCSS("display", "grid");
  await accessible(page);
  await context.setOffline(false);
});
