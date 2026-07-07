import { Bug, Cpu, Keyboard, Lightbulb, Play, Save, Search, SlidersHorizontal, Sparkles, Usb } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Console } from "./components/Console";
import { StatusBanner } from "./components/StatusBanner";
import { VisualKeyboard } from "./components/VisualKeyboard";
import type { CommandLogEntry, CommandResult, KeymapLibraryEntry, ReadinessReport, RGBRecord } from "../../shared/types";
import { normalizeHexColor, splitSpecs } from "../../shared/validation";

type Page = "rgb" | "keymap" | "device" | "developer";
type KeymapLayer = "top" | "fn";
type FnMode = "momentary" | "toggle";
type RGBTab = "static" | "effects";

const navItems: Array<{ page: Page; label: string; icon: typeof Lightbulb }> = [
  { page: "rgb", label: "RGB", icon: Lightbulb },
  { page: "keymap", label: "Keymap", icon: Keyboard },
  { page: "device", label: "Device", icon: Usb },
  { page: "developer", label: "Developer", icon: Bug },
];

function commandSummary(result: CommandResult): string {
  return result.status === "ok" ? result.stdout || "Command completed." : result.stderr || result.stdout || "Command failed.";
}

function recordColors(records: RGBRecord[]): Map<string, string> {
  const colors = new Map<string, string>();
  for (const record of records) {
    const key = (record.spec ?? record.key ?? "").toLowerCase();
    if (key && record.rgb !== "000000") {
      colors.set(key, record.rgb);
    }
  }
  return colors;
}

function normalizeKeySpec(value: string): string {
  return value.trim().toLowerCase();
}

function parseRemapText(value: string): Map<string, string> {
  const remaps = new Map<string, string>();
  for (const spec of splitSpecs(value)) {
    const [source, target] = spec.split("=", 2);
    if (source?.trim() && target?.trim()) {
      remaps.set(normalizeKeySpec(source), target.trim());
    }
  }
  return remaps;
}

function remapMapToText(remaps: Map<string, string>): string {
  return [...remaps.entries()]
    .map(([source, target]) => `${source}=${target}`)
    .join(" ");
}

function setRemapInText(value: string, source: string, target: string): string {
  const remaps = parseRemapText(value);
  const normalizedSource = normalizeKeySpec(source);
  const normalizedTarget = target.trim();
  if (normalizedTarget && normalizedTarget !== source) {
    remaps.set(normalizedSource, normalizedTarget);
  } else {
    remaps.delete(normalizedSource);
  }
  return remapMapToText(remaps);
}

function mappingLabel(target: string): string {
  return target.replace(":control", "+ctrl").replace(":shift", "+shift").replace(":alt", "+alt").replace(":win", "+cmd").toUpperCase();
}

