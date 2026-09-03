import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("palette, accessibilité et continuité réseau", async ({ page, context }) => {
  const consoleErrors = [];
  page.on("console", (message) => { if (message.type() === "error") consoleErrors.push(message.text()); });
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  await page.keyboard.press("Control+K");
  await expect(page.locator(".command-palette")).toBeVisible();
  await expect(page.locator(".command-palette input")).toBeFocused();
  await page.keyboard.press("Escape");
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations.map((violation) => ({ id: violation.id, targets: violation.nodes.map((node) => node.target.join(" ")) }))).toEqual([]);
  await context.setOffline(true);
  await context.setOffline(false);
  await expect(page.locator(".network-toast")).toContainText("Connexion rétablie");
  expect(consoleErrors).toEqual([]);
});

test("les fiches de l’accueil conservent leur bandeau et leurs repères", async ({ page }) => {
  const consoleErrors = [];
  page.on("console", (message) => { if (message.type() === "error") consoleErrors.push(message.text()); });
  await page.goto("/");
  await page.waitForLoadState("networkidle");
  await page.evaluate(() => {
    const renderCard = ({ name, initials, accent, team }) => `
      <article class="adventurer-card" style="--card-order:0;--card-accent:${accent}">
        <div class="adventurer-card__cover">
          <div class="adventurer-card__identity"><span class="adventurer-card__monogram">${initials}</span><div><p>Cocopois sauvage</p><h3>${name}</h3></div></div>
        </div>
        <div class="adventurer-card__team">
          <small>Équipe active</small>
          <div>${team.map((pal) => `<span>${pal} <b>Niv. 80</b></span>`).join("")}</div>
        </div>
        <div class="adventurer-card__quickfacts">
          <span class="adventurer-card__kpi adventurer-card__kpi--collection"><small>Collection</small><span><strong>884</strong><em>Pals</em></span></span>
          <span class="adventurer-card__kpi adventurer-card__kpi--team"><small>Équipe active</small><span><strong>5</strong><em>Pals</em></span></span>
          <span class="adventurer-card__kpi adventurer-card__kpi--bases"><small>Campements</small><span><strong>6</strong><em>bases</em></span></span>
        </div>
        <a class="adventurer-card__open" href="#joueur/${name.toLowerCase()}/profile">Explorer la fiche <span>→</span></a>
      </article>`;
    document.querySelector("#save-players").innerHTML = [
      { name: "Rick", initials: "RI", accent: "hsl(338 61% 44%)", team: ["Solenne"] },
      { name: "Alyross", initials: "AL", accent: "hsl(145 62% 40%)", team: ["Frostallion Noct", "Jetragon", "Menasting", "Elphidran", "Astegon"] },
      { name: "Brian", initials: "BR", accent: "hsl(270 48% 45%)", team: ["Prister Lux (Boss)", "Prister Lux", "Prister Lux (Boss)"] },
    ].map(renderCard).join("");
  });

  const visualState = await page.locator("#save-players .adventurer-card").evaluateAll((cards) => {
    const firstCard = cards[0];
    const cover = firstCard.querySelector(".adventurer-card__cover");
    const kpis = firstCard.querySelector(".adventurer-card__quickfacts");
    return {
      accent: getComputedStyle(firstCard).getPropertyValue("--card-accent").trim(),
      cover: getComputedStyle(cover).backgroundImage,
      columns: getComputedStyle(kpis).gridTemplateColumns.split(" ").length,
      cards: cards.map((card) => {
        const cardRect = card.getBoundingClientRect();
        const factsRect = card.querySelector(".adventurer-card__quickfacts").getBoundingClientRect();
        const buttonRect = card.querySelector(".adventurer-card__open").getBoundingClientRect();
        return {
          height: Math.round(cardRect.height),
          factsOffset: Math.round(factsRect.top - cardRect.top),
          buttonOffset: Math.round(buttonRect.top - cardRect.top),
        };
      }),
    };
  });
  expect(visualState.accent).toBe("hsl(338 61% 44%)");
  expect(visualState.cover).not.toBe("none");
  expect(visualState.columns).toBe(3);
  expect(new Set(visualState.cards.map(({ height }) => height)).size).toBe(1);
  expect(new Set(visualState.cards.map(({ factsOffset }) => factsOffset)).size).toBe(1);
  expect(new Set(visualState.cards.map(({ buttonOffset }) => buttonOffset)).size).toBe(1);
  expect(await page.locator(".adventurer-card__kpi").allTextContents()).toEqual(expect.arrayContaining([expect.stringContaining("Collection"), expect.stringContaining("Équipe active"), expect.stringContaining("Campements")]));
  expect(consoleErrors).toEqual([]);
});

