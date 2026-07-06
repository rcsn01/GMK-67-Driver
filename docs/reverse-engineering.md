# GMK67 Reverse-Engineering Notes

This repository includes three Windows GMK67 installers. They are Inno Setup
packages and can be unpacked without executing them.

The two Zuoya setup artifacts are byte-identical. The BOYI installer has
different branding/runtime files, but the protocol-relevant `DeviceDriver.exe`
paths checked for RGB writes match the Zuoya driver: the `HidD_SetFeature`
wrapper, the `04 23` custom-lighting table writer, and the follow-up `04 13`
activation routine all use the same HID report shapes.

Useful extracted files:

- `device.xml`: declares the target device as VID `05AC`, PID `024F`, product
  `USB DEVICE`, identify `RKGK890`.
- `KeyboardLayout.xml`: declares the 67-key logical layout, HID usage codes,
  key indices, and light indices.
- `DeviceDriver.exe`: MFC HID app. It uses `HidD_GetFeature`,
  `HidD_SetFeature`, raw HID enumeration, and an SQLite-backed profile store.
  Embedded SQLite strings define local profile tables such as `t_key_data`,
  `t_light_data`, `t_key_rgb_data`, `t_customlight_data`, and
  `t_customrgb_data`; those appear to back the Windows UI's saved profiles, but
  they are not evidence of a hardware keymap readback path.

Important current findings:

- The vendor app filters for HID path `vid_....&pid_....`.
- It opens the vendor-defined configuration interface, not the standard
  keyboard input interface.
- The configuration interface has HID usage page `0xFFFF` and usage `0x0001`.
- It verifies HID caps against usage page `0xFFFF` and usage `0x0001` before
  keeping a device handle.

Windows feature inventory:

- The shared Windows shell exposes driver management, language/settings,
  software update, firmware update, battery/status, auto-start, game mode, and
  factory reset UI.
- Keyboard panels include configuration profiles, import/export/copy/rename/
  delete, top layer and Fn layer editing, custom key assignment, light effect
  mode, custom lighting, and key light customization.
- Key assignment categories include disabled/default key functions, macro
  definition, mouse functions, multimedia, Windows shortcuts, open program,
  open website, send text, switch configuration, and multiple keys.
- Macro Manager exposes keyboard, mouse, delay, record/stop, repeat count,
  play-once, play-N-times, stop-when-pressed-again, and import/export flows.
- Lighting UI strings include Static, SingleOn, SingleOff, Glittering, Falling,
  Colourful, Breath, Spectrum, Outward, Scrolling, Rolling, Rotating, Explode,
  Launch, Ripples, Flowing, Pulsating, Tilt, Shuttle, LED Off, Inwards, and
  Floweriness, plus brightness, speed, direction, random/preset colors, light
  sleep time, select all, and reset selected.
- `DeviceDriver.exe` embeds SQLite table names for app-local state, including
  `t_configdata`, `t_light_data`, `t_key_rgb_data`, `t_keyprofile`,
  `t_key_data`, `t_macro_data`, `t_macrorecord`, `t_key_otherdata`,
  `t_customlight_data`, `t_customrgb_data`, `t_custommodergb_data`, and
  `t_musiclayer_data`.
- The extracted mouse/DPI/report-rate strings appear to come from the same
  generic driver shell. They are inventoried but not GMK67 keyboard firmware
  targets until a matching GMK67 HID path is found.

Current driver status:

- `gmk67 list` enumerates the exact GMK67 configuration interface on macOS.
- Wired USB connection exposes `USB DEVICE` from `hfd.cn` with a 64-byte
  feature-report interface.
- With the wired board and USB dongle both present, `gmk67 doctor` observed
  five matching HID interfaces. The wired board's 64-byte interface at scan
  index 0 remains the preferred RGB read/write target.
