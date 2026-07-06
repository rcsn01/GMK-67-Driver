# GMK67 Refactor Plan

This plan describes how to split the two current monolithic Swift files into smaller files without changing behavior:

- `Sources/GMK67Driver/main.swift`
- `Sources/GMK67App/main.swift`

The goal is to make the driver and app easier to navigate, review, and extend while keeping the first refactor mostly mechanical. Avoid protocol redesign, UI redesign, or behavioral fixes during the file split unless a build error forces a tiny compatibility adjustment.

## Ground Rules

- Keep each step buildable. Run `swift build --scratch-path .build` after every small group of moves.
- Start with mechanical file extraction. Do not rename commands, change CLI output, rewrite protocols, or restructure the UI layout in the same pass.
- Keep all new files inside the existing SwiftPM target folders. SwiftPM compiles all Swift files in a target path, including subdirectories, so no `Package.swift` change is needed for the initial split.
- Expect access-control edits. Many top-level declarations are currently `private` because everything lives in one file. When a moved declaration must be used by another file in the same target, change it from `private` to the default internal access. Keep helpers `private` when they are only used inside their new file.
- Keep only one executable entry point per target. The driver should end with a tiny `main.swift`; the SwiftUI app should keep exactly one `@main` app declaration.
- Commit or at least verify after each phase. This makes it easy to locate mistakes caused by a move.

## Proposed Driver Layout

Target root: `Sources/GMK67Driver/`

```text
Sources/GMK67Driver/
  main.swift

  Core/
    GMK67Constants.swift
    DriverError.swift
    Hex.swift
    Models.swift

  HID/
    HIDDeviceInfo.swift
    HIDDriver.swift
    InputReportContext.swift
    IOReturnNames.swift

  Layout/
    KeyboardLayout.swift
    KeyLookup.swift
    HIDUsageNames.swift

  Protocol/
    FeatureReports.swift
    RGBFrames.swift
    KeymapProtocol.swift
    LightingProtocol.swift
    FactoryReset.swift

  Presets/
    RGBPresets.swift
    KeymapPresets.swift
    LightingPresets.swift
    CombinedProfilePresets.swift

  Profiles/
    CombinedProfile.swift
    ProfileIO.swift
    ProfileLibrary.swift
    AppLibraryBundle.swift

  Keymaps/
    KeymapProfile.swift
    KeymapLibrary.swift

  Macros/
    MacroProfile.swift
    MacroLibrary.swift

  Diagnostics/
    Readiness.swift
    DiagnosticsReport.swift
    SupportBundle.swift
    ValidationPlan.swift
    PermissionReport.swift

  CLI/
    Usage.swift
    CommandRouter.swift
    CommandOptions.swift
    DeviceCommands.swift
    RGBCommands.swift
    KeymapCommands.swift
    ProfileCommands.swift
    MacroCommands.swift
    LightingCommands.swift
```

### Driver Responsibilities

`main.swift`

- Keep this file as the entry point only.
- It should call a router function and handle errors:

```swift
do {
    try run(CommandLine.arguments)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
```

`Core/`

- Move `GMK67`, shared DTOs, shared constants, `DriverError`, `parseHexBytes`, and `hex`.
- If `Models.swift` gets too large, split it later by domain. For the first pass, centralizing the Codable record and bundle models is enough.

`HID/`

- Move `HIDDeviceInfo`, `HIDDriver`, `InputReportContext`, `ioReturnName`, `printDevices`, and `formatUsagePairs`.
- Keep IOKit/CoreFoundation-specific code here so protocol and CLI files do not need to know as much about raw HID plumbing.

`Layout/`

- Move `loadKeyboardLayout`, XML attribute parsing helpers, key lookup aliases, layout maps, and HID usage-name helpers.
- This area owns translating user-facing key names like `W`, `caps`, or `left` into layout records and HID usage bytes.

`Protocol/`

- Move feature-report construction, RGB table read/write, keymap sequence generation, lighting candidate sequence generation, and reset artifact generation.
- Keep device I/O helpers separate from pure sequence builders where possible:
  - Pure builders return `[[UInt8]]`.
  - Live operations accept `HIDDriver` or opened `IOHIDDevice` values.

`Presets/`

- Move built-in preset arrays and lookup/printing functions.
- Keep preset definition structs with either `Core/Models.swift` or the relevant preset file. Prefer the smallest scope that still avoids circular-looking dependencies.

`Profiles/`, `Keymaps/`, and `Macros/`

- Move profile validation, JSON read/write, preview, library slots, bundle import/export, and app-library bundle helpers.
- Keep each library implementation close to its profile type. For example, `MacroLibrary.swift` should contain macro library paths, list, save, delete, bundle export, and bundle import.

`Diagnostics/`

