import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "portal/tests/browser",
  timeout: 30_000,
  fullyParallel: false,
  use: {
    baseURL: "http://127.0.0.1:4179",
    trace: "retain-on-failure",
    reducedMotion: "reduce",
  },
  projects: [
    { name: "mobile", use: { viewport: { width: 390, height: 844 } } },
    { name: "tablet", use: { viewport: { width: 768, height: 1024 } } },
    { name: "desktop", use: { viewport: { width: 1440, height: 1000 } } },
  ],
  webServer: {
    command: "node portal/tests/browser/serve.mjs",
    url: "http://127.0.0.1:4179/",
    reuseExistingServer: false,
  },
});
