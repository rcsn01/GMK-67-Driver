# GMK67 Driver

Native macOS user-space driver tools for the Zuoya/BOYI GMK67 keyboard.

The bundled Windows installers identify this keyboard as:

- VID: `0x05AC`
- PID: `0x024F`
- Product: `USB DEVICE`
- Vendor configuration HID usage page: `0xFFFF`
- Vendor configuration HID usage: `0x0001`
- Wired configuration interface observed on macOS: `USB DEVICE`, maker
  `hfd.cn`, 64-byte feature reports.

## Build

```sh
swift build
```

If SwiftPM tries to write outside the repository in a restricted environment:

```sh
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache swift build --scratch-path .build
```

The executable is written to:

```sh
.build/debug/gmk67
```

Run the offline regression checks without opening HID:

```sh
.build/debug/gmk67 self-test
```

## macOS App

Build the native app bundle:

```sh
Scripts/build-app.sh
```

The script builds both the GUI and the helper, packages `dist/GMK67.app`, and
ad-hoc signs the bundle when `codesign` is available.

The app is written to:

```sh
dist/GMK67.app
```

Open it from Finder or with:

```sh
open dist/GMK67.app
```

Install it for normal use:

```sh
Scripts/install-app.sh
```

By default this copies the bundle to `~/Applications/GMK67.app` and opens it.
Use `Scripts/install-app.sh --no-open` to install without launching, or
`Scripts/install-app.sh --dest /path/to/folder` to choose another destination.

The app bundles the `gmk67` command-line driver as `Contents/Resources/Helper/gmk67`
and uses the same protocol implementation as the terminal tool. It exposes:

- Device diagnostics: readiness, doctor, open-check, interface list, layout dump,
  self-test, protocol notes, and diagnostics report export.
- RGB controls: native color pickers for one-key/all-key writes, dump current
  RGB, clear, built-in lighting presets, load a built-in preset into the visual
  editor for tweaking, create fresh RGB profiles, save, validate, restore
  profiles, and load saved/current RGB tables back into the visual editor.
- Visual keyboard editor: click keys to assign RGB and remaps; duplicate
  physical keys such as left/right Shift and Alt are addressed with stable
  key-index specs while retaining readable labels.
- RGB backup controls: list automatic backups and restore the newest valid
  backup from the app's working directory.
- Keyboard profiles: built-in whole-keyboard presets plus load into editor,
  create, validate, and apply for combined profiles made from a lighting preset
  plus an optional keymap preset.
- Keymap tooling: built-in remap presets, load a preset into the visual remap
  editor for tweaking, dry-run simple and multi-remaps, direct guarded
  multi-remap apply/clear, export/validate/load keymap profile files, and
  guarded unsafe profile apply.
- Macro tooling: event builder for key taps, key down/up, text, and delays,
  plus create, validate, import, load, list, backup, restore, and delete
  app-local macro JSON profiles while the board-side macro write protocol is
  still unmapped.
- Lighting tooling: export, validate, and guarded-apply candidate
  custom-lighting RGB feature sequences, Windows-named candidate lighting
  effects, and candidate lighting-mode presets, with file loading back into the
  editor.
- Advanced command runner: execute any `gmk67` command without leaving the app.
- Whole-app library backup/restore for saved profiles, keymaps, and macros as
  one portable JSON bundle.

Keep the terminal CLI available for scripting and reverse-engineering work; the
app is a GUI wrapper around the same driver executable.

On first launch, use the status banner at the top of the app. If it shows
`Permission needed`, grant Input Monitoring permission to `GMK67.app` in System
Settings, then quit and reopen the app and reconnect the keyboard. macOS blocks
live RGB and keymap HID writes until that permission is granted.

The app keeps offline actions available while permission is missing: create,
load, preview, export, validate, and library operations still work. Live HID
commands such as RGB apply/restore, loading current RGB, profile apply, keymap
apply, lighting apply, and factory reset are gated until the Device status is
ready.