- Move `doctor`, `readiness`, support bundle creation, physical validation text, protocol-candidate text, and Input Monitoring permission report generation.
- These commands should remain read-only unless their current behavior explicitly requests permission.

`CLI/`

- Move `printUsage` into `Usage.swift`.
- Move the current `run(_:)` switch into `CommandRouter.swift`.
- Move option parsers such as `parseProfileApplyOptions`, `parseRGBMapOptions`, and unsafe write option parsing into `CommandOptions.swift`.
- After the mechanical split is stable, optionally split the giant switch into domain functions:
  - `runDeviceCommand(command:args:)`
  - `runRGBCommand(command:args:)`
  - `runKeymapCommand(command:args:)`
  - `runProfileCommand(command:args:)`
  - `runMacroCommand(command:args:)`
  - `runLightingCommand(command:args:)`

Do this second step only after the file move builds cleanly.

## Proposed App Layout

Target root: `Sources/GMK67App/`

```text
Sources/GMK67App/
  GMK67Application.swift

  App/
    AppDelegate.swift
    DeviceStatusKind.swift
    AppModels.swift

  Services/
    HelperLocator.swift
    HelperCommandRunner.swift
    DriverModel.swift
    DriverModel+Device.swift
    DriverModel+RGB.swift
    DriverModel+Profiles.swift
    DriverModel+Keymap.swift
    DriverModel+Macros.swift
    DriverModel+Lighting.swift
    DriverModel+Diagnostics.swift
    DriverModel+VisualEditor.swift

  Views/
    ContentView.swift
    DeviceStatusBanner.swift
    DevicePanel.swift
    VisualKeyboardPanel.swift
    ProfilePanel.swift
    QuickPresetsPanel.swift
    RGBPanel.swift
    KeymapPanel.swift
    MacroPanel.swift
    LightingPanel.swift
    AdvancedPanel.swift
    ConsoleView.swift

  Views/Components/
    Panel.swift
    CommandButton.swift
    ActionButton.swift
    VisualKeyButton.swift

  ViewModels/
    VisualKeyboardLayout.swift
    VisualRemap.swift

  Utilities/
    ColorHex.swift
    CommandLineParsing.swift
    SpecEditing.swift
```

### App Responsibilities

`GMK67Application.swift`

- Keep only the `@main` app declaration and the scene setup.
- Move `AppDelegate` out to `App/AppDelegate.swift`.

`App/AppModels.swift`

- Move the app-side Codable structs:
  - `AppProfileLibraryEntry`
  - `AppCombinedProfile`
  - `AppMacroLibraryEntry`
  - `AppKeymapLibraryEntry`
  - `AppKeymapProfile`
  - `AppRGBPreset`
  - `AppKeymapPreset`
  - `AppMacroProfile`
  - `AppMacroEvent`
  - `AppRGBRecord`
  - `AppKeymapRecord`
  - `AppByteRecord`

`Services/DriverModel.swift`

- Keep the `DriverModel` class declaration, all `@Published` state, and small generic helpers such as `append` and `clearOutput`.
- Do not move stored properties into extensions; Swift does not allow stored properties in extensions.
- Then move behavior into extensions by domain:
  - `DriverModel+Device.swift`: status refresh, permission request, settings open.
  - `DriverModel+RGB.swift`: RGB save/restore/create/apply/load operations.
  - `DriverModel+Profiles.swift`: combined profile creation, preview, apply, library operations.
  - `DriverModel+Keymap.swift`: keymap export/apply/library operations.
  - `DriverModel+Macros.swift`: macro builder, macro profile, macro library operations.
  - `DriverModel+Lighting.swift`: lighting custom RGB, mode, and effect operations.
  - `DriverModel+Diagnostics.swift`: diagnostics report, support bundle, factory reset.
  - `DriverModel+VisualEditor.swift`: selected key color/remap editor actions.

`Services/HelperLocator.swift` and `Services/HelperCommandRunner.swift`

- Extract helper discovery and process execution from `DriverModel`.
- A small service can own:
  - bundled helper lookup
  - debug helper lookup
  - helper working directory
  - bundled resources environment
  - `run` and `runCapture` process logic
- `DriverModel` can then call the service and remain focused on UI state updates.

`Views/`

- Move each SwiftUI panel into its own file.
- Keep `ContentView` responsible for high-level layout only.
- Keep reusable buttons and wrappers under `Views/Components/`.

`ViewModels/` and `Utilities/`

- Move `VisualKey`, `VisualKeyRow`, `visualKeyboardRows`, `VisualRemap`, and remap display helpers out of the panel file.
- Move `rgbHex`, `colorFromHex`, `splitCommandLine`, `quoteCommandToken`, `upsertSpec`, `removeSpec`, `colorForKey`, and `visualColorForKey` into utility files.

## Extraction Order

### Phase 1: Baseline

