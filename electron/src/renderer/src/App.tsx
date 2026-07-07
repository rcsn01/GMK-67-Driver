import { Activity, Bug, Cpu, Keyboard, Layers3, Lightbulb, Play, Save, Search, SlidersHorizontal, Sparkles, Usb } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Console } from "./components/Console";
import { StatusBanner } from "./components/StatusBanner";
import { VisualKeyboard } from "./components/VisualKeyboard";
import type { CommandLogEntry, CommandResult, KeymapLibraryEntry, MacroLibraryEntry, ProfileLibraryEntry, ReadinessReport, RGBRecord } from "../../shared/types";
import { normalizeHexColor, splitSpecs } from "../../shared/validation";

type Page = "rgb" | "profiles" | "keymap" | "macros" | "device" | "developer";
type KeymapLayer = "top" | "fn";
type FnMode = "momentary" | "toggle";

const navItems: Array<{ page: Page; label: string; icon: typeof Lightbulb }> = [
  { page: "rgb", label: "RGB", icon: Lightbulb },
  { page: "profiles", label: "Profiles", icon: Layers3 },
  { page: "keymap", label: "Keymap", icon: Keyboard },
  { page: "macros", label: "Macros", icon: Activity },
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
  const [selectedColor, setSelectedColor] = useState("FF0000");
  const [fillColor, setFillColor] = useState("000000");
  const [mapSpecs, setMapSpecs] = useState("W=FF0000 A=00FF00 S=0000FF D=00FFFF");
  const [effectName, setEffectName] = useState("breath");
  const [effectColor, setEffectColor] = useState("FFFFFF");
  const [presetName, setPresetName] = useState("wasd");
  const [themeLayout, setThemeLayout] = useState("wasd");
  const [themeName, setThemeName] = useState("rainbow");
  const [keyboardColors, setKeyboardColors] = useState<Map<string, string>>(new Map());
  const [profiles, setProfiles] = useState<ProfileLibraryEntry[]>([]);
  const [keymaps, setKeymaps] = useState<KeymapLibraryEntry[]>([]);
  const [macros, setMacros] = useState<MacroLibraryEntry[]>([]);
  const [profileForm, setProfileForm] = useState({ slot: "gaming", name: "Gaming", rgbPreset: "wasd", keymapPreset: "wasd-arrows", rgbFill: "000000", rgbAssignments: "space=00FF00", keymapRemaps: "W=up A=left S=down D=right" });
  const [keymapForm, setKeymapForm] = useState({ slot: "wasd", name: "WASD Arrows", remaps: "W=up A=left S=down D=right" });
  const [macroForm, setMacroForm] = useState({ slot: "combo", name: "Combo", repeatCount: "1", events: "down:control key:C up:control delay:50" });
  const [developerCommand, setDeveloperCommand] = useState("doctor");
  const [lastMessage, setLastMessage] = useState("");
  const [unsafeKeymapWrites, setUnsafeKeymapWrites] = useState(false);
  const [consoleExpanded, setConsoleExpanded] = useState(false);
  const [selectedKeymapSlot, setSelectedKeymapSlot] = useState("");
  const [keymapLayer, setKeymapLayer] = useState<KeymapLayer>("top");
  const [fnMode, setFnMode] = useState<FnMode>("momentary");
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
      window.gmk67.profiles.list().then(setProfiles),
      window.gmk67.keymap.list().then(setKeymaps),
      window.gmk67.macros.list().then(setMacros),
    ]);
  }

  async function syncRGBDump(): Promise<void> {
    try {
      const records = await window.gmk67.rgb.dump();
      setKeyboardColors(recordColors(records));
      setLastMessage(`Loaded ${records.length} RGB record(s).`);
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

  const renderedPage = useMemo(() => {
    switch (page) {
      case "rgb":
        return (
          <section className="workArea">
            <div className="panel">
              <div className="panelHeader">
                <div>
                  <h2>Per-key RGB</h2>
                  <p>{selectedKey} #{selectedColor}</p>
                </div>
                <button className="iconButton" onClick={syncRGBDump} title="Read RGB table">
                  <Search size={17} />
                </button>
              </div>
              <VisualKeyboard selectedKey={selectedKey} colorsByKey={keyboardColors} onSelect={setSelectedKey} />
              <div className="formGrid">
                <label>
                  Key
                  <input value={selectedKey} onChange={(event) => setSelectedKey(event.target.value)} />
                </label>
                <label>
                  Color
                  <input value={selectedColor} onChange={(event) => setSelectedColor(event.target.value.toUpperCase())} />
                </label>
                <button className="primaryButton" disabled={!canWrite} onClick={() => run(() => window.gmk67.rgb.setKey(selectedKey, normalizeHexColor(selectedColor)))}>
                  <Save size={16} />
                  Apply key
                </button>
              </div>
            </div>
            <div className="panel">
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
            </div>
            <div className="panel">
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
            </div>
          </section>
        );
      case "profiles":
        return (
          <LibraryPanel
            title="Profiles"
            entries={profiles.map((entry) => ({ id: entry.slot, title: entry.name, detail: `${entry.rgbPreset} / ${entry.keymapPreset ?? "no keymap"} / ${entry.customRGB} RGB / ${entry.customRemaps} remap(s)` }))}
            onRefresh={refreshLibraries}
            form={
              <>
                <div className="formGrid two">
                  <input value={profileForm.slot} onChange={(event) => setProfileForm({ ...profileForm, slot: event.target.value })} placeholder="Slot" />
                  <input value={profileForm.name} onChange={(event) => setProfileForm({ ...profileForm, name: event.target.value })} placeholder="Name" />
                  <input value={profileForm.rgbPreset} onChange={(event) => setProfileForm({ ...profileForm, rgbPreset: event.target.value })} placeholder="RGB preset" />
                  <input value={profileForm.keymapPreset} onChange={(event) => setProfileForm({ ...profileForm, keymapPreset: event.target.value })} placeholder="Keymap preset" />
                </div>
                <textarea value={profileForm.rgbAssignments} onChange={(event) => setProfileForm({ ...profileForm, rgbAssignments: event.target.value })} />
                <textarea value={profileForm.keymapRemaps} onChange={(event) => setProfileForm({ ...profileForm, keymapRemaps: event.target.value })} />
                <button onClick={() => run(async () => {
                  const result = await window.gmk67.profiles.create({
                    ...profileForm,
                    rgbFill: profileForm.rgbFill,
                    rgbAssignments: splitSpecs(profileForm.rgbAssignments),
                    keymapRemaps: splitSpecs(profileForm.keymapRemaps),
                  });
                  await refreshLibraries();
                  return result;
                })}>Save profile</button>
              </>
            }
            onApply={(slot) => run(() => window.gmk67.profiles.apply(slot, unsafeKeymapWrites))}
            onDelete={(slot) => run(async () => {
              const result = await window.gmk67.profiles.delete(slot);
              await refreshLibraries();
              return result;
            })}
          />
        );
      case "keymap":
        {
          const activeRemaps = keymapLayer === "top" ? keymapForm.remaps : fnLayerRemaps;
          const activeRemapMap = parseRemapText(activeRemaps);
          const keyboardMappings = new Map([...activeRemapMap.entries()].map(([source, target]) => [source, mappingLabel(target)]));
          const currentTarget = activeRemapMap.get(normalizeKeySpec(selectedKey)) ?? "";
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
            updateActiveRemaps(setRemapInText(activeRemaps, selectedKey, nextTarget));
          };
          const clearSelectedKey = () => {
            updateActiveRemaps(setRemapInText(activeRemaps, selectedKey, ""));
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
                <VisualKeyboard
                  selectedKey={selectedKey}
                  sourceKey={keymapLayer === "fn" ? "fn" : null}
                  colorsByKey={new Map()}
                  mappingsByKey={keyboardMappings}
                  onSelect={(key) => {
                    setSelectedKey(key);
                    setTargetKey(activeRemapMap.get(normalizeKeySpec(key)) ?? key);
                  }}
                />
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
                  <textarea value={activeRemaps} onChange={(event) => updateActiveRemaps(event.target.value)} />
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
      case "macros":
        return (
          <LibraryPanel
            title="Macros"
            entries={macros.map((entry) => ({ id: entry.slot, title: entry.name, detail: `${entry.repeatCount} repeat / ${entry.eventCount} event(s)` }))}
            onRefresh={refreshLibraries}
            form={
              <>
                <div className="formGrid two">
                  <input value={macroForm.slot} onChange={(event) => setMacroForm({ ...macroForm, slot: event.target.value })} placeholder="Slot" />
                  <input value={macroForm.name} onChange={(event) => setMacroForm({ ...macroForm, name: event.target.value })} placeholder="Name" />
                  <input value={macroForm.repeatCount} onChange={(event) => setMacroForm({ ...macroForm, repeatCount: event.target.value })} placeholder="Repeat" />
                </div>
                <textarea value={macroForm.events} onChange={(event) => setMacroForm({ ...macroForm, events: event.target.value })} />
                <button onClick={() => run(async () => {
                  const result = await window.gmk67.macros.create({
                    slot: macroForm.slot,
                    name: macroForm.name,
                    repeatCount: Number(macroForm.repeatCount) || 1,
                    events: splitSpecs(macroForm.events),
                  });
                  await refreshLibraries();
                  return result;
                })}>Save macro</button>
              </>
            }
            onDelete={(slot) => run(async () => {
              const result = await window.gmk67.macros.delete(slot);
              await refreshLibraries();
              return result;
            })}
          />
        );
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
        return (
          <section className="workArea">
            <div className="panel">
              <div className="panelHeader">
                <div>
                  <h2>Developer</h2>
                  <p>Raw command bridge</p>
                </div>
                <Bug size={18} />
              </div>
              <textarea value={developerCommand} onChange={(event) => setDeveloperCommand(event.target.value)} />
              <button onClick={() => run(() => window.gmk67.developer.run(splitSpecs(developerCommand)))}>
                <Play size={16} />
                Run
              </button>
            </div>
          </section>
        );
    }
  }, [page, selectedKey, selectedColor, fillColor, mapSpecs, effectName, effectColor, presetName, themeLayout, themeName, keyboardColors, profiles, keymaps, macros, profileForm, keymapForm, macroForm, developerCommand, canWrite, readiness, unsafeKeymapWrites, selectedKeymapSlot, keymapLayer, fnMode, targetKey, fnLayerRemaps]);

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

function LibraryPanel({
  title,
  entries,
  form,
  onRefresh,
  onApply,
  onDelete,
}: {
  title: string;
  entries: Array<{ id: string; title: string; detail: string }>;
  form: JSX.Element;
  onRefresh: () => void;
  onApply?: (slot: string) => void;
  onDelete: (slot: string) => void;
}): JSX.Element {
  return (
    <section className="workArea">
      <div className="panel">
        <div className="panelHeader">
          <div>
            <h2>{title} Library</h2>
            <p>{entries.length} saved item(s)</p>
          </div>
          <button className="iconButton" onClick={onRefresh} title="Refresh library">
            <Search size={16} />
          </button>
        </div>
        <div className="libraryList">
          {entries.length === 0 ? (
            <div className="emptyState">No saved entries.</div>
          ) : (
            entries.map((entry) => (
              <div className="libraryRow" key={entry.id}>
                <div>
                  <strong>{entry.title}</strong>
                  <span>{entry.id}</span>
                  <p>{entry.detail}</p>
                </div>
                {onApply && <button onClick={() => onApply(entry.id)}>Apply</button>}
                <button onClick={() => onDelete(entry.id)}>Delete</button>
              </div>
            ))
          )}
        </div>
      </div>
      <div className="panel">
        <div className="panelHeader">
          <div>
            <h2>Editor</h2>
            <p>Save to app library</p>
          </div>
        </div>
        <div className="editorStack">{form}</div>
      </div>
    </section>
  );
}