export function App(): JSX.Element {
  const [page, setPage] = useState<Page>("rgb");
  const [readiness, setReadiness] = useState<ReadinessReport | null>(null);
  const [loadingStatus, setLoadingStatus] = useState(false);
  const [logs, setLogs] = useState<CommandLogEntry[]>([]);
  const [selectedKey, setSelectedKey] = useState("W");
  const [fillColor, setFillColor] = useState("000000");
  const [mapSpecs, setMapSpecs] = useState("W=FF0000 A=00FF00 S=0000FF D=00FFFF");
  const [effectName, setEffectName] = useState("breath");
  const [effectColor, setEffectColor] = useState("FFFFFF");
  const [presetName, setPresetName] = useState("wasd");
  const [themeLayout, setThemeLayout] = useState("wasd");
  const [themeName, setThemeName] = useState("rainbow");
  const [keyboardColors, setKeyboardColors] = useState<Map<string, string>>(new Map());
  const [keymaps, setKeymaps] = useState<KeymapLibraryEntry[]>([]);
  const [keymapForm, setKeymapForm] = useState({ slot: "wasd", name: "WASD Arrows", remaps: "W=up A=left S=down D=right" });
  const [developerCommand, setDeveloperCommand] = useState("doctor");
  const [lastMessage, setLastMessage] = useState("");
  const [unsafeKeymapWrites, setUnsafeKeymapWrites] = useState(false);
  const [consoleExpanded, setConsoleExpanded] = useState(false);
  const [selectedKeymapSlot, setSelectedKeymapSlot] = useState("");
  const [keymapLayer, setKeymapLayer] = useState<KeymapLayer>("top");
  const [fnMode, setFnMode] = useState<FnMode>("momentary");
  const [rgbTab, setRGBTab] = useState<RGBTab>("static");
  const [targetKey, setTargetKey] = useState("up");
  const [fnLayerRemaps, setFnLayerRemaps] = useState("1=f1 2=f2 3=f3 4=f4 5=f5 6=f6 7=f7 8=f8 9=f9 0=f10 -=f11 equal=f12");

  useEffect(() => {
    return window.gmk67.logs.onCommandOutput((entry) => {
      setLogs((current) => [...current.slice(-499), entry]);
    });
  }, []);

  useEffect(() => {
    void refreshStatus();
    void refreshLibraries();
  }, []);

  const canWrite = readiness?.status === "ready";

  useEffect(() => {
    if (page === "rgb" && canWrite) {
      void syncRGBDump();
    }
  }, [page, canWrite]);

  async function run(action: () => Promise<CommandResult>): Promise<void> {
    try {
      const result = await action();
      setLastMessage(commandSummary(result));
    } catch (error) {
      setLastMessage(error instanceof Error ? error.message : String(error));
    }
  }

  async function refreshStatus(): Promise<void> {
    setLoadingStatus(true);
    try {
      setReadiness(await window.gmk67.device.readiness(true));
    } catch (error) {
      setLastMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setLoadingStatus(false);
    }
  }

  async function refreshLibraries(): Promise<void> {
    await Promise.allSettled([
      window.gmk67.keymap.list().then(setKeymaps),
    ]);
  }

  async function syncRGBDump(): Promise<void> {
    try {
      const records = await window.gmk67.rgb.dump();
      setKeyboardColors(recordColors(records));
    } catch (error) {
      setLastMessage(error instanceof Error ? error.message : String(error));
    }
  }

  async function loadKeymapProfile(slot: string): Promise<void> {
    if (!slot) {
      return;
    }
    try {
      const profile = await window.gmk67.keymap.show(slot);
      setSelectedKeymapSlot(slot);
      setKeymapForm({ slot, name: profile.name, remaps: profile.remaps.join(" ") });
      setKeymapLayer("top");
      setLastMessage(`Loaded keymap profile ${profile.name}.`);
    } catch (error) {
      setLastMessage(error instanceof Error ? error.message : String(error));
    }
  }

  const activeKeymapRemaps = keymapLayer === "top" ? keymapForm.remaps : fnLayerRemaps;
  const activeKeymapMap = parseRemapText(activeKeymapRemaps);
  const keymapKeyboardMappings = new Map([...activeKeymapMap.entries()].map(([source, target]) => [source, mappingLabel(target)]));

  const keyboardDock = (
    <div className="keyboardDock">
      <VisualKeyboard
        colorsByKey={page === "rgb" ? keyboardColors : new Map()}
        selectedKey={page === "keymap" ? selectedKey : undefined}
        sourceKey={page === "keymap" && keymapLayer === "fn" ? "fn" : null}
        mappingsByKey={page === "keymap" ? keymapKeyboardMappings : undefined}
        onSelect={page === "keymap"
          ? (key) => {
              setSelectedKey(key);
              setTargetKey(activeKeymapMap.get(normalizeKeySpec(key)) ?? key);
            }
          : undefined}
      />
    </div>
  );

  const renderedPage = useMemo(() => {
    switch (page) {
      case "rgb":
        return (
          <section className="workArea">
            <div className="panel">
              <div className="tabBar" aria-label="RGB controls">
                <button className={rgbTab === "static" ? "active" : ""} onClick={() => setRGBTab("static")}>
                  <Sparkles size={16} />
                  Static layouts
                </button>
                <button className={rgbTab === "effects" ? "active" : ""} onClick={() => setRGBTab("effects")}>
                  <SlidersHorizontal size={16} />
                  Built-in effects
                </button>
              </div>
              {rgbTab === "static" ? (
                <>
                  <div className="panelHeader">
                    <div>
                      <h2>Static Layouts</h2>
                      <p>Built-in presets and custom maps</p>
                    </div>
                    <Sparkles size={18} />
                  </div>
                  <div className="formGrid two">
                    <label>
                      Fill
                      <input value={fillColor} onChange={(event) => setFillColor(event.target.value.toUpperCase())} />
                    </label>
                    <button disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.setAll(normalizeHexColor(fillColor)))}>Set all</button>
                    <button disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.clear())}>Clear</button>
                    <label>
                      Preset
                      <input value={presetName} onChange={(event) => setPresetName(event.target.value)} />
                    </label>
                    <button disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.applyPreset(presetName))}>Apply preset</button>
                    <label>
                      Layout
                      <input value={themeLayout} onChange={(event) => setThemeLayout(event.target.value)} />
                    </label>
                    <label>
                      Theme
                      <input value={themeName} onChange={(event) => setThemeName(event.target.value)} />
                    </label>
                    <button disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.applyTheme(themeLayout, themeName))}>Apply theme</button>
                  </div>
                  <label className="stacked">
                    RGB map
                    <textarea value={mapSpecs} onChange={(event) => setMapSpecs(event.target.value)} />
                  </label>
                  <button disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.map(splitSpecs(mapSpecs)))}>Apply map</button>
                </>
              ) : (
                <>
                  <div className="panelHeader">
                    <div>
                      <h2>Built-in Effects</h2>
                      <p>Native animated modes</p>
                    </div>
                    <SlidersHorizontal size={18} />
                  </div>
                  <div className="formGrid">
                    <label>
                      Effect
                      <input value={effectName} onChange={(event) => setEffectName(event.target.value)} />
                    </label>
                    <label>
                      Color
                      <input value={effectColor} onChange={(event) => setEffectColor(event.target.value.toUpperCase())} />
                    </label>
                    <button disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.applyEffect({ effect: effectName, color: normalizeHexColor(effectColor) }))}>
                      <Play size={16} />
                      Apply effect
                    </button>
                  </div>
                  <button onClick={() => run(() => window.gmk67.rgb.effectList())}>List effects</button>
                </>
              )}
            </div>
          </section>
        );
      case "keymap":
        {
          const currentTarget = activeKeymapMap.get(normalizeKeySpec(selectedKey)) ?? "";
          const updateActiveRemaps = (nextRemaps: string) => {
            if (keymapLayer === "top") {
              setKeymapForm({ ...keymapForm, remaps: nextRemaps });
            } else {
              setFnLayerRemaps(nextRemaps);
            }
          };
          const assignSelectedKey = () => {
            const nextTarget = targetKey.trim();
            if (!nextTarget) {
              return;
            }
            updateActiveRemaps(setRemapInText(activeKeymapRemaps, selectedKey, nextTarget));
          };
          const clearSelectedKey = () => {
            updateActiveRemaps(setRemapInText(activeKeymapRemaps, selectedKey, ""));
          };
          return (
            <section className="workArea keymapWorkspace">
              <div className="panel">
                <div className="panelHeader">
                  <div>
                    <h2>Keymap Profile</h2>
                    <p>{keymaps.length} saved profile(s)</p>
                  </div>
                  <button className="iconButton" onClick={refreshLibraries} title="Refresh keymap profiles">
                    <Search size={16} />
                  </button>
                </div>
                <div className="profileControls">
                  <label>
                    Saved profile
                    <select
                      value={selectedKeymapSlot}
                      onChange={(event) => {
                        void loadKeymapProfile(event.target.value);
                      }}
                    >
                      <option value="">Select profile</option>
                      {keymaps.map((entry) => (
                        <option key={entry.slot} value={entry.slot}>
                          {entry.name} ({entry.slot})
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Slot
                    <input value={keymapForm.slot} onChange={(event) => setKeymapForm({ ...keymapForm, slot: event.target.value })} />
                  </label>
                  <label>
                    Name
                    <input value={keymapForm.name} onChange={(event) => setKeymapForm({ ...keymapForm, name: event.target.value })} />
                  </label>
                </div>
              </div>

              <div className="panel">
                <div className="keymapToolbar">
                  <div className="segmentedControl" aria-label="Keymap layer">
                    <button className={keymapLayer === "top" ? "active" : ""} onClick={() => setKeymapLayer("top")}>Top layer</button>
                    <button className={keymapLayer === "fn" ? "active" : ""} onClick={() => setKeymapLayer("fn")}>Fn layer</button>
                  </div>
                  <div className="segmentedControl" aria-label="Fn behavior">
                    <button className={fnMode === "momentary" ? "active" : ""} onClick={() => setFnMode("momentary")}>Hold</button>
                    <button className={fnMode === "toggle" ? "active" : ""} onClick={() => setFnMode("toggle")}>Toggle</button>
                  </div>
                </div>
                <div className="keymapNotice">
                  {fnMode === "momentary"
                    ? "Fn behavior: hold Fn while pressing another key."
                    : "Fn behavior: press Fn once, then press another key without holding Fn."}
                  {keymapLayer === "fn" && " Fn-layer mappings are modeled in the editor; backend support for writing a second layer is still pending."}
                </div>
                <div className="keymapEditGrid">
                  <div className="mappingCard">
                    <span>Selected key</span>
                    <strong>{selectedKey}</strong>
                    <p>{currentTarget ? `Currently sends ${mappingLabel(currentTarget)}` : "Uses its normal output."}</p>
                  </div>
                  <label>
                    Send when pressed
                    <input value={targetKey} onChange={(event) => setTargetKey(event.target.value)} placeholder="up, f1, C:control" />
                  </label>
                  <button className="primaryButton" onClick={assignSelectedKey}>
                    <Save size={16} />
                    Assign
                  </button>
                  <button onClick={clearSelectedKey}>Clear key</button>
                </div>
                <label className="stacked">
                  {keymapLayer === "top" ? "Top layer remaps" : "Fn layer remaps"}
                  <textarea value={activeKeymapRemaps} onChange={(event) => updateActiveRemaps(event.target.value)} />
                </label>
              </div>

              <div className="panel">
                <div className="panelHeader">
                  <div>
                    <h2>Save and Apply</h2>
                    <p>Writes use the current proven top-layer keymap path.</p>
                  </div>
                </div>
                <div className="actionRow">
                  <button onClick={() => run(async () => {
                    const result = await window.gmk67.keymap.create({ slot: keymapForm.slot, name: keymapForm.name, remaps: splitSpecs(keymapForm.remaps) });
                    await refreshLibraries();
                    setSelectedKeymapSlot(keymapForm.slot);
                    return result;
                  })}>Save top layer profile</button>
                  <button disabled={!unsafeKeymapWrites || !canWrite} onClick={() => run(() => window.gmk67.keymap.apply(keymapForm.slot, unsafeKeymapWrites))}>Apply saved profile</button>
                  <button onClick={() => run(async () => {
                    const result = await window.gmk67.keymap.delete(keymapForm.slot);
                    await refreshLibraries();
                    return result;
                  })}>Delete profile</button>
                </div>
              </div>
            </section>
          );
        }
      case "device":
        return (
          <section className="workArea">
            <div className="panel">
              <div className="panelHeader">
                <div>
                  <h2>Device</h2>
                  <p>{readiness?.status ?? "not checked"}</p>
                </div>
                <Cpu size={18} />
              </div>
              <div className="deviceGrid">
                <Metric label="Resources" value={readiness?.resourcesOK ? "OK" : "Check"} />
                <Metric label="Encoders" value={readiness?.offlineEncodersOK ? "OK" : "Check"} />
                <Metric label="Input Monitoring" value={readiness?.inputMonitoringGranted ? "Granted" : "Not granted"} />
                <Metric label="HID open" value={readiness?.hidOpenPermission ?? "-"} />
              </div>
              <button onClick={() => run(() => window.gmk67.device.doctor(true))}>Run doctor</button>
              <button onClick={() => run(() => window.gmk67.device.diagnostics())}>Diagnostics</button>
              <button onClick={() => run(() => window.gmk67.device.permissionStatus())}>Permission status</button>
            </div>
          </section>
        );
      case "developer":
        {
          const doctorActions: Array<{ label: string; description: string; action: () => Promise<CommandResult> }> = [
            { label: "Doctor", description: "Read-only resource, protocol, and USB checks.", action: () => window.gmk67.device.doctor(false) },
            { label: "Doctor + HID open", description: "Also verifies macOS can open the configuration interface.", action: () => window.gmk67.device.doctor(true) },
            { label: "Readiness", description: "Concise readiness report without opening HID.", action: () => window.gmk67.developer.run(["readiness"]) },
            { label: "Readiness + open", description: "Concise readiness report with HID open check.", action: () => window.gmk67.developer.run(["readiness", "--open-check"]) },
            { label: "Diagnostics", description: "Full read-only diagnostics report.", action: () => window.gmk67.device.diagnostics() },
            { label: "Support bundle", description: "Writes readiness, diagnostics, protocol, and layout reports.", action: () => window.gmk67.device.supportBundle() },
          ];
          const permissionActions: Array<{ label: string; description: string; action: () => Promise<CommandResult> }> = [
            { label: "Permission status", description: "Check Input Monitoring without opening HID.", action: () => window.gmk67.device.permissionStatus() },
            { label: "Request permission", description: "Ask macOS for Input Monitoring permission.", action: () => window.gmk67.device.permissionRequest() },
          ];
          const readOnlyTools: Array<{ label: string; description: string; args: string[] }> = [
            { label: "Scan HID", description: "List all HID interfaces for the keyboard VID/PID.", args: ["scan"] },
            { label: "List config interface", description: "List likely vendor configuration interfaces.", args: ["list"] },
            { label: "Dump layout", description: "Print vendor keyboard layout resource details.", args: ["dump-layout"] },
            { label: "Self-test", description: "Run offline parser and encoder checks.", args: ["self-test"] },
            { label: "Protocol candidates", description: "Print proven and candidate command families.", args: ["protocol-candidates"] },
            { label: "Windows features", description: "Print extracted Windows feature inventory.", args: ["windows-features"] },
            { label: "Validation plan", description: "Print physical validation checklist.", args: ["validation-plan"] },
          ];

          return (
            <section className="workArea">
              <div className="panel">
                <div className="panelHeader">
                  <div>
                    <h2>Doctor</h2>
                    <p>Read-only diagnostics and support collection</p>
                  </div>
                  <Bug size={18} />
                </div>
                <div className="developerGrid">
                  {doctorActions.map((item) => (
                    <button key={item.label} className="developerAction" onClick={() => run(item.action)}>
                      <strong>{item.label}</strong>
                      <span>{item.description}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div className="panel">
                <div className="panelHeader">
                  <div>
                    <h2>Permissions</h2>
                    <p>macOS Input Monitoring checks</p>
                  </div>
                </div>
                <div className="developerGrid compact">
                  {permissionActions.map((item) => (
                    <button key={item.label} className="developerAction" onClick={() => run(item.action)}>
                      <strong>{item.label}</strong>
                      <span>{item.description}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div className="panel">
                <div className="panelHeader">
                  <div>
                    <h2>Read-only Tools</h2>
                    <p>Protocol, layout, and validation helpers</p>
                  </div>
                </div>
                <div className="developerGrid">
                  {readOnlyTools.map((item) => (
                    <button key={item.label} className="developerAction" onClick={() => run(() => window.gmk67.developer.run(item.args))}>
                      <strong>{item.label}</strong>
                      <span>{item.description}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div className="panel">
                <div className="panelHeader">
                  <div>
                    <h2>Raw Command</h2>
                    <p>Advanced command bridge</p>
                  </div>
                  <Play size={18} />
                </div>
                <div className="developerCommandGrid">
                  <textarea value={developerCommand} onChange={(event) => setDeveloperCommand(event.target.value)} />
                  <button className="primaryButton" onClick={() => run(() => window.gmk67.developer.run(splitSpecs(developerCommand)))}>
                    <Play size={16} />
                    Run
                  </button>
                </div>
              </div>
            </section>
          );
        }
    }
  }, [page, selectedKey, fillColor, mapSpecs, effectName, effectColor, presetName, themeLayout, themeName, keymaps, keymapForm, developerCommand, canWrite, readiness, unsafeKeymapWrites, selectedKeymapSlot, keymapLayer, fnMode, rgbTab, targetKey, fnLayerRemaps, activeKeymapMap, activeKeymapRemaps]);

  return (
    <div className="appShell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brandMark">G</div>
          <div>
            <h1>GMK67</h1>
            <p>Driver</p>
          </div>
        </div>
        <nav>
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <button key={item.page} className={page === item.page ? "active" : ""} onClick={() => setPage(item.page)}>
                <Icon size={18} />
                {item.label}
              </button>
            );
          })}
        </nav>
        <label className="toggle">
          <input type="checkbox" checked={unsafeKeymapWrites} onChange={(event) => setUnsafeKeymapWrites(event.target.checked)} />
          Unsafe keymap writes
        </label>
      </aside>
      <main>
        <StatusBanner readiness={readiness} loading={loadingStatus} onRefresh={refreshStatus} onPermission={() => run(() => window.gmk67.device.permissionRequest())} />
        {lastMessage && <div className="messageStrip">{lastMessage}</div>}
        {keyboardDock}
        <div className="mainGrid">{renderedPage}</div>
        <Console entries={logs} expanded={consoleExpanded} onExpandedChange={setConsoleExpanded} onClear={() => setLogs([])} />
      </main>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }): JSX.Element {
  return (
    <div className="metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