- `gmk67 dump-layout` prints the vendor key index/light index map.
- `gmk67 self-test` runs offline parser, RGB table, and keymap sequence
  regression checks without opening HID.
- `gmk67 readiness` is the concise app/driver readiness report. `gmk67 doctor`
  combines resource checks, offline protocol checks, and USB interface
  discovery without sending HID reports. `doctor --open-check` and
  `readiness --open-check` only open the likely configuration interface to
  verify macOS permission; they still do not send device reports.
- `gmk67 diagnostics [path]` prints or saves a read-only report containing
  resource checks, offline protocol status, USB interface discovery, protocol
  candidates, and safety notes. It does not open a keyboard interface or send
  reports.
- `gmk67 support-bundle [directory]` writes readiness, diagnostics, protocol,
  and layout reports into one support directory. It does not open a keyboard
  interface or send reports.
- `gmk67 permission-status` and `gmk67 permission-request` use macOS Input
  Monitoring APIs without opening HID, so users can resolve `not permitted`
  failures before live RGB/keymap writes.
- `gmk67 profile-library-*` commands keep named combined profile JSON files in
  the app-local profile library and reuse the same preview/export/apply
  pipeline as file-based profiles. `profile-library-bundle-export` and
  `profile-library-bundle-import` move the whole app-local library as one
  validated JSON bundle without opening HID.
- `gmk67 app-library-bundle-export` and `app-library-bundle-import` wrap the
  profile, keymap, and macro libraries into one validated whole-app JSON bundle
  for app backup/restore. They do not open HID.
- `gmk67 macro-*` and `macro-library-*` commands model the Windows app's Macro
  Manager as validated app-local JSON artifacts with key/down/up/delay/text
  events. `macro-library-bundle-export` and `macro-library-bundle-import` move
  the whole app-local macro library as one validated JSON bundle. `gmk67
  macro-firmware-template`, `macro-firmware-validate`, and
  `macro-firmware-apply` model the Windows macro firmware table container, but
  event-record encoding and readback are still unmapped; live writes remain
  guarded by `--unsafe-no-backup`.
- `GMK67.app` is a native macOS SwiftUI wrapper that bundles the same `gmk67`
  helper and exposes common device, RGB, keymap, and advanced driver commands.
  App-launched helper commands use `GMK67_RESOURCES_DIR` to load bundled vendor
  XML while writing backups/profile output under the user's Application Support
  directory instead of inside the app bundle. The app can also save the
  diagnostics report and support bundle through the Device panel, has buttons
  for requesting/opening Input Monitoring permission, and can save/list/preview/
  export/apply/delete named profiles through the Keyboard Profile panel.
- `gmk67 protocol-candidates` is a read-only report of proven RGB opcodes and
  unproven lighting/profile opcode families identified in `DeviceDriver.exe`.
- `gmk67 windows-features` is a read-only implementation-status inventory
  derived from the extracted Windows language resources, SQLite table strings,
  and disassembly notes.
- `gmk67 validation-plan` is a read-only physical test checklist for the next
  permission-granted validation session. It prints exact commands, rollback
  steps, and expected evidence without opening HID.
- `gmk67 feature-get` and `gmk67 feature-set` provide raw feature-report access
  for continuing protocol work without running the Windows vendor app.
- `gmk67 feature-scan 0 00 FF 64` performs a read-only scan for feature report
  IDs on the 64-byte wired interface.
- `gmk67 input-listen` passively listens for interrupt input reports. This is
  needed because the Windows app uses `ReadFile` for at least one readback
  path, not `HidD_GetFeature`.
- The Windows app calls `HidD_SetFeature` with length `0x41` and sends chunks
  copied from 64-byte source blocks into bytes 1...64 of the Windows report
  buffer. Byte 0 is the report ID slot required by Windows HID APIs.
- A read-only `feature-scan 0 00 FF 64` over USB returned success for all
  report IDs, but every 64-byte response was all zero. Passive feature reads are
  therefore not a useful discovery path for this board.
