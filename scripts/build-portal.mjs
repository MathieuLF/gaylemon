import { build } from "esbuild";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const result = await build({
  absWorkingDir: root,
  entryPoints: ["portal/src/app.js", "portal/src/styles.css"],
  outdir: "portal/assets",
  bundle: true,
  format: "iife",
  target: "es2022",
  minify: true,
  charset: "utf8",
  legalComments: "none",
  external: ["/assets/*"],
  write: false,
});
for (const output of result.outputFiles) {
  if (process.argv.includes("--check")) {
    const existing = await readFile(output.path, "utf8");
    if (existing !== output.text) throw new Error("Actifs du portail périmés : lancer npm run build.");
  } else {
    await writeFile(output.path, output.contents);
  }
}