When commands are launched from the app, the helper runs in:

```sh
~/Library/Application Support/GMK67
```

Automatic RGB backups and generated profile files are written there unless you
choose a different path in a save/open panel. The bundled vendor XML resources
are loaded from inside `GMK67.app`.

The app's keymap Apply and Clear buttons use the same guarded commands as the
CLI and require the unsafe writes checkbox. The Keyboard Profile panel can use
built-in whole-keyboard presets or create manual RGB-only profiles by disabling
its keymap include checkbox.

Back up or restore every app-local profile, keymap, and macro library at once:

```sh
.build/debug/gmk67 app-library-bundle-export gmk67-app-library.json
.build/debug/gmk67 app-library-bundle-import gmk67-app-library.json
```

For testing or portable folders, pass `--profiles=path`, `--keymaps=path`, and
`--macros=path`. These commands validate all nested records and do not open HID.

## Commands

List the GMK67 configuration HID interface:

```sh
.build/debug/gmk67 list
```

List all HID interfaces with the installer VID/PID:

```sh
.build/debug/gmk67 scan
```

Print the vendor key map extracted from `KeyboardLayout.xml`:

```sh
.build/debug/gmk67 dump-layout
```

Run parser, RGB table, and keymap sequence checks without touching the keyboard:

```sh
.build/debug/gmk67 self-test
```

Check the driver resources, offline protocol logic, USB interfaces, and
optionally macOS HID open permission:

```sh
.build/debug/gmk67 readiness
.build/debug/gmk67 readiness --open-check
.build/debug/gmk67 doctor
.build/debug/gmk67 doctor --open-check
.build/debug/gmk67 permission-status
.build/debug/gmk67 permission-request
```

`readiness` is the concise status report for normal app/driver use. `doctor`
prints more detail. Neither command sends HID reports. `--open-check` attempts
to open the likely configuration interface, which is useful for confirming
whether macOS Input Monitoring permission is in place before running read/write
commands. `permission-status` and `permission-request` use macOS' Input
Monitoring permission APIs without opening HID or sending reports.

Print the current proven and candidate vendor protocol command families without
opening HID:

```sh
.build/debug/gmk67 protocol-candidates
```

Print the next physical validation checklist without opening HID:

```sh
.build/debug/gmk67 validation-plan
```

Print or save a read-only diagnostics report with resource checks, offline
protocol status, USB interface discovery, and protocol notes:

```sh
.build/debug/gmk67 diagnostics
.build/debug/gmk67 diagnostics gmk67-diagnostics.txt
```

Create a read-only support bundle directory containing readiness, diagnostics,
protocol, and layout reports:

```sh
.build/debug/gmk67 support-bundle
.build/debug/gmk67 support-bundle gmk67-support
```

Read a raw feature report:

```sh
.build/debug/gmk67 feature-get <report-id-hex> <length-decimal>
```

Read from a specific configuration interface shown by `list`:

```sh
.build/debug/gmk67 feature-get-at <config-index> <report-id-hex> <length-decimal>
```

Scan readable feature report IDs without writing to the keyboard:

```sh
.build/debug/gmk67 feature-scan 0 00 FF 64
```

Listen for interrupt input reports without writing to the keyboard:

```sh
.build/debug/gmk67 input-listen 0 8 10
.build/debug/gmk67 input-listen 1 16 10
```

Run a decoded key tester without writing to the keyboard:

```sh
.build/debug/gmk67 key-test 0 8 10
```

Read a one-shot input report from a scanned VID/PID interface:

```sh
.build/debug/gmk67 input-get-at <scan-index> <report-id-hex> <length-decimal>
```

Write a raw feature report payload:

```sh
.build/debug/gmk67 feature-set <report-id-hex> <payload-hex>
```

Write a feature report payload padded to the vendor app's 64-byte payload size:

```sh
.build/debug/gmk67 feature-set64 <report-id-hex> <payload-hex>
```

Probe the vendor RGB readback path observed in the Windows app:

```sh
.build/debug/gmk67 rgb-read-probe 0 1 3 2
```

Probe the same path via explicit input-report reads after the request:

```sh
.build/debug/gmk67 rgb-read-get-probe 0 0 00 64 3
```

Dump and parse the current per-key RGB table:

```sh
.build/debug/gmk67 rgb-dump 0 0 9
.build/debug/gmk67 rgb-dump 0 0 9 --json
```

Set one key in the current RGB table and inspect the rendered readback:

```sh
.build/debug/gmk67 rgb-set-key W FF0000
```

Set multiple keys in one RGB write:

```sh
.build/debug/gmk67 rgb-map W=FF0000 A=00FF00 S=0000FF D=00FFFF
```

Mutating RGB commands save an automatic `.gmk67-rgb-backup-*.hex` file before
writing. The board's rendered readback may be scaled or mode-composited; for
example, a physical W-key red write can read back as `FD 7F 00` rather than an
exact `FF 00 00` byte echo.

Set all physical keys from the vendor layout to one color, or clear them:

```sh
.build/debug/gmk67 rgb-set-all 00FF00
.build/debug/gmk67 rgb-clear
```

Save or restore the current RGB table:

```sh
.build/debug/gmk67 rgb-save rgb-current.hex
.build/debug/gmk67 rgb-restore rgb-current.hex
.build/debug/gmk67 rgb-file-dump rgb-current.hex
.build/debug/gmk67 rgb-file-dump rgb-current.hex --json
.build/debug/gmk67 rgb-file-map rgb-current.hex rgb-wasd.hex W=FF0000 A=00FF00 S=0000FF D=00FFFF
.build/debug/gmk67 rgb-restore-dry-run rgb-wasd.hex
.build/debug/gmk67 rgb-restore rgb-wasd.hex
.build/debug/gmk67 rgb-backups
.build/debug/gmk67 rgb-restore-latest
```

`rgb-file-map` and `rgb-file-dump` are offline helpers: they do not open HID.
Use `--json` with `rgb-dump` or `rgb-file-dump` when an app/editor needs the
decoded per-key records. RGB table files must contain 8 or 9 lines of 64 hex
bytes, which prevents accidentally passing a keymap export to `rgb-restore`.
`rgb-restore` validates the file before opening HID; use `rgb-restore-dry-run`
when you want the same validation and record summary without touching the
keyboard.

Mutating RGB commands create hidden `.gmk67-rgb-backup-*.hex` files in the
current working directory. `rgb-backups [directory]` lists valid automatic
backups without opening HID. `rgb-restore-latest [--directory=path]` restores
the newest valid backup using the same validation and pre-restore backup logic
as `rgb-restore`.

Create a fresh RGB profile file without reading the keyboard first:

```sh
.build/debug/gmk67 rgb-profile-create rgb-wasd.hex --fill=000000 W=FF0000 A=00FF00 S=0000FF D=00FFFF
.build/debug/gmk67 rgb-restore-dry-run rgb-wasd.hex
.build/debug/gmk67 rgb-restore rgb-wasd.hex
```

`rgb-profile-create` starts from a zeroed 9-frame RGB table. `--fill=rrggbb`
sets all known physical keys to a base color, then any `key=rrggbb`
assignments override individual keys. The output is the same validated RGB
table format used by `rgb-restore`.

List, export, or apply built-in RGB lighting presets:

```sh
.build/debug/gmk67 rgb-preset-list
.build/debug/gmk67 rgb-preset-show wasd --json
.build/debug/gmk67 rgb-preset-create wasd-rgb.hex wasd
.build/debug/gmk67 rgb-preset-apply wasd
```