- Startup/keymap write sequences observed in `DeviceDriver.exe` use payload
  commands such as `04 18`, `04 11 ... 09`, a large keymap blob ending with
  `AA 55`, then `04 02` and `04 F0`.
- RGB/readback code sends `04 F5 ...` and then repeatedly reads 64-byte input
  reports with `ReadFile`.
- The observed RGB readback request is a 64-byte payload sent to feature report
  `00`: byte 0 `04`, byte 1 `F5`, byte 8 set to `03` or `09` for the expected
  chunk count. `gmk67 rgb-read-probe 0 1 3 2` starts an input listener and sends
  that request.
- On the tested USB board, `rgb-read-probe 0 1 3 2` produced no input reports on
  interface 1. `rgb-read-probe 0 0 3 2` produced only normal keyboard reports
  from manually typed keys. Next probes should check whether an explicit
  input-report read is required or whether the Windows app targets a different
  interface ordering than macOS.
- `rgb-read-get-probe 0 0 00 64 9` did return structured data. The response is
  read from scanned interface 0 with `IOHIDDeviceGetReport(input, report 00)`.
  Frames contain 16 four-byte records. The apparent format is
  `[index, red, green, blue]`; most records are zero RGB, while selected keys
  returned values such as `27 7B 3E 00`, `38 7B 7B 00`, `39 00 7B 00`, and
  `3A 00 7B 7B`.
- Response record indices match `light_index` from `KeyboardLayout.xml`. In the
  current captured table, non-zero records map to W (`0x27`), A/S/D
  (`0x38..0x3A`), and the arrow cluster (`0x63..0x66`).
- The matching Windows RGB table write path sends `04 20` first. On the tested
  board family, byte 8 is `08`, then the app sends eight 64-byte table chunks,
  then sends `04 02`. `gmk67 rgb-set-key` mirrors this sequence by reading the
  current nine-frame table, modifying one `[light_index, R, G, B]` record,
  writing the first eight frames, and verifying with `04 F5` readback.
- A physical write test with `gmk67 rgb-set-key W FF0000` changed the W key
  color. Readback did not echo raw `FF 00 00`; the device returned scaled or
  rendered values such as `FD 7F 00`, and many previously zero records expanded
  into active colors. Treat readback after writes as the device's rendered table,
  not necessarily the exact bytes sent.
- `gmk67 rgb-save` and `gmk67 rgb-restore` save/restore the 9-frame readback
  table to make future write probes reversible.
- `gmk67 rgb-backups` lists valid automatic `.gmk67-rgb-backup-*.hex` files
  without opening HID. `gmk67 rgb-restore-latest` restores the newest valid
  automatic backup through the same RGB table write path and first saves another
  pre-restore backup.
- `gmk67 rgb-map` applies multiple key/color records after one read and one
  automatic backup. `gmk67 rgb-file-map` and `rgb-file-dump` edit or inspect
  saved RGB tables offline without opening HID, which makes simple RGB profiles
  possible before restoring them to the board.
- `gmk67 rgb-profile-create` creates a fresh 9-frame RGB table offline. It
  starts from zeroed `[index, R, G, B]` records, optionally fills all mapped
  physical keys, then applies per-key overrides. The result can be checked with
  `rgb-restore-dry-run` and applied with `rgb-restore`.
- `gmk67 rgb-preset-*` commands are higher-level driver/app presets layered on
  the proven RGB table format. Applying one still uses the same `04 20` table
  write path and automatic pre-write backup.
- `gmk67 profile-preset-*` commands are app/driver convenience presets, not a
  separate vendor protocol family. They compose a named RGB preset with an
  optional named keymap preset; applying one uses the proven RGB table path
  first and only sends keymap reports when the preset includes a keymap and the
  caller passes `--unsafe-no-backup`.
