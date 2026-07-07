import { app, BrowserWindow } from "electron";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { CommandLogEntry, CommandResult } from "../shared/types";
import { sanitizeArgs } from "../shared/validation";

const repoRoot = path.resolve(__dirname, "..", "..", "..");

function applicationSupportDirectory(): string {
  const directory = path.join(os.homedir(), "Library", "Application Support", "GMK67");
  fs.mkdirSync(directory, { recursive: true });
  return directory;
}

function packagedHelperPath(): string {
  if (process.platform === "darwin") {
    return path.join(process.resourcesPath, "..", "MacOS", "GMK67Helper");
  }
  return path.join(process.resourcesPath, "GMK67Helper");
}

function developmentHelperPath(): string {
  return path.join(repoRoot, ".build", "debug", "gmk67");
}

export function resolveHelperPath(): string | null {
  if (process.env.GMK67_HELPER_PATH && fs.existsSync(process.env.GMK67_HELPER_PATH)) {
    return process.env.GMK67_HELPER_PATH;
  }
  const packaged = packagedHelperPath();
  if (app.isPackaged && fs.existsSync(packaged)) {
    return packaged;
  }
  const development = developmentHelperPath();
  if (fs.existsSync(development)) {
    return development;
  }
  return null;
}

export function resolveResourcesDirectory(): string {
  if (process.env.GMK67_RESOURCES_DIR && fs.existsSync(process.env.GMK67_RESOURCES_DIR)) {
    return process.env.GMK67_RESOURCES_DIR;
  }
  const packaged = path.join(process.resourcesPath, "vendor");
  if (app.isPackaged && fs.existsSync(packaged)) {
    return process.resourcesPath;
  }
  return path.join(repoRoot, "Resources");
}

export class BackendRunner {
  private queue = Promise.resolve();

  constructor(private readonly windowProvider: () => BrowserWindow | null) {}

  run(args: string[]): Promise<CommandResult> {
    const task = this.queue.then(() => this.runNow(args));
    this.queue = task.then(
      () => undefined,
      () => undefined,
    );
    return task;
  }

  private async runNow(args: string[]): Promise<CommandResult> {
    const safeArgs = sanitizeArgs(args);
    const helper = resolveHelperPath();
    const startedAt = new Date().toISOString();
    const command = helper ? [helper, ...safeArgs] : ["gmk67", ...safeArgs];
    const id = crypto.randomUUID();
    this.emit({ id, stream: "command", message: `$ ${["gmk67", ...safeArgs].join(" ")}`, at: startedAt });

    if (process.platform !== "darwin" || !helper) {
      const finishedAt = new Date().toISOString();
      const message = process.platform !== "darwin"
        ? "GMK67 hardware backend is only available on macOS in this phase."
        : "GMK67 helper is not built. Run `swift build --product gmk67` from the repository root.";
      this.emit({ id, stream: "status", message, at: finishedAt });
      return {
        status: "backend-unavailable",
        exitCode: null,
        stdout: "",
        stderr: message,
        command,
        startedAt,
        finishedAt,
      };
    }

    return new Promise<CommandResult>((resolve) => {
      const child = spawn(helper, safeArgs, {
        cwd: applicationSupportDirectory(),
        env: {
          ...process.env,
          GMK67_RESOURCES_DIR: resolveResourcesDirectory(),
        },
        windowsHide: true,
      });
      let stdout = "";
      let stderr = "";

      child.stdout.on("data", (chunk: Buffer) => {
        const text = chunk.toString();
        stdout += text;
        this.emit({ id, stream: "stdout", message: text, at: new Date().toISOString() });
      });

      child.stderr.on("data", (chunk: Buffer) => {
        const text = chunk.toString();
        stderr += text;
        this.emit({ id, stream: "stderr", message: text, at: new Date().toISOString() });
      });

      child.on("error", (error) => {
        stderr += `${error.message}\n`;
      });

      child.on("close", (code) => {
        const finishedAt = new Date().toISOString();
        const exitCode = code ?? -1;
        const status = exitCode === 0 ? "ok" : "error";
        this.emit({ id, stream: "status", message: `Command exited with status ${exitCode}.`, at: finishedAt });
        resolve({
          status,
          exitCode,
          stdout,
          stderr,
          command,
          startedAt,
          finishedAt,
        });
      });
    });
  }

  private emit(entry: CommandLogEntry): void {
    this.windowProvider()?.webContents.send("gmk67:log", entry);
  }
}
