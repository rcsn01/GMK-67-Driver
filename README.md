# GMK67 Driver

Native macOS tools for configuring the Zuoya/BOYI GMK67 keyboard.

This repository contains:

- `gmk67`, a command-line helper for device diagnostics, RGB control, profile export/import, and protocol testing.
- `GMK67.app`, a SwiftUI desktop app that wraps the same helper for everyday use.
- Reverse-engineering notes and extracted vendor metadata for the GMK67 Windows driver protocol.

The project targets the GMK67 device identified by the vendor software as:

| Field | Value |
| --- | --- |
| VID | `0x05AC` |
| PID | `0x024F` |
| Product | `USB DEVICE` |
| Vendor HID usage page | `0xFFFF` |
| Vendor HID usage | `0x0001` |

Use the keyboard in wired USB mode. Bluetooth mode usually does not expose the vendor configuration HID interface needed for RGB and profile writes.

## Status

Working today:

- Native macOS app and CLI.
- USB HID discovery and readiness diagnostics.
- Input Monitoring permission request/status helpers.
- Proven RGB readback and RGB table write path.
- Built-in RGB presets and one-click RGB presets in the app.
- RGB profile save, restore, dry-run validation, automatic backups, and latest-backup restore.
- Combined profile files that compose RGB presets, custom RGB maps, and optional keymap data.
- App-local profile, keymap, and macro libraries with JSON backup/restore.
- Offline keymap, lighting, macro firmware container, and alternate-table artifact generation/validation for protocol testing.

Experimental or incomplete:

- Keymap writes are guarded because keymap readback/backup is not proven.
- Candidate lighting/effect writes are guarded and may not visibly change the keyboard.
- Board-side macro event encoding/readback is not mapped yet.
- Animated lighting effect selection is not proven as a high-level firmware command.

For deeper protocol details, see `docs/reverse-engineering.md`.

## Requirements

- macOS 13 or newer.
- Swift 5.9 or newer.
- A GMK67 connected over USB.
- macOS Input Monitoring permission for the process that opens the keyboard HID interface.

## Quick Start

Build the CLI:

```sh
swift build --scratch-path .build
```

Run the offline self-test:

```sh
.build/debug/gmk67 self-test
```

Check whether the keyboard and driver are ready:

```sh
.build/debug/gmk67 readiness
.build/debug/gmk67 readiness --open-check
```

Build the app bundle:

```sh
Scripts/build-app.sh
```

Install the built app:

```sh
Scripts/install-app.sh
```

By default, the install script copies `dist/GMK67.app` to `~/Applications/GMK67.app` and opens it. Run `Scripts/build-app.sh` first if the app bundle does not exist.
The script also prints the exact installed helper path and runs a read-only permission status check for it.

## macOS Permissions

macOS can block HID access to keyboards unless the process opening the HID device has Input Monitoring permission.

For the app, use the **Permission** button first. The app runs driver commands in-process so macOS attributes HID access to the app executable:

```text
~/Applications/GMK67.app/Contents/MacOS/GMK67
```

Then enable the app or helper entry shown in:

```text
System Settings > Privacy & Security > Input Monitoring
```

After changing the setting, quit and reopen the app, then unplug and reconnect the keyboard.
Avoid switching between `dist/GMK67.app` and `~/Applications/GMK67.app` while testing permissions; macOS treats those as different app bundles. The bundled `GMK67Helper` remains available for terminal-style support checks, but normal app actions open HID from the app process.

For terminal use, grant Input Monitoring permission to the terminal app running `gmk67`, then rerun:

```sh
.build/debug/gmk67 readiness --open-check
```

Permission helper commands:

```sh
.build/debug/gmk67 permission-status
.build/debug/gmk67 permission-request
```

These commands do not open HID and do not send keyboard reports.

## Using the App

The app is the recommended interface for normal use.

Build only:

```sh
Scripts/build-app.sh
open dist/GMK67.app
```

Install:

```sh
Scripts/install-app.sh
```

Install without launching:

```sh
Scripts/install-app.sh --no-open
```

Install somewhere else:

```sh
Scripts/install-app.sh --dest /path/to/folder
```

The app provides:

- Device readiness, diagnostics, permission request, and support bundle export.
- One-click RGB presets using the proven RGB write path.
- Visual keyboard editor for RGB assignments and remap specs.
- RGB save, restore, backup listing, latest-backup restore, and profile creation.
- Combined profile creation, preview, export, apply, and app-local library management.
- Keymap dry-run/export/library tools, with live writes guarded by the unsafe toggle.
- Macro JSON profile and library management for app-local macro definitions.
- Candidate lighting export/validate/apply controls for protocol testing.
- An advanced command runner for any `gmk67` CLI command.

When launched from the app, helper output, generated files, and automatic RGB backups are written under:

```text
~/Library/Application Support/GMK67
```

## CLI Usage

Show all supported commands:

```sh
.build/debug/gmk67 help
```

### Diagnostics

```sh
.build/debug/gmk67 readiness
.build/debug/gmk67 readiness --open-check
.build/debug/gmk67 doctor
.build/debug/gmk67 doctor --open-check
.build/debug/gmk67 list
.build/debug/gmk67 scan
.build/debug/gmk67 dump-layout
.build/debug/gmk67 diagnostics gmk67-diagnostics.txt
.build/debug/gmk67 support-bundle gmk67-support
```

`readiness` is the normal health check. `doctor` prints more detail. `--open-check` attempts to open the likely configuration interface to verify macOS permission, but it does not send feature reports.

### RGB

Apply built-in RGB presets:

```sh
.build/debug/gmk67 rgb-preset-list
.build/debug/gmk67 rgb-preset-apply wasd
.build/debug/gmk67 rgb-preset-apply ocean
```

Set individual or multiple keys:

```sh
.build/debug/gmk67 rgb-set-key W FF0000
.build/debug/gmk67 rgb-map W=FF0000 A=00FF00 S=0000FF D=00FFFF
```

Set all mapped physical keys or clear them:

```sh
.build/debug/gmk67 rgb-set-all 00FF00
.build/debug/gmk67 rgb-clear
```

Save, validate, and restore RGB tables:

```sh
.build/debug/gmk67 rgb-save current-rgb.hex
.build/debug/gmk67 rgb-restore-dry-run current-rgb.hex
.build/debug/gmk67 rgb-restore current-rgb.hex
.build/debug/gmk67 rgb-backups
.build/debug/gmk67 rgb-restore-latest
```

Mutating RGB commands automatically save `.gmk67-rgb-backup-*.hex` before writing.

### Profiles

Create and apply a combined keyboard profile:

```sh
.build/debug/gmk67 profile-create gaming.json --name=Gaming --rgb=wasd --keymap=none
.build/debug/gmk67 profile-validate gaming.json
.build/debug/gmk67 profile-preview gaming.json
.build/debug/gmk67 profile-apply gaming.json
```

Profiles that include keymap changes require the unsafe flag:

```sh
.build/debug/gmk67 profile-apply gaming-with-keymap.json --unsafe-no-backup
```

Use built-in profile presets:

```sh
.build/debug/gmk67 profile-preset-list
.build/debug/gmk67 profile-preset-show gaming --editor-json
.build/debug/gmk67 profile-preset-create gaming.json gaming
```

Manage the app-local profile library:

```sh
.build/debug/gmk67 profile-library-create --slot=gaming --name=Gaming --rgb=wasd --keymap=none
.build/debug/gmk67 profile-library-list
.build/debug/gmk67 profile-library-preview gaming
.build/debug/gmk67 profile-library-apply gaming
.build/debug/gmk67 profile-library-bundle-export gmk67-profile-library.json
.build/debug/gmk67 profile-library-bundle-import gmk67-profile-library.json
```

### Keymaps

Build and inspect keymap artifacts without writing to the keyboard:

```sh
.build/debug/gmk67 keymap-preset-list
.build/debug/gmk67 keymap-map-dry-run W=up A=left S=down D=right
.build/debug/gmk67 keymap-map-export wasd-arrows.hex W=up A=left S=down D=right
.build/debug/gmk67 keymap-sequence-validate wasd-arrows.hex
```

Apply keymaps only when you intentionally accept the risk:

```sh
.build/debug/gmk67 keymap-file-apply wasd-arrows.hex --unsafe-no-backup
.build/debug/gmk67 keymap-clear --unsafe-no-backup
```

Keymap writes are guarded because this project does not yet have a proven board-side keymap readback/backup path.

### Macros

Macro support creates and manages app-local JSON artifacts. The driver also models
the Windows macro firmware table container as a guarded candidate artifact; it
does not yet encode app-local macro JSON events into firmware records.

```sh
.build/debug/gmk67 macro-create combo.json --name=Combo --repeat=1 down:control key:C up:control
.build/debug/gmk67 macro-validate combo.json
.build/debug/gmk67 macro-library-create --slot=copy --name=Copy down:control key:C up:control
.build/debug/gmk67 macro-library-list
.build/debug/gmk67 macro-library-bundle-export gmk67-macro-library.json
.build/debug/gmk67 macro-firmware-template macro-fw.hex
.build/debug/gmk67 macro-firmware-validate macro-fw.hex
```

Live macro firmware candidate writes require `--unsafe-no-backup` and should only
be used with captured/understood firmware tables:

```sh
.build/debug/gmk67 macro-firmware-apply macro-fw.hex --unsafe-no-backup
```

### Experimental Lighting

Candidate lighting commands are available for controlled protocol testing:

```sh
.build/debug/gmk67 lighting-mode-preset-list
.build/debug/gmk67 lighting-mode-preset-export wasd-mode.hex wasd-steps
.build/debug/gmk67 lighting-mode-validate wasd-mode.hex
.build/debug/gmk67 lighting-effect-list
.build/debug/gmk67 lighting-effect-export breath.hex breath
.build/debug/gmk67 short-op-template short-op.hex static-80
.build/debug/gmk67 short-op-validate short-op.hex
.build/debug/gmk67 keyboard-settings-export keyboard-settings.hex gamemode=on disable-win=on sleep-light=30
.build/debug/gmk67 keyboard-settings-validate keyboard-settings.hex
```

Live candidate lighting writes require `--unsafe-no-backup`:

```sh
.build/debug/gmk67 lighting-effect-apply breath --unsafe-no-backup
.build/debug/gmk67 short-op-apply short-op.hex --unsafe-no-backup
.build/debug/gmk67 keyboard-settings-apply keyboard-settings.hex --unsafe-no-backup
```

These commands may not visibly change lighting. The known reliable path for color changes is the RGB preset/table path.

## Safety Notes

- Run `readiness --open-check` before live writes.
- Save or verify an RGB backup before testing keymap or lighting candidates.
- Treat every command requiring `--unsafe-no-backup` as experimental.
- Do not run candidate keymap, lighting, or factory reset commands unless you understand the current rollback limitations.
- Use `validation-plan` for a step-by-step physical testing workflow:

```sh
.build/debug/gmk67 validation-plan
```

## Project Layout

```text
Sources/GMK67Driver/    CLI helper and HID/protocol implementation
Sources/GMK67App/       SwiftUI app
Resources/vendor/       Extracted vendor XML metadata
Scripts/                Build/install scripts for the app bundle
docs/                   Reverse-engineering notes
```

## Development

Build and test:

```sh
swift build --scratch-path .build
.build/debug/gmk67 self-test
.build/debug/gmk67 readiness
```

Useful read-only reports:

```sh
.build/debug/gmk67 protocol-candidates
.build/debug/gmk67 windows-features
.build/debug/gmk67 diagnostics
.build/debug/gmk67 support-bundle
```

The driver code is intentionally split by responsibility:

- `Core`: shared constants, models, errors, and hex helpers.
- `HID`: IOKit HID discovery, reports, and device printing.
- `Layout`: vendor keyboard layout loading and key lookup.
- `Protocol`: RGB/keymap/lighting report builders and table helpers.
- `Presets`: built-in RGB, keymap, lighting, and combined profile presets.
- `Profiles`: JSON profile and library management.
- `Diagnostics`: readiness, permission, and support reporting.
- `CLI`: command usage, option parsing, and routing.

## License

No license has been added yet. Treat this repository as all rights reserved until a license is chosen.