- Combined profile JSON files can also include optional custom RGB fill,
  per-key RGB assignments, and custom keymap remaps. These fields are composed
  into the same RGB table and custom-key table formats already modeled by the
  lower-level commands; they are not separate vendor protocol commands.
  `profile-preview` and `profile-export` use only those local encoders and do
  not open HID.
- `gmk67 rgb-restore` validates the restore file before opening HID. The
  companion `rgb-restore-dry-run` command runs the same file parser and record
  summary without sending any reports.
- Mutating RGB commands now also write an automatic `.gmk67-rgb-backup-*.hex`
  backup before changing the table.

Keymap candidates:

- A candidate keymap-write routine starts near `0x4143f0`. It sends `04 18`,
  then `04 11` with byte 8 set to `09`, builds a large table, writes an `AA 55`
  marker, then sends `04 02` and `04 F0`.
- The keymap routine passes declared length `0x2B6` to the common feature-write
  wrapper at `0x449b80`. The wrapper's chunk loop shifts that length by six and
  subtracts one, so this call sends nine 64-byte table reports. The marker at
  table offset `0x23E` lands at bytes 62...63 of the ninth table report; trailing
  local zero bytes are not sent by this path.
- In that routine, simple key remaps appear to write four-byte records into a
  table indexed by the source key's vendor `key_index`: byte 0 `02`, byte 1
  encoded modifier mask, byte 2 encoded target HID usage, byte 3 `00`. HID
  modifier usages `E0...E7` are encoded as bit masks `01, 02, 04, ... 80`;
  other one-byte usages are stored directly. For example, a dry-run `A -> B`
  record is expected to be `02 00 05 00` at source key index `0x38`.
- A second candidate path near `0x41dcd0` sends `04 18`, then `04 23` with byte
  8 set to `03` or `09`, sends a large table, then finishes with `04 02` and
  `04 F0`.
- Another short operation near `0x41db30` sends `04 18`, `04 13`, a single
  command payload, then `04 02` and `04 F0`.
- A related helper at `0x41E050` uses the same `04 13` sequence, sets payload
  byte 0 to `80`, bytes 9...10 to `0F 0F`, and writes the same `AA 55` marker at
  payload offsets `0x0E...0x0F`.
- A keyboard/settings payload path at `0x426FB0` sends `04 18`, then `04 17`
  with byte 2 set from the Windows profile/current slot byte and byte 8 set to
  `01`, writes one 64-byte payload, places `AA 55` at payload offsets
  `0x3E...0x3F`, then commits with `04 02`. The payload appears to collect
  several local UI booleans and a string length, but the individual flag
  meanings are not proven.
- `gmk67 keymap-dry-run` builds and prints the candidate simple-remap feature
  sequence without opening the HID device or sending reports. This is for
  protocol validation only until a safe keymap readback/restore path is known.
- `gmk67 keymap-export` and `gmk67 keymap-clear-export` write the exact
  candidate report sequence to a hex text file without opening HID. Each line is
  one report-ID-0 payload. This gives us stable artifacts to diff before a
  physical write test.
- `gmk67 keymap-sequence-validate` checks an exported sequence offline: 13
  reports total, nine 64-byte table chunks, `04 18`, `04 11` byte 8 `09`,
  `AA 55` at table offset `0x23E`, then `04 02` and `04 F0`. It also prints
  non-zero table records with key names where the vendor layout maps them.
- `gmk67 keymap-map-dry-run`, `keymap-map-export`, and `keymap-map-apply` build
  one full custom-keymap table from multiple simple remap records using
  `source=target` or `source=target:modifier` specs. This matches the apparent
  full-table write semantics better than repeatedly applying one-key tables.
- `gmk67 keymap-preset-*` commands are named remap collections built with the
  same simple record encoder. Preset apply is guarded by `--unsafe-no-backup`
  for the same reason as all other keymap writes. Shortcut-oriented presets use
  the existing modifier byte in the same record shape and do not introduce a new
  protocol branch.