1. Capture the current state with `git status`.
2. Build before moving anything:

```sh
swift build --scratch-path .build
```

3. Run no-hardware checks where possible:

```sh
.build/debug/gmk67 self-test
.build/debug/gmk67 dump-layout
.build/debug/gmk67 readiness
```

### Phase 2: Split App Views First

1. Create `Views/`, `Views/Components/`, `ViewModels/`, and `Utilities/`.
2. Move pure SwiftUI views one at a time:
   - `Panel`
   - `CommandButton`
   - `ActionButton`
   - `ConsoleView`
   - `DeviceStatusBanner`
   - each panel view
   - `ContentView`
3. Move visual keyboard types and utility functions after the views compile.
4. Build after every few files.

This phase is low risk because it mostly moves declarations without changing logic.

### Phase 3: Split App Models and Services

1. Move app Codable structs and `DeviceStatusKind`.
2. Extract helper lookup and process execution into services.
3. Keep `DriverModel` state in `DriverModel.swift`.
4. Move `DriverModel` methods into domain-specific extensions.
5. Build and launch the app after the split.

Watch for `private` declarations that must become internal after moving files. For example, a utility used by multiple views cannot remain top-level `private`.

### Phase 4: Split Driver Foundations

1. Move constants, errors, hex helpers, and models.
2. Move HID wrapper types and functions.
3. Move keyboard layout parsing and key lookup.
4. Move protocol builders and live protocol operations.
5. Build after each directory is populated.

This establishes the dependency direction:

```text
CLI -> Diagnostics/Profiles/Protocol -> HID/Layout/Core
App does not import Driver target; it still talks to the helper executable.
```

### Phase 5: Split Driver Domains

1. Move RGB profile logic and backup helpers.
2. Move keymap profile, keymap sequence, and keymap library logic.
3. Move combined profile logic and profile library logic.
4. Move macro profile and macro library logic.
5. Move lighting mode/effect logic.
6. Move factory reset and diagnostics.
7. Move usage text and command option parsers.

Keep the existing `run(_:)` switch intact at first, even if it lives in `CLI/CommandRouter.swift`. A later cleanup can route command families to smaller functions.

### Phase 6: Reduce the Driver Command Router

After all moves build cleanly, split the command switch by domain.

Recommended pattern:

```swift
enum CommandDispatchResult {
    case handled
    case notHandled
}
```

Each domain router can return `.handled` or `.notHandled`. The top-level router asks each domain in order and falls back to `printUsage()`.

This keeps each command group readable while preserving the current CLI behavior.

### Phase 7: Optional Shared Core Target

Only consider this after the mechanical split is done.

The app currently duplicates some DTOs that mirror helper JSON. If that duplication becomes painful, add a small library target such as `GMK67Core` for shared Codable models and command names:

```swift
.library(name: "GMK67Core", targets: ["GMK67Core"])
```

Then make both executable targets depend on it. Do not put HID or SwiftUI code in this shared target. Keep it limited to pure Swift models, command constants, and parsing helpers that genuinely need to be shared.

## Access-Control Checklist

When moving code, decide access intentionally:

- Keep declarations `private` if only used inside the same new file.
- Use default internal access for declarations used across files in the same target.
- Avoid `public`; this package does not expose a public library API yet.
- For `DriverModel` extensions, methods called by views must be internal, not private.
- For helper utilities used by several views, prefer internal top-level functions in `Utilities/`.
- If a type is only used by one panel, move it beside that panel and keep it private.

## Validation Checklist

Run these after each major phase:

```sh
swift build --scratch-path .build
.build/debug/gmk67 self-test
.build/debug/gmk67 readiness
.build/debug/gmk67 protocol-candidates
.build/debug/gmk67 validation-plan
```

For app packaging, also run the existing app build/install workflow used by the project and verify:

- The app launches.
- The helper is found.
- Device status refresh still works.
- The Permission button still calls the helper permission command.
- One-click RGB presets still call proven RGB commands.
- Advanced commands still execute and stream output.

## Suggested Commit Slices

1. `Split GMK67App views into focused files`
2. `Extract GMK67App helper runner and model extensions`
3. `Split GMK67Driver core, HID, and layout files`
4. `Split GMK67Driver protocol and profile domains`
5. `Move GMK67Driver CLI usage and command routing`
6. `Reduce GMK67Driver command router by domain`

Keep the optional shared target as a separate later commit or PR.

## Biggest Risks

- Accidentally changing behavior while moving code. Keep the first pass mechanical.
- Leaving declarations `private` after moving their callers into other files.
- Creating a shared target too early and turning a file split into a design migration.
- Splitting the command router before the domain functions are stable.
- Moving SwiftUI stored state into extensions, which Swift does not allow.

The safest path is to split the app views first, then app services, then driver foundations, then driver domains, and only then simplify the command router.