Built-in RGB presets currently include `off`, `white`, `red`, `blue`, `wasd`,
`arrows`, `coding`, `rainbow`, `ocean`, and `sunset`. Applying a preset uses
the proven RGB table write path and saves an automatic pre-write backup.

Create a combined keyboard profile that stores both a lighting preset and a
keymap preset:

```sh
.build/debug/gmk67 profile-create gaming.json --name=Gaming --rgb=wasd --keymap=wasd-arrows
.build/debug/gmk67 profile-validate gaming.json
.build/debug/gmk67 profile-apply gaming.json --unsafe-no-backup
```

Use `--keymap=none` for RGB-only profiles. Applying an RGB-only profile uses
the proven RGB write path and creates an automatic RGB backup. Applying a
profile that includes a keymap preset is guarded by `--unsafe-no-backup`
because keymap readback/backup is still not proven.

Combined profiles can also store custom per-key RGB assignments and custom
remaps in one JSON file:

```sh
.build/debug/gmk67 profile-create custom.json --name=Custom --rgb=off --keymap=none --rgb-fill=000000 W=FF0000 A=00FF00 --remap=W=up --remap=A=left
.build/debug/gmk67 profile-validate custom.json
.build/debug/gmk67 profile-show custom.json --json
.build/debug/gmk67 profile-preview custom.json
.build/debug/gmk67 profile-export custom.json custom-artifacts
.build/debug/gmk67 profile-apply custom.json --unsafe-no-backup
.build/debug/gmk67 profile-preview-spec --name=Custom --rgb=off --keymap=none --rgb-fill=000000 W=FF0000 --remap=W=up
.build/debug/gmk67 profile-export-spec custom-artifacts --name=Custom --rgb=off --keymap=none --rgb-fill=000000 W=FF0000 --remap=W=up
.build/debug/gmk67 profile-apply-spec --name=Custom --rgb=off --keymap=none --rgb-fill=000000 W=FF0000 --remap=W=up --unsafe-no-backup
```

Custom RGB fields use the same `key=rrggbb` format as `rgb-map`. Custom keymap
fields use `--remap=source=target[:modifier]` and share the same guarded write
path as keymap presets. `profile-preview` and `profile-export` are offline:
they do not open HID. Export writes `<prefix>-rgb.hex` and, when the profile has
keymap changes, `<prefix>-keymap.hex`. `profile-show --json` is intended for
frontends that load profile files back into an editor. `profile-preview-spec`,
`profile-export-spec`, and `profile-apply-spec` let frontends preview, export,
or apply the current editor state without first writing a profile JSON file.

Built-in whole-keyboard profile presets combine RGB and optional keymap presets:

```sh
.build/debug/gmk67 profile-preset-list
.build/debug/gmk67 profile-preset-show gaming --editor-json
.build/debug/gmk67 profile-preset-create gaming.json gaming
.build/debug/gmk67 profile-preset-apply gaming --unsafe-no-backup
```

Preset apply uses the same safety rules as `profile-apply`: RGB-only presets do
not need the unsafe flag, while presets containing key remaps do.
`profile-preset-show --editor-json` expands a built-in preset into editable
RGB fill/assignment and key-remap fields for app frontends.

Save app-local profiles by name under `~/Library/Application Support/GMK67/Profiles`
or an explicit library directory:

```sh
.build/debug/gmk67 profile-library-create --name=Gaming --rgb=wasd --keymap=wasd-arrows
.build/debug/gmk67 profile-library-save custom.json --slot=custom
.build/debug/gmk67 profile-library-list
.build/debug/gmk67 profile-library-preview gaming
.build/debug/gmk67 profile-library-show gaming --json
.build/debug/gmk67 profile-library-export gaming exported/gaming
.build/debug/gmk67 profile-library-apply gaming --unsafe-no-backup
.build/debug/gmk67 profile-library-delete gaming
.build/debug/gmk67 profile-library-bundle-export gmk67-profile-library.json
.build/debug/gmk67 profile-library-bundle-import gmk67-profile-library.json
```