- `gmk67 keymap-profile-*` and `keymap-library-*` commands store editable
  `source=target[:modifier]` specs as app-local JSON profiles, then reuse the
  same full-table encoder when exporting or guarded-applying them.
  `keymap-library-bundle-export` and `keymap-library-bundle-import` move the
  whole app-local keymap library as one validated JSON bundle without opening
  HID.
- `gmk67 keymap-file-apply` validates an exported keymap sequence file with the
  same checks as `keymap-sequence-validate` before opening HID, then sends the
  validated reports. It still requires `--unsafe-no-backup` because there is no
  proven board-side keymap backup/readback path.
- `gmk67 keymap-apply` and `gmk67 keymap-clear` now expose the same sequence as
  guarded experimental writes requiring `--unsafe-no-backup`. `keymap-apply`
  writes a full custom-keymap table containing only the requested simple remap,
  so it should be treated as replacing the profile's custom-key table rather
  than patching one key in place. `keymap-clear` writes the same table with no
  custom records and is expected to clear custom remaps.
- These paths look like keymap/profile operations, but there is not yet a safe
  readback/backup path equivalent to RGB. Do not send candidate keymap writes
  casually; use the guarded write commands only for explicit physical tests.

Macro firmware candidate:

- A Windows path near `DeviceDriver.exe` VA `0x42042E` sends `04 19`, builds a
  variable-length macro table, sends `04 15` with byte 8 set to the table chunk
  count, sends that many 64-byte table reports, places `AA 55` in the final two
  table bytes, then commits with `04 02`.
- The observed empty/minimum path starts its working length at `0x190` and
  produces an eight-chunk transfer. `gmk67 macro-firmware-template` models this
  as a zeroed container with selector byte 8 set to `08` and `AA 55` at the end
  of the eighth table report.
- `gmk67 macro-firmware-validate` checks opcode order, selector chunk count,
  64-byte report sizes, and final marker placement. `macro-firmware-apply`
  validates before sending and remains guarded by `--unsafe-no-backup`.
- This is not yet a complete macro firmware writer. The Windows table is built
  from SQLite-backed macro/action records, but the exact per-event firmware
  record layout still needs mapping before app-local macro JSON can be compiled
  into board-side macro storage.

Lighting/profile candidates:

- A short operation at `DeviceDriver.exe` VA `0x41DB30` sends `04 18`, then
  `04 13` with byte 8 set to `01`, sends one payload containing an `AA 55`
  marker, then finishes with `04 02` and `04 F0`. `gmk67 short-op-template`,
  `short-op-validate`, and guarded `short-op-apply` now model this as a raw
  candidate container with `empty` and `static-80` template variants.
- A keyboard/settings operation at VA `0x426FB0` sends `04 18`, then `04 17`,
  one settings payload, and `04 02`. The surrounding load/apply routine at
  `0x426BE0...0x427168` reads Windows config keys `gamemode`,
  `disable_alttab`, `disable_altf4`, `disable_win`, `fn_switchfunction`, and
  `sleep_light`, then writes them to payload offsets `0x01...0x06` before the
  `AA 55` marker at offsets `0x3E...0x3F`. `gmk67 keyboard-settings-export`
  accepts those named fields plus raw payload assignments for offsets
  `0x00...0x3D`. `keyboard-settings-validate` checks the sequence and guarded
  `keyboard-settings-apply` sends only validated files.
- A custom lighting mode table path at VA `0x41DCD0` sends `04 18`, then
  `04 23` with byte 8 set to `03` or `09`, builds a per-key table with an
  `AA 55` marker, then finishes with `04 02` and `04 F0`. On return from the
  selector-09 custom RGB branch, Windows immediately calls the short operation
  routine at VA `0x41E050`, which sends `04 18`, `04 13` with byte 8 set to
  `01`, a `static-80` style payload, `04 02`, and `04 F0`. Selector-09 alone
  writes the custom table but does not match the full native apply sequence.
