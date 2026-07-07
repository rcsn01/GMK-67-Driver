import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const electronDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(electronDir, "..", "..");
const outputDir = path.join(repoRoot, "electron", "assets", "bin");
const helperSource = path.join(repoRoot, ".build", "debug", "gmk67");
const helperDestination = path.join(outputDir, "GMK67Helper");

const build = spawnSync("swift", ["build", "--product", "gmk67"], {
  cwd: repoRoot,
  stdio: "inherit",
});

if (build.status !== 0) {
  process.exit(build.status ?? 1);
}

fs.mkdirSync(outputDir, { recursive: true });
fs.copyFileSync(helperSource, helperDestination);
fs.chmodSync(helperDestination, 0o755);
console.log(`Prepared ${helperDestination}`);