Pass `--directory=path` to any `profile-library-*` command to use a portable
profile folder. `profile-library-list --json` emits a machine-readable list for
frontends. The app's Keyboard Profile panel exposes the same library save, list,
refresh, load, preview, export, apply, delete, backup, and restore actions.
The bundle commands save or restore the whole app profile library as one JSON
file; they do not open HID.

Create and manage app-local macro profiles:

```sh
.build/debug/gmk67 macro-create combo.json --name=Combo --repeat=2 down:control key:C up:control delay:50
.build/debug/gmk67 macro-validate combo.json
.build/debug/gmk67 macro-show combo.json --json
.build/debug/gmk67 macro-library-create --slot=copy --name=Copy down:control key:C up:control
.build/debug/gmk67 macro-library-save combo.json --slot=combo
.build/debug/gmk67 macro-library-list
.build/debug/gmk67 macro-library-show combo --json
.build/debug/gmk67 macro-library-delete combo
.build/debug/gmk67 macro-library-bundle-export gmk67-macro-library.json
.build/debug/gmk67 macro-library-bundle-import gmk67-macro-library.json
```

Macro events are `key:A` for a tap, `down:A`, `up:A`, `delay:50`, and
`text:hello`. Pass `--directory=path` to any `macro-library-*` command to use a
portable macro folder. The app's Macro panel exposes create, validate, load,
save, import, refresh, load saved, list, delete, backup, and restore actions.
These macro files are validated app/software artifacts only. The Windows app
exposes Macro Manager, but the firmware macro storage/writeback protocol has
not been mapped yet, so no macro command writes HID reports.

Build a candidate simple key-remap payload without sending anything to the
keyboard:

```sh
.build/debug/gmk67 keymap-dry-run A B
.build/debug/gmk67 keymap-dry-run A B shift
.build/debug/gmk67 keymap-clear-dry-run
.build/debug/gmk67 keymap-export keymap-A-to-B.hex A B
.build/debug/gmk67 keymap-clear-export keymap-clear.hex
.build/debug/gmk67 keymap-map-dry-run A=B Caps=esc W=up:shift
.build/debug/gmk67 keymap-map-export keymap-wasd.hex W=up A=left S=down D=right
.build/debug/gmk67 keymap-sequence-validate keymap-wasd.hex
.build/debug/gmk67 keymap-sequence-validate keymap-wasd.hex --json
```

This is intentionally non-mutating. It prints the inferred `04 18`, `04 11`,
nine table chunks, `04 02`, `04 F0` sequence for inspection while the keymap
write path is still being validated. The table buffer is declared as `0x2B6`
bytes in the Windows app, but its wrapper sends the first nine 64-byte reports,
ending with the `AA 55` marker. Export files contain one 64-byte feature-report
payload per line and can be validated or compared before any live HID write.

Multi-remap specs use `source=target` or `source=target:modifier`. Names come
from `dump-layout`; one-byte HID usages such as `0x04` are also accepted. Since
keymap writes replace the full custom-keymap table, use `keymap-map-*` when you
want more than one remap active at the same time.
Use `keymap-sequence-validate --json` when an app/editor needs to load an
exported keymap profile back into editable `source=target[:modifier]` specs.

Experimental keymap writes are available, but intentionally require an explicit
unsafe flag because no keymap readback/backup path has been proven yet:

```sh
.build/debug/gmk67 keymap-apply A B --unsafe-no-backup
.build/debug/gmk67 keymap-apply A B shift --unsafe-no-backup
.build/debug/gmk67 keymap-map-apply A=B Caps=esc --unsafe-no-backup
.build/debug/gmk67 keymap-file-apply keymap-wasd.hex --unsafe-no-backup
.build/debug/gmk67 keymap-clear --unsafe-no-backup
```

