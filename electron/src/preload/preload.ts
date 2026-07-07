import { contextBridge, ipcRenderer } from "electron";
import type { ApplyEffectOptions, CommandLogEntry, GMK67API } from "../shared/types";

const invoke = <T>(channel: string, payload?: unknown): Promise<T> => ipcRenderer.invoke(channel, payload) as Promise<T>;

const api: GMK67API = {
  device: {
    readiness: (openCheck = true) => invoke("gmk67:device:readiness", { openCheck }),
    doctor: (openCheck = false) => invoke("gmk67:command", { args: openCheck ? ["doctor", "--open-check"] : ["doctor"] }),
    diagnostics: (outputPath) => invoke("gmk67:command", { args: outputPath ? ["diagnostics", outputPath] : ["diagnostics"] }),
    supportBundle: (directoryPath) => invoke("gmk67:command", { args: directoryPath ? ["support-bundle", directoryPath] : ["support-bundle"] }),
    permissionStatus: () => invoke("gmk67:command", { args: ["permission-status"] }),
    permissionRequest: () => invoke("gmk67:command", { args: ["permission-request"] }),
  },
  rgb: {
    effectList: () => invoke("gmk67:command", { args: ["effect-list"] }),
    applyEffect: (options: ApplyEffectOptions) => invoke("gmk67:rgb:apply-effect", options),
    presetList: () => invoke("gmk67:command", { args: ["rgb-preset-list"] }),
    layoutList: () => invoke("gmk67:command", { args: ["rgb-layout-list"] }),
    themeList: () => invoke("gmk67:command", { args: ["rgb-theme-list"] }),
    presetShow: (name) => invoke("gmk67:json", { args: ["rgb-preset-show", name, "--json"] }),
    themeShow: (layout, theme) => invoke("gmk67:json", { args: ["rgb-theme-show", layout, theme, "--json"] }),
    applyPreset: (name) => invoke("gmk67:command", { args: ["rgb-preset-apply", name] }),
    applyTheme: (layout, theme) => invoke("gmk67:command", { args: ["rgb-theme-apply", layout, theme] }),
    setAll: (color) => invoke("gmk67:rgb:set-all", { color }),
    clear: () => invoke("gmk67:command", { args: ["rgb-clear"] }),
    map: (specs) => invoke("gmk67:command", { args: ["rgb-map", ...specs] }),
    dump: () => invoke("gmk67:json", { args: ["rgb-dump", "--json"] }),
  },
  keymap: {
    presetList: () => invoke("gmk67:command", { args: ["keymap-preset-list"] }),
    presetShow: (name) => invoke("gmk67:json", { args: ["keymap-preset-show", name, "--json"] }),
    list: () => invoke("gmk67:json", { args: ["keymap-library-list", "--json"] }),
    show: (slot) => invoke("gmk67:json", { args: ["keymap-library-show", slot, "--json"] }),
    create: (options) => invoke("gmk67:keymap:create", options),
    apply: (slot, unsafeKeymapWrites = false) => invoke("gmk67:command", { args: ["keymap-library-apply", slot, ...(unsafeKeymapWrites ? ["--unsafe-keymap-write"] : [])] }),
    delete: (slot) => invoke("gmk67:command", { args: ["keymap-library-delete", slot] }),
  },
  files: {
    openFile: (filters) => invoke("gmk67:files:open", { filters }),
    saveFile: (defaultPath, filters) => invoke("gmk67:files:save", { defaultPath, filters }),
  },
  logs: {
    onCommandOutput: (callback) => {
      const listener = (_event: Electron.IpcRendererEvent, entry: CommandLogEntry) => callback(entry);
      ipcRenderer.on("gmk67:log", listener);
      return () => ipcRenderer.removeListener("gmk67:log", listener);
    },
  },
  developer: {
    run: (args) => invoke("gmk67:developer:run", { args }),
  },
};

contextBridge.exposeInMainWorld("gmk67", api);
