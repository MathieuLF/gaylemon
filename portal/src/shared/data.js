export function createJsonReader(getSeasonBasePath) {
  async function readJson(path, options = {}) {
    const normalized = path.startsWith("/") ? path : `/${path}`;
    const seasonal = normalized.startsWith("/data/") || normalized.startsWith("/api/public/") || normalized === "/public-events-channel.json";
    const source = getSeasonBasePath() && seasonal ? `${getSeasonBasePath()}${normalized}` : normalized;
    const response = await fetch(source, {
      cache: options.immutable ? "force-cache" : options.revalidate ? "no-cache" : "no-store",
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    if (!options.expectedSha256) return response.json();
    if (!window.crypto?.subtle) throw new Error("sha256-unavailable");
    const bytes = await response.arrayBuffer();
    const digest = await window.crypto.subtle.digest("SHA-256", bytes);
    const actual = [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
    const expected = String(options.expectedSha256).replace(/^sha256:/i, "").toLocaleLowerCase("en-CA");
    if (actual !== expected) throw new Error("sha256-mismatch");
    return JSON.parse(new TextDecoder("utf-8").decode(bytes));
  }
  return readJson;
}