`keymap-apply` writes a full custom-keymap table containing only the requested
simple remap, so it may replace other custom remaps. `keymap-clear` writes the
same table shape with no remap records and is expected to clear custom remaps.
Both commands accept `--write-index=N` if the scanned HID interface ordering is
different from the tested USB board.

For reusable keymap profiles, you can either keep low-level `.hex` feature
sequence files or use app-local JSON keymap profiles. JSON profiles preserve the
editable `source=target[:modifier]` specs and can be exported to `.hex` later:

```sh
.build/debug/gmk67 keymap-map-export keymap-wasd.hex W=up A=left S=down D=right
.build/debug/gmk67 keymap-sequence-validate keymap-wasd.hex
.build/debug/gmk67 keymap-file-apply keymap-wasd.hex --unsafe-no-backup
.build/debug/gmk67 keymap-profile-create wasd.json --name="WASD Arrows" W=up A=left S=down D=right
.build/debug/gmk67 keymap-profile-validate wasd.json
.build/debug/gmk67 keymap-profile-show wasd.json --json
.build/debug/gmk67 keymap-profile-export wasd.json wasd.hex
.build/debug/gmk67 keymap-profile-apply wasd.json --unsafe-no-backup
.build/debug/gmk67 keymap-library-create --slot=wasd --name="WASD Arrows" W=up A=left S=down D=right
.build/debug/gmk67 keymap-library-list
.build/debug/gmk67 keymap-library-show wasd --json
.build/debug/gmk67 keymap-library-export wasd wasd.hex
.build/debug/gmk67 keymap-library-apply wasd --unsafe-no-backup
.build/debug/gmk67 keymap-library-bundle-export gmk67-keymap-library.json
.build/debug/gmk67 keymap-library-bundle-import gmk67-keymap-library.json
```

The app's Keymap panel exposes the same keymap library save, import, refresh,
load, export, apply, list, delete, backup, and restore actions. Keymap library
commands that only create, validate, export, or list profiles do not open HID.
Applying a keymap JSON profile still requires `--unsafe-no-backup` for the same
reason as applying a `.hex` keymap sequence.

Built-in keymap presets provide common remaps:

```sh
.build/debug/gmk67 keymap-preset-list
.build/debug/gmk67 keymap-preset-show wasd-arrows --json
.build/debug/gmk67 keymap-preset-export wasd-arrows.hex wasd-arrows
.build/debug/gmk67 keymap-preset-apply wasd-arrows --unsafe-no-backup
```

Built-in keymap presets currently include `caps-esc`, `wasd-arrows`,
`vim-arrows`, `gaming-layer`, `editing-shortcuts`, `function-row`, and
`navigation-cluster`.

Shortcut presets use the same `source=target:modifier` syntax as custom
multi-remaps. For example, `editing-shortcuts` maps keys in the navigation
cluster to Control-C, Control-V, Control-Z, and Control-Y style shortcuts.

`keymap-file-apply` validates the file before opening HID, but it is still an
unsafe keymap write because the board-side keymap readback/backup path is not
known yet.

Build and validate a candidate custom-lighting RGB payload without sending it:

```sh
.build/debug/gmk67 lighting-custom-rgb-export custom-lighting.hex W=FF0000 A=00FF00 S=0000FF D=00FFFF
.build/debug/gmk67 lighting-custom-rgb-validate custom-lighting.hex
.build/debug/gmk67 lighting-custom-rgb-validate custom-lighting.hex --json
.build/debug/gmk67 lighting-custom-rgb-apply custom-lighting.hex --unsafe-no-backup
```

This models the Windows driver's `04 18`, `04 23` byte 8 `09`, nine table
chunks, `04 02`, `04 F0` path found in `DeviceDriver.exe`. The apply command
validates the file first and is guarded because a lighting readback/restore path
is not known.

Build and validate the shorter candidate lighting-mode table branch:

