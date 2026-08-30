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
  await page.evaluate(() => {
    document.querySelector("#event-pagination").hidden = false;
  });

  const mobileShell = await page.evaluate(() => {
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
