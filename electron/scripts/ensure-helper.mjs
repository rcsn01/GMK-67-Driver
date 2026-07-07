import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..", "..");
const helperPath = path.join(repoRoot, ".build", "debug", "gmk67");
const watchedPaths = [
  path.join(repoRoot, "Package.swift"),
  path.join(repoRoot, "Package.resolved"),
  path.join(repoRoot, "Sources", "GMK67Core"),
  path.join(repoRoot, "Sources", "GMK67Driver"),
];

function exists(filePath) {
  return fs.existsSync(filePath);
}

function latestMtimeMs(filePath) {
  if (!exists(filePath)) {
    return 0;
  }

  const stat = fs.statSync(filePath);
  if (!stat.isDirectory()) {
    return stat.mtimeMs;
  }

  let latest = stat.mtimeMs;
  for (const entry of fs.readdirSync(filePath, { withFileTypes: true })) {
    const entryPath = path.join(filePath, entry.name);
    if (entry.isDirectory()) {
      latest = Math.max(latest, latestMtimeMs(entryPath));
    } else if (entry.isFile()) {
      latest = Math.max(latest, fs.statSync(entryPath).mtimeMs);
    }
  }
  return latest;
}

function helperIsFresh() {
  if (!exists(helperPath)) {
    return false;
  }

  const helperMtime = fs.statSync(helperPath).mtimeMs;
  const latestSourceMtime = watchedPaths.reduce((latest, sourcePath) => {
    return Math.max(latest, latestMtimeMs(sourcePath));
  }, 0);

  return helperMtime >= latestSourceMtime;
}

if (process.env.GMK67_SKIP_HELPER_BUILD === "1") {
  console.log("Skipping helper build because GMK67_SKIP_HELPER_BUILD=1.");
  process.exit(0);
}

if (process.env.GMK67_HELPER_PATH && exists(process.env.GMK67_HELPER_PATH)) {
  console.log(`Using GMK67_HELPER_PATH: ${process.env.GMK67_HELPER_PATH}`);
  process.exit(0);
}

if (process.platform !== "darwin") {
  console.log("Skipping helper build: the Swift hardware backend is macOS-only in this phase.");
  process.exit(0);
}

if (helperIsFresh()) {
  console.log(`Using existing helper: ${helperPath}`);
  process.exit(0);
}

console.log("Building GMK67 helper...");
const build = spawnSync("swift", ["build", "--product", "gmk67"], {
  cwd: repoRoot,
  stdio: "inherit",
});

process.exit(build.status ?? 1);