```sh
.build/debug/gmk67 lighting-mode-export lighting-mode.hex W=01 A=02 S=03 D=04
.build/debug/gmk67 lighting-mode-preset-list
.build/debug/gmk67 lighting-mode-preset-export wasd-mode.hex wasd-steps
.build/debug/gmk67 lighting-effect-list
.build/debug/gmk67 lighting-effect-export breath-effect.hex breath
.build/debug/gmk67 lighting-effect-apply breath --unsafe-no-backup
.build/debug/gmk67 lighting-mode-validate lighting-mode.hex
.build/debug/gmk67 lighting-mode-validate lighting-mode.hex --json
.build/debug/gmk67 lighting-mode-preset-apply wasd-steps --unsafe-no-backup
.build/debug/gmk67 lighting-mode-apply lighting-mode.hex --unsafe-no-backup
```

This models the `04 23` byte 8 `03` path with a declared `0x100`-byte table,
three 64-byte table chunks, and `AA 55` at table offset `0xBE`. Table entries
are still raw one-byte values because their UI meaning is not fully mapped yet.
`lighting-mode-preset-*` commands are named raw selector-03 table patterns for
controlled testing, not proof of the exact Windows UI effect semantics. Apply
commands are guarded for the same reason as custom-lighting RGB apply.
`lighting-effect-*` commands use effect names discovered in the Windows English
language resource, such as `static`, `breath`, `spectrum`, `ripples`,
`flowing`, and `led-off`. They generate selector-03 tables that set every known
physical key to the candidate effect value, so they are useful test artifacts
but still not a proven high-level firmware mode command.
Use the `--json` validation forms when the app/editor needs to load exported
candidate lighting artifacts back into editable specs.

Build and validate the alternate `04 27` full-table artifact:

```sh
.build/debug/gmk67 alternate-table-export alternate-table.hex W=up A=left S=down D=right
.build/debug/gmk67 alternate-table-validate alternate-table.hex
.build/debug/gmk67 alternate-table-validate alternate-table.hex --json
.build/debug/gmk67 alternate-table-apply alternate-table.hex --unsafe-no-backup
```

This uses the same simple remap record encoder as the guarded keymap path, but
selects the Windows driver's alternate `04 27` operation with declared table
length `0x2AC`. It is exported only for protocol comparison and remains
guarded for live tests.
Use `alternate-table-validate --json` when the app/editor needs to load an
exported alternate-table artifact back into editable remap specs.

Recommended physical keymap test workflow:

```sh
.build/debug/gmk67 keymap-export keymap-A-to-B.hex A B
.build/debug/gmk67 keymap-clear-export keymap-clear.hex
.build/debug/gmk67 keymap-sequence-validate keymap-A-to-B.hex
.build/debug/gmk67 keymap-apply A B --unsafe-no-backup
# test whether A now produces B
.build/debug/gmk67 keymap-clear --unsafe-no-backup
```

Run or export a modeled factory reset:

```sh
.build/debug/gmk67 factory-reset-dry-run
.build/debug/gmk67 factory-reset-export factory-reset
.build/debug/gmk67 factory-reset --unsafe-no-backup
```

This is not a discovered vendor factory-reset opcode. It composes the modeled
operations available today: clear all known physical RGB records through the
RGB table path, and write the empty custom-keymap table. The live command saves
an RGB backup before writing and remains guarded because keymap backup/readback
is not proven.

## Current Status

Implemented:

- Native macOS app bundle with GUI access to common driver workflows and an
  advanced command runner for the full CLI surface.
- macOS HID enumeration for the GMK67 vendor-defined configuration interface.
- Broader VID/PID scanning for alternate GMK67 interface descriptors.
- Automatic preference for the 64-byte wired configuration interface.
- Vendor layout loading from the extracted Windows installer data.
- Built-in offline self-test for parser, RGB table, and keymap sequence
  regression checks.
