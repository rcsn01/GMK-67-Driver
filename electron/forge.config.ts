import type { ForgeConfig } from "@electron-forge/shared-types";
import { MakerDMG } from "@electron-forge/maker-dmg";
import { MakerZIP } from "@electron-forge/maker-zip";
import { VitePlugin } from "@electron-forge/plugin-vite";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(__dirname, "..");
const helperPath = path.join(__dirname, "assets", "bin", "GMK67Helper");
const vendorPath = path.join(root, "Resources", "vendor");

function appBundlePath(buildPath: string): string {
  if (buildPath.endsWith(".app")) {
    return buildPath;
  }
  const directContents = path.join(buildPath, "Contents");
  if (fs.existsSync(directContents)) {
    return buildPath;
  }
  const appName = "GMK67.app";
  return path.join(buildPath, appName);
}

const copyHelperIntoBundle = (
  buildPath: string,
  _electronVersion: string,
  platform: string,
  _arch: string,
  callback: (error?: Error | null) => void,
) => {
  try {
    if (platform === "darwin" && fs.existsSync(helperPath)) {
      const macOSPath = path.join(appBundlePath(buildPath), "Contents", "MacOS");
      fs.mkdirSync(macOSPath, { recursive: true });
      const destination = path.join(macOSPath, "GMK67Helper");
      fs.copyFileSync(helperPath, destination);
      fs.chmodSync(destination, 0o755);
    }
    callback();
  } catch (error) {
    callback(error instanceof Error ? error : new Error(String(error)));
  }
};

const signCompletedBundle = (
  buildPath: string,
  _electronVersion: string,
  platform: string,
  _arch: string,
  callback: (error?: Error | null) => void,
) => {
  try {
    if (platform === "darwin") {
      const result = spawnSync("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appBundlePath(buildPath)], {
        encoding: "utf8",
      });
      if (result.status !== 0) {
        throw new Error(result.stderr || result.stdout || "codesign failed");
      }
    }
    callback();
  } catch (error) {
    callback(error instanceof Error ? error : new Error(String(error)));
  }
};

const config: ForgeConfig = {
  packagerConfig: {
    name: "GMK67",
    executableName: "GMK67",
    appBundleId: "dev.gmk67.driver",
    asar: true,
    extraResource: [vendorPath],
    afterCopyExtraResources: [copyHelperIntoBundle],
    afterComplete: [signCompletedBundle],
    osxSign: {},
  },
  rebuildConfig: {},
  makers: [
    new MakerDMG({}),
    new MakerZIP({}, ["darwin"]),
  ],
  plugins: [
    new VitePlugin({
      build: [
        {
          entry: "src/main/main.ts",
          config: "vite.main.config.ts",
          target: "main",
        },
        {
          entry: "src/preload/preload.ts",
          config: "vite.preload.config.ts",
          target: "preload",
        },
      ],
      renderer: [
        {
          name: "main_window",
          config: "vite.renderer.config.ts",
        },
      ],
    }),
  ],
};

export default config;
