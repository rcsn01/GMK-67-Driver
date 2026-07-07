export type CommandStatus = "ok" | "error" | "backend-unavailable";

export interface CommandResult {
  status: CommandStatus;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  command: string[];
  startedAt: string;
  finishedAt: string;
}

export interface ReadinessDevice {
  index: number;
  kind: "config" | "hid" | string;
  maxFeatureReportSize: number;
  maxInputReportSize: number;
  maxOutputReportSize: number;
  primaryUsagePage: string;
  primaryUsage: string;
  usagePage: string;
  usage: string;
}

export interface ReadinessReport {
  status: "ready" | "ready-open-check-skipped" | "partial" | "not-ready" | string;
  openCheck: boolean;
  resourcesOK: boolean;
  layoutKeyCount: number | null;
  mappedPhysicalRGBKeyCount: number | null;
  offlineEncodersOK: boolean;
  usbDeviceOK: boolean;
  configurationInterfaceOK: boolean;
  likelyConfigurationIndices: number[];
  inputMonitoringGranted: boolean;
  hidOpenPermission: "ok" | "failed" | "skipped" | "not-requested" | string;
  hidOpenIndex: number | null;
  devices: ReadinessDevice[];
  warnings: string[];
  failures: string[];
}

export interface RGBRecord {
  chunk: number;
  offset: number;
  index: number;
  key?: string | null;
  spec?: string | null;
  rgb: string;
}

export interface ProfileLibraryEntry {
  slot: string;
  name: string;
  rgbPreset: string;
  keymapPreset?: string | null;
  customRGB: number;
  customRemaps: number;
}

export interface CombinedProfile {
  format: string;
  version: number;
  name: string;
  rgbPreset: string;
  keymapPreset?: string | null;
  rgbFill?: string | null;
  rgbAssignments?: string[] | null;
  keymapRemaps?: string[] | null;
}

export interface KeymapLibraryEntry {
  slot: string;
  name: string;
  remapCount: number;
}

export interface KeymapProfile {
  format: string;
  version: number;
  name: string;
  remaps: string[];
}

export interface MacroLibraryEntry {
  slot: string;
  name: string;
  repeatCount: number;
  eventCount: number;
}

export interface MacroEvent {
  type: string;
  key?: string | null;
  usage?: string | null;
  text?: string | null;
  delayMS?: number | null;
}

export interface MacroProfile {
  format: string;
  version: number;
  name: string;
  repeatCount: number;
  events: MacroEvent[];
}

export interface RGBPreset {
  name: string;
  title: string;
  description: string;
  fill: string;
  assignments: string[];
}

export interface KeymapPreset {
  name: string;
  title: string;
  description: string;
  remaps: string[];
}

export interface FileDialogResult {
  canceled: boolean;
  path: string | null;
}

export interface ApplyEffectOptions {
  effect: string;
  color?: string;
  writeIndex?: number;
  colorType?: number;
  byte5?: number;
  byte6?: number;
  byte7?: number;
}

export interface GMK67API {
  device: {
    readiness(openCheck?: boolean): Promise<ReadinessReport>;
    doctor(openCheck?: boolean): Promise<CommandResult>;
    diagnostics(outputPath?: string): Promise<CommandResult>;
    permissionStatus(): Promise<CommandResult>;
    permissionRequest(): Promise<CommandResult>;
  };
  rgb: {
    effectList(): Promise<CommandResult>;
    applyEffect(options: ApplyEffectOptions): Promise<CommandResult>;
    presetList(): Promise<CommandResult>;
    layoutList(): Promise<CommandResult>;
    themeList(): Promise<CommandResult>;
    presetShow(name: string): Promise<RGBPreset>;
    themeShow(layout: string, theme: string): Promise<RGBPreset>;
    applyPreset(name: string): Promise<CommandResult>;
    applyTheme(layout: string, theme: string): Promise<CommandResult>;
    setKey(key: string, color: string): Promise<CommandResult>;
    setAll(color: string): Promise<CommandResult>;
    clear(): Promise<CommandResult>;
    map(specs: string[]): Promise<CommandResult>;
    dump(): Promise<RGBRecord[]>;
  };
  profiles: {
    presetList(): Promise<CommandResult>;
    presetShow(name: string, editable?: boolean): Promise<CombinedProfile>;
    list(): Promise<ProfileLibraryEntry[]>;
    show(slot: string): Promise<CombinedProfile>;
    create(options: { slot?: string; name: string; rgbPreset: string; keymapPreset?: string | null; rgbFill?: string; rgbAssignments?: string[]; keymapRemaps?: string[] }): Promise<CommandResult>;
    apply(slot: string, unsafeKeymapWrites?: boolean): Promise<CommandResult>;
    delete(slot: string): Promise<CommandResult>;
  };
  keymap: {
    presetList(): Promise<CommandResult>;
    presetShow(name: string): Promise<KeymapPreset>;
    list(): Promise<KeymapLibraryEntry[]>;
    show(slot: string): Promise<KeymapProfile>;
    create(options: { slot?: string; name: string; remaps: string[] }): Promise<CommandResult>;
    apply(slot: string, unsafeKeymapWrites?: boolean): Promise<CommandResult>;
    delete(slot: string): Promise<CommandResult>;
  };
  macros: {
    list(): Promise<MacroLibraryEntry[]>;
    show(slot: string): Promise<MacroProfile>;
    create(options: { slot?: string; name: string; repeatCount: number; events: string[] }): Promise<CommandResult>;
    delete(slot: string): Promise<CommandResult>;
  };
  files: {
    openFile(filters?: Electron.FileFilter[]): Promise<FileDialogResult>;
    saveFile(defaultPath?: string, filters?: Electron.FileFilter[]): Promise<FileDialogResult>;
  };
  logs: {
    onCommandOutput(callback: (entry: CommandLogEntry) => void): () => void;
  };
  developer: {
    run(args: string[]): Promise<CommandResult>;
  };
}

export interface CommandLogEntry {
  id: string;
  stream: "command" | "stdout" | "stderr" | "status";
  message: string;
  at: string;
}