- Read-only doctor command for resource checks, USB interface discovery, and
  optional macOS HID open-permission diagnostics.
- Read-only diagnostics report export for app/CLI support and protocol notes.
- Read-only protocol-candidates report for proven RGB commands and unproven
  lighting/profile opcode families found in the Windows driver.
- Raw feature-report read/write plumbing for protocol probing.
- Read-only feature-report ID scanner.
- Passive input-report listener for matching the Windows app's `ReadFile`
  readback path.
- Targeted RGB readback probe using the Windows app's `04 F5` request shape.
- Experimental single-key RGB write probe using the Windows app's `04 20`,
  table chunks, `04 02` sequence.
- RGB table save/restore helpers for reversible probing.
- Automatic RGB backup listing and newest-backup restore helper.
- High-level RGB commands for one key, all known physical keys, and clearing
  known physical keys.
- Multi-key RGB writes and offline saved-table editing/dumping helpers.
- Fresh RGB profile file creation with optional fill color and per-key
  overrides.
- Built-in RGB lighting presets for common static profiles.
- Automatic pre-write RGB table backups for mutating RGB commands.
- Non-writing keymap remap payload builder for protocol validation.
- Offline keymap sequence export for review before physical testing.
- Offline keymap sequence validation for exported keymap reports.
- Multi-remap keymap table generation for dry-run, export, and guarded apply.
- Built-in keymap remap presets for common layouts.
- Guarded keymap profile file apply after offline sequence validation.
- App-local keymap JSON profile creation, import/export, backup/restore, and
  library management.
- Guarded experimental keymap apply/clear commands that require
  `--unsafe-no-backup`.
- Offline custom-lighting RGB sequence export/validation for the `04 23`
  extended lighting path.
- Offline lighting-mode table sequence export/validation for the `04 23`
  selector-03 path, including named candidate presets.
- Windows-named candidate lighting-effect exports for the selector-03 table
  path, surfaced in the app Lighting panel.
- Offline alternate full-table sequence export/validation for the `04 27`
  path.
- Guarded apply commands for validated candidate lighting/full-table sequences.
- Modeled factory reset dry-run/export/live command that clears RGB and custom
  keymap state through known table paths.
- App-local profile library backup/restore as a portable JSON bundle.
- App-local macro profile creation, validation, import, backup/restore, and
  library management.
- Whole-app library backup/restore for profiles, keymaps, and macros in one
  validated portable JSON bundle.

Still being reverse-engineered:

- Safe keymap readback/backup commands.
- Live RGB mode/per-key lighting commands.
- Unknown onboard profile-slot save/load commands, if the firmware exposes any.
- Board-side macro storage/write commands.

Use wired USB mode while probing; Bluetooth mode normally does not expose the
vendor configuration HID interface.

## macOS HID Permission

If `feature-get` or `feature-set` returns `not permitted`, macOS is blocking
keyboard HID access. Grant Input Monitoring permission to the terminal/Codex
host app in System Settings, then unplug/replug the GMK67 and retry:

```sh
.build/debug/gmk67 feature-get 00 64
```

When using `GMK67.app`, grant Input Monitoring permission to the app if macOS
prompts or if app commands report `not permitted`. The bundled helper is inside
`GMK67.app/Contents/Resources/Helper/gmk67`, so macOS may show either the app
or the helper depending on how TCC attributes the HID open. The app's Device
panel has **Permission** and **Settings** buttons to request Input Monitoring
access and open the correct System Settings pane.

## Reverse Engineering Notes

The Windows vendor app uses `HidD_SetFeature` with a fixed length of `0x41`
bytes. On Windows this includes the report ID byte plus 64 bytes of payload.
The app leaves the report ID byte as zero and copies command payload bytes into
the following 64 bytes, so macOS writes should use report ID `00` with a
64-byte payload. The app also chunks larger transfers into 64-byte blocks.