test("la page Informations est une page secondaire lisible", async ({ page }) => {
  await page.goto("/informations");
  await expect(page).toHaveTitle("Informations | Gaylémon Palworld");
  await expect(page.locator(".site-nav a", { hasText: "Informations" })).toHaveCount(0);
  await expect(page.locator('.site-footer__meta-links a[aria-current="page"]')).toHaveText("Informations");
  await expect(page.locator(".information-changelog")).not.toHaveAttribute("open", "");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Un carnet vivant");

  await page.setViewportSize({ width: 390, height: 844 });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations.map((violation) => ({ id: violation.id, targets: violation.nodes.map((node) => node.target.join(" ")) }))).toEqual([]);
});

test("une archive désactive le direct et le sondage", async ({ page }) => {
  await page.goto("/saisons/saison-2026/");
  await expect(page.locator(".season-archive-banner")).toContainText("archives figées");
  await expect(page.locator("#next-update")).toHaveText("Archive figée");
  await expect(page.locator("#header-players")).toBeHidden();
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations.map((violation) => ({ id: violation.id, targets: violation.nodes.map((node) => node.target.join(" ")) }))).toEqual([]);
});

test("le terminal conserve le cadre commun autour de la console", async ({ page }) => {
  await page.goto("/terminal");
  await page.waitForLoadState("networkidle");

  await expect(page.locator(".site-nav")).toBeVisible();
  await expect(page.locator('.site-nav a[aria-current="page"]')).toHaveText("Terminal");

  await page.evaluate(() => {
    const pagination = document.querySelector("#event-pagination");
    if (!pagination.hidden) return;
    pagination.innerHTML = `
      <button class="event-pagination__step" type="button" aria-label="Page précédente" disabled><span aria-hidden="true">‹</span></button>
      <label class="event-pagination__position">
        <span class="event-pagination__label">Page</span>
        <input class="event-pagination__page-input" type="number" min="1" max="5102" value="1" aria-label="Numéro de page">
        <span class="event-pagination__total">sur 5 102</span>
      </label>
      <button class="event-pagination__step" type="button" aria-label="Page suivante"><span aria-hidden="true">›</span></button>`;
    pagination.hidden = false;
  });

  const shell = await page.evaluate(() => {
    const body = getComputedStyle(document.body);
    const consoleStyle = getComputedStyle(document.querySelector(".event-console"));
    const journalStyle = getComputedStyle(document.querySelector(".terminal-journal-panel"));
    const controlsStyle = getComputedStyle(document.querySelector(".event-controls"));
    const pagination = document.querySelector("#event-pagination");
    const returnRect = document.querySelector(".terminal-return").getBoundingClientRect();
    return {
      bodyColor: body.color,
      bodyBackground: body.backgroundColor,
      consoleBackground: consoleStyle.backgroundColor,
      consoleRadius: consoleStyle.borderRadius,
      journalRadius: journalStyle.borderRadius,
      controlsRadius: controlsStyle.borderRadius,
      paginationInHeading: Boolean(pagination.closest(".terminal-journal-heading")),
      paginationInConsole: Boolean(pagination.closest(".event-console")),
      paginationHeight: pagination.getBoundingClientRect().height,
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      returnHeight: returnRect.height,
    };
  });

  expect(shell.bodyColor).toBe("rgb(19, 38, 66)");
  expect(shell.bodyBackground).toBe("rgb(231, 247, 238)");
  expect(shell.consoleBackground).toBe("rgb(8, 21, 27)");
  expect(["18px", "22px"]).toContain(shell.consoleRadius);
  expect(shell.journalRadius).toBe("24px");
  expect(shell.controlsRadius).toBe("18px");
  expect(shell.paginationInHeading).toBe(true);
  expect(shell.paginationInConsole).toBe(false);
  expect(shell.paginationHeight).toBeGreaterThanOrEqual(44);
  expect(shell.overflow).toBeLessThanOrEqual(1);
  expect(shell.returnHeight).toBeGreaterThanOrEqual(44);

  await page.setViewportSize({ width: 390, height: 844 });
  const mobileShell = await page.evaluate(() => {
    document.querySelector("#event-pagination").hidden = false;
    const heroRect = document.querySelector(".terminal-page-heading").getBoundingClientRect();
    const returnRect = document.querySelector(".terminal-return").getBoundingClientRect();
    const returnTextRect = document.querySelector(".terminal-return span").getBoundingClientRect();
    const journalRect = document.querySelector(".terminal-journal-panel").getBoundingClientRect();
    const paginationRect = document.querySelector("#event-pagination").getBoundingClientRect();
    return {
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      paginationRatio: paginationRect.width / journalRect.width,
      returnRatio: returnRect.width / heroRect.width,
      returnTextWidth: returnTextRect.width,
    };
  });

  expect(mobileShell.overflow).toBeLessThanOrEqual(1);
  expect(mobileShell.paginationRatio).toBeGreaterThan(0.85);
  expect(mobileShell.returnRatio).toBeGreaterThan(0.85);
  expect(mobileShell.returnTextWidth).toBeGreaterThan(60);

  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations.map((violation) => ({ id: violation.id, targets: violation.nodes.map((node) => node.target.join(" ")) }))).toEqual([]);
});
