import { dialog, ipcMain } from "electron";
import type { BackendRunner } from "./backend";
import type { ApplyEffectOptions, CommandResult } from "../shared/types";
import { normalizeHexColor, requireNonEmpty, splitSpecs } from "../shared/validation";

function parseJSON<T>(result: CommandResult): T {
  if (result.status !== "ok") {
    throw new Error(result.stderr || result.stdout || "GMK67 command failed.");
  }
  return JSON.parse(result.stdout) as T;
}

function numericOption(name: string, value: number | undefined): string[] {
  return typeof value === "number" ? [`--${name}=${value}`] : [];
}

export function registerIPC(runner: BackendRunner): void {
  ipcMain.handle("gmk67:command", async (_event, payload: { args: string[] }) => runner.run(payload.args));

  ipcMain.handle("gmk67:json", async (_event, payload: { args: string[] }) => parseJSON(await runner.run(payload.args)));

  ipcMain.handle("gmk67:device:readiness", async (_event, payload: { openCheck?: boolean }) => {
    const args = ["readiness", "--json"];
    if (payload.openCheck ?? true) {
      args.push("--open-check");
    }
    return parseJSON(await runner.run(args));
  });

  ipcMain.handle("gmk67:rgb:set-key", async (_event, payload: { key: string; color: string }) => {
    return runner.run(["rgb-set-key", requireNonEmpty(payload.key, "Key"), normalizeHexColor(payload.color)]);
  });

  ipcMain.handle("gmk67:rgb:set-all", async (_event, payload: { color: string }) => {
    return runner.run(["rgb-set-all", normalizeHexColor(payload.color)]);
  });

  ipcMain.handle("gmk67:rgb:apply-effect", async (_event, payload: ApplyEffectOptions) => {
    const args = [
      "effect-apply",
      requireNonEmpty(payload.effect, "Effect"),
      ...(payload.color ? [normalizeHexColor(payload.color)] : []),
      ...numericOption("write-index", payload.writeIndex),
      ...numericOption("colortype", payload.colorType),
      ...numericOption("byte5", payload.byte5),
      ...numericOption("byte6", payload.byte6),
      ...numericOption("byte7", payload.byte7),
    ];
    return runner.run(args);
  });

  ipcMain.handle("gmk67:profiles:create", async (_event, payload: { slot?: string; name: string; rgbPreset: string; keymapPreset?: string | null; rgbFill?: string; rgbAssignments?: string[]; keymapRemaps?: string[] }) => {
    const args = [
      "profile-library-create",
      ...(payload.slot ? [`--slot=${payload.slot}`] : []),
      `--name=${requireNonEmpty(payload.name, "Name")}`,
      `--rgb=${requireNonEmpty(payload.rgbPreset, "RGB preset")}`,
      `--keymap=${payload.keymapPreset || "none"}`,
      ...(payload.rgbFill ? [`--rgb-fill=${normalizeHexColor(payload.rgbFill)}`] : []),
      ...(payload.keymapRemaps ?? []).map((remap) => `--remap=${remap}`),
      ...(payload.rgbAssignments ?? []),
    ];
    return runner.run(args);
  });

  ipcMain.handle("gmk67:keymap:create", async (_event, payload: { slot?: string; name: string; remaps: string[] }) => {
    return runner.run([
      "keymap-library-create",
      ...(payload.slot ? [`--slot=${payload.slot}`] : []),
      `--name=${requireNonEmpty(payload.name, "Name")}`,
      ...payload.remaps.flatMap(splitSpecs),
    ]);
  });

  ipcMain.handle("gmk67:macros:create", async (_event, payload: { slot?: string; name: string; repeatCount: number; events: string[] }) => {
    return runner.run([
      "macro-library-create",
      ...(payload.slot ? [`--slot=${payload.slot}`] : []),
      `--name=${requireNonEmpty(payload.name, "Name")}`,
      `--repeat=${payload.repeatCount}`,
      ...payload.events.flatMap(splitSpecs),
    ]);
  });

  ipcMain.handle("gmk67:files:open", async (_event, payload?: { filters?: Electron.FileFilter[] }) => {
    const result = await dialog.showOpenDialog({
      properties: ["openFile"],
      filters: payload?.filters,
    });
    return { canceled: result.canceled, path: result.filePaths[0] ?? null };
  });

  ipcMain.handle("gmk67:files:save", async (_event, payload?: { defaultPath?: string; filters?: Electron.FileFilter[] }) => {
    const result = await dialog.showSaveDialog({
      defaultPath: payload?.defaultPath,
      filters: payload?.filters,
    });
    return { canceled: result.canceled, path: result.filePath ?? null };
  });

  ipcMain.handle("gmk67:developer:run", async (_event, payload: { args: string[] }) => {
    if (process.env.NODE_ENV === "production") {
      throw new Error("Raw developer commands are disabled in packaged builds.");
    }
    return runner.run(payload.args);
  });
}