- The extended/custom-RGB branch of that `04 23` path checks a mode flag, sets
  selector byte 8 to `09`, writes a declared `0x280`-byte table through the
  same Windows chunk wrapper, and places `AA 55` at table offset `0x23E`.
  The wrapper sends nine 64-byte table reports, so the marker lands in bytes
  62...63 of the ninth table report. `gmk67 lighting-custom-rgb-export` and
  `lighting-custom-rgb-validate` now model this path offline.
  `lighting-custom-rgb-export --brightness=N|PCT%` models the Windows brightness
  behavior observed in the `04 20` static RGB writer at `0x4184F0...0x4187CB`:
  the driver scales each RGB channel as `(channel * scale) >> 8` before sending
  the table, rather than sending a separate brightness command. The MUI UI calls
  for `SetSpeed` (`0x5487E4`) and `SetBrightNess` (`0x5487A8`) update the local
  custom-light controls/SQLite-backed state; only brightness was found to feed a
  HID table, as pre-send RGB scaling. `lighting-custom-rgb-apply` validates the
  file first and remains guarded by `--unsafe-no-backup`.
- The shorter branch of `04 23` sets selector byte 8 to `03`, declares a
  `0x100`-byte table, and places `AA 55` at table offset `0xBE`. The wrapper
  sends three 64-byte table reports. `gmk67 lighting-mode-export` and
  `lighting-mode-validate` now model this shape offline with raw one-byte table
  assignments because the meaning of each UI value still needs more validation.
  `lighting-mode-preset-*` commands provide named raw table patterns for
  controlled testing. The Windows English language resource lists lighting
  effects `Static`, `SingleOn`, `SingleOff`, `Glittering`, `Falling`,
  `Colourful`, `Breath`, `Spectrum`, `Outward`, `Scrolling`, `Rolling`,
  `Rotating`, `Explode`, `Launch`, `Ripples`, `Flowing`, `Pulsating`, `Tilt`,
  `Shuttle`, `LED Off`, `Inwards`, and `Floweriness`; `lighting-effect-*`
  exports map those UI names to sequential selector-03 table byte values across
  all known physical keys for controlled physical tests. These are still
  candidate artifacts, not proof of the high-level firmware effect opcode.
  `lighting-mode-apply`, `lighting-mode-preset-apply`, and
  `lighting-effect-apply` validate or generate the sequence first and remain
  guarded by `--unsafe-no-backup`.
- An alternate full-table operation at VA `0x414BE0` sends `04 18`, then
  `04 27` with byte 8 set to `09`, writes a table through the same keymap-like
  record builder, then finishes with `04 02` and `04 F0`. The function declares
  a `0x2AC`-byte table, and the Windows chunk wrapper sends nine visible
  64-byte table reports. `gmk67 alternate-table-export` and
  `alternate-table-validate` model this shape offline using the existing simple
  remap record encoder. `alternate-table-apply` validates first and remains
  guarded by `--unsafe-no-backup`.
- These can plausibly overwrite lighting profiles or custom lighting state, so
  live writes remain guarded until a matching readback/restore path is known.
- `gmk67 factory-reset-*` is a modeled reset, not a discovered vendor reset
  opcode. It composes known table operations: RGB clear via the proven RGB table
  path plus an empty custom-keymap table via the guarded keymap path.

Current blocker:

- macOS returned `kIOReturnNotPermitted` when Codex opened the keyboard
  interface. Running the built binary from a terminal with Input Monitoring
  permission works; continue physical-device probes from that terminal.

The remaining protocol work is mapping high-level operations such as key
remapping, RGB mode changes, per-key lighting, macro event records inside the
now-modeled macro firmware container, device-side profile save/load, and any
true vendor factory-reset opcode to feature reports.
