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
