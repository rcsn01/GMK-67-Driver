import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func printUsage() {
    print("""
    gmk67 - macOS user-space driver tools for the Zuoya/BOYI GMK67

    Commands:
      list
          List the GMK67 vendor-defined HID configuration interface.

      scan
          List all HID interfaces with the GMK67 VID/PID.

      dump-layout
          Print the vendor key map from Resources/vendor/KeyboardLayout.xml.

      self-test
          Run offline parser, RGB table, and keymap sequence checks without HID.

      doctor [--open-check]
          Run read-only resource, protocol, and USB HID diagnostics.

      readiness [--open-check]
          Print a concise driver/app readiness report without sending HID reports.

      protocol-candidates
          Print proven and candidate vendor protocol command families without HID.

      windows-features
          Print the extracted Windows app feature inventory and implementation status without HID.

      validation-plan
          Print a read-only physical validation checklist without HID.

      diagnostics [path]
          Print or save a read-only diagnostics report without sending HID reports.

      support-bundle [directory]
          Write readiness, diagnostics, protocol, and layout reports into a support directory without sending HID reports.

      permission-status
          Check macOS Input Monitoring permission without opening HID.

      permission-request
          Request macOS Input Monitoring permission without sending HID reports.

      factory-reset-dry-run
          Preview the modeled reset artifacts without opening HID.

      factory-reset-export <output-prefix>
          Export modeled reset artifacts as <prefix>-rgb.hex and <prefix>-keymap-clear.hex.

      factory-reset \(unsafeKeymapFlag) [--write-index=N] [--read-index=N]
          Clear known physical RGB records and write an empty custom-keymap table.

      profile-create <path> [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Create a combined GMK67 profile JSON file without opening HID.

      profile-validate <path>
          Validate a combined GMK67 profile JSON file without opening HID.

      profile-preview <path>
          Render a combined profile's RGB and keymap changes without opening HID.

      profile-show <path> [--json]
          Show a combined profile, optionally as raw JSON for app editors.

      profile-preview-spec [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Preview an inline combined profile without creating a file or opening HID.

      profile-export-spec <output-prefix> [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Export inline profile artifacts without creating a profile JSON file.

      profile-apply-spec [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...] [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply an inline combined profile without creating a file. Keymap sections require \(unsafeKeymapFlag).

      profile-export <path> <output-prefix>
          Export composed profile artifacts as <prefix>-rgb.hex and optional <prefix>-keymap.hex.

      profile-apply <path> [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply a combined profile. Keymap sections require \(unsafeKeymapFlag).

      profile-preset-list
          List built-in whole-keyboard profile presets.

      profile-preset-show <preset-name> [--json|--editor-json]
          Show a built-in whole-keyboard profile preset without opening HID.
          --editor-json expands preset internals into editable RGB/remap fields.

      profile-preset-create <path> <preset-name>
          Create a combined GMK67 profile JSON file from a built-in preset.

      profile-preset-apply <preset-name> [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply a built-in whole-keyboard profile preset.

      profile-library-create [--directory=path] [--slot=name] [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Create or replace a named profile in the app-local profile library.

      profile-library-save <path> [--slot=name] [--directory=path]
          Validate and copy an existing profile JSON into the app-local profile library.

      profile-library-list [--directory=path] [--json]
          List saved app-local profiles.

      profile-library-preview <slot> [--directory=path]
          Preview a saved app-local profile without opening HID.

      profile-library-show <slot> [--directory=path] [--json]
          Show a saved app-local profile, optionally as raw JSON.

      profile-library-export <slot> <output-prefix> [--directory=path]
          Export saved app-local profile artifacts.

      profile-library-apply <slot> [--directory=path] [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply a saved app-local profile. Keymap sections require \(unsafeKeymapFlag).

      profile-library-delete <slot> [--directory=path]
          Delete a saved app-local profile.

      profile-library-bundle-export <path> [--directory=path]
          Export all saved app-local profiles to one portable JSON bundle.

      profile-library-bundle-import <path> [--directory=path]
          Validate and import a portable JSON profile library bundle.

      app-library-bundle-export <path> [--profiles=path] [--keymaps=path] [--macros=path]
          Export all app-local profile, keymap, and macro libraries to one JSON bundle.

      app-library-bundle-import <path> [--profiles=path] [--keymaps=path] [--macros=path]
          Validate and import a whole-app library bundle.

      macro-create <path> [--name=Name] [--repeat=N] <event ...>
          Create an app-local macro JSON file. Events: key:A, down:A, up:A, delay:50, text:hello.

      macro-validate <path>
          Validate a macro JSON file without opening HID.

      macro-show <path> [--json]
          Show a macro profile, optionally as raw JSON for app editors.

      macro-firmware-template <path> [chunk-count]
          Write a zeroed candidate 04 19 / 04 15 macro firmware table container without HID.

      macro-firmware-validate <path>
          Validate an exported candidate macro firmware table container without HID.

      macro-firmware-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported macro firmware table container.

      macro-library-create [--directory=path] [--slot=name] [--name=Name] [--repeat=N] <event ...>
          Create or replace a named macro in the app-local macro library.

      macro-library-save <path> [--slot=name] [--directory=path]
          Validate and copy an existing macro JSON into the app-local macro library.

      macro-library-list [--directory=path] [--json]
          List saved app-local macros.

      macro-library-show <slot> [--directory=path] [--json]
          Show a saved app-local macro.

      macro-library-delete <slot> [--directory=path]
          Delete a saved app-local macro.

      macro-library-bundle-export <path> [--directory=path]
          Export all saved app-local macros to one portable JSON bundle.

      macro-library-bundle-import <path> [--directory=path]
          Validate and import a portable JSON macro library bundle.

      feature-get <report-id-hex> <length-decimal>
          Read a raw feature report from the configuration interface.

      feature-get-at <config-index> <report-id-hex> <length-decimal>
          Read a raw feature report from a listed configuration interface.

      feature-scan [config-index] [start-report-id-hex] [end-report-id-hex] [length-decimal]
          Read-only scan for feature report IDs that return successfully.

      input-listen [config-index] [length-decimal] [seconds]
          Listen for interrupt input reports from a listed configuration interface.

      key-test [config-index] [length-decimal] [seconds]
          Listen for boot keyboard input reports and decode modifiers/keys.

      input-get-at <index> <report-id-hex> <length-decimal>
          Read a raw input report from any VID/PID interface shown by scan.

      feature-set <report-id-hex> <payload-hex>
          Write a raw feature report payload to the configuration interface.

      feature-set64 <report-id-hex> <payload-hex>
          Write a feature report payload padded with zeros to exactly 64 bytes.

      rgb-read-probe [write-index] [listen-index] [chunks] [seconds]
          Send the vendor RGB readback request and print returned input reports.

      rgb-read-get-probe [write-index] [read-index] [read-report-id-hex] [length] [chunks]
          Send the vendor RGB readback request, then call IOHIDDeviceGetReport(input).

      rgb-dump [write-index] [read-index] [chunks] [--json]
          Send the RGB readback request, read all chunks, and print non-zero records.

      rgb-set-key <key-name-or-light-index-hex> <rrggbb-hex> [write-index] [read-index]
          Save a backup, set one key in the RGB table, then read back the rendered table.

      rgb-map <key=rrggbb> [...] [--write-index=N] [--read-index=N]
          Save a backup, set multiple keys in one RGB table write, then read back.

      rgb-file-map <input.hex> <output.hex> <key=rrggbb> [...]
          Edit a saved RGB table file without opening HID.

      rgb-profile-create <path> [--fill=rrggbb] [key=rrggbb ...]
          Create a fresh RGB table profile file without opening HID.

      rgb-preset-list
          List built-in RGB lighting presets.

      rgb-preset-show <preset-name> [--json]
          Show a built-in RGB lighting preset without opening HID.

      rgb-preset-create <path> <preset-name>
          Create a fresh RGB table file from a built-in preset without opening HID.

      rgb-preset-apply <preset-name> [write-index] [read-index]
          Save a backup, apply a built-in RGB preset, then read back rendered RGB.

      effect-list
          List experimental animated lighting effect names with friendly aliases.

      effect-apply <effect-name>
          Refuse live apply and explain that animated effect selection is not proven yet.

      rgb-file-dump <path> [--json]
          Parse a saved RGB table file and print non-zero records without opening HID.

      rgb-set-all <rrggbb-hex> [write-index] [read-index]
          Save a backup, then set all physical keys from the vendor layout to one RGB color.

      rgb-clear [write-index] [read-index]
          Save a backup, then set all physical keys from the vendor layout to black/off.

      rgb-save <path> [write-index] [read-index]
          Save the current 9-frame RGB table to a hex text file.

      rgb-restore <path> [write-index] [read-index]
          Restore a saved RGB table file and read back the result.

      rgb-restore-dry-run <path>
          Validate and summarize an RGB table restore file without opening HID.

      rgb-backups [directory]
          List valid automatic RGB backup files without opening HID.

      rgb-restore-latest [--directory=path] [--write-index=N] [--read-index=N]
          Restore the newest valid automatic RGB backup file and read back the result.

      keymap-dry-run <source-key> <target-key-or-hid-hex> [modifier-key-or-hid-hex]
          Build and print the candidate simple-remap feature sequence without sending it.

      keymap-clear-dry-run
          Build and print the candidate empty custom-keymap sequence without sending it.

      keymap-export <path> <source-key> <target-key-or-hid-hex> [modifier-key-or-hid-hex]
          Write the candidate simple-remap feature sequence to a hex text file.

      keymap-clear-export <path>
          Write the candidate empty custom-keymap sequence to a hex text file.

      keymap-map-dry-run <source=target[:modifier]> [...]
          Build and print a custom-keymap table with multiple simple remaps.

      keymap-map-export <path> <source=target[:modifier]> [...]
          Write a multi-remap feature sequence to a hex text file.

      keymap-preset-list
          List built-in keymap remap presets.

      keymap-preset-show <preset-name> [--json]
          Show a built-in keymap remap preset without opening HID.

      keymap-preset-export <path> <preset-name>
          Write a built-in keymap preset sequence to a hex text file.

      keymap-preset-apply <preset-name> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a full custom-keymap table from a built-in preset.

      keymap-sequence-validate <path> [--json]
          Validate an exported keymap feature sequence and print non-zero records.

      keymap-file-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported keymap feature sequence file.

      keymap-profile-create <path> [--name=Name] <source=target[:modifier]> [...]
          Create an app-local keymap JSON profile without opening HID.

      keymap-profile-validate <path>
          Validate a keymap JSON profile without opening HID.

      keymap-profile-show <path> [--json]
          Show a keymap JSON profile, optionally as raw JSON for app editors.

      keymap-profile-export <profile.json> <output.hex>
          Export a keymap JSON profile to a validated feature sequence file.

      keymap-profile-apply <profile.json> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write a keymap JSON profile.

      keymap-library-create [--directory=path] [--slot=name] [--name=Name] <source=target[:modifier]> [...]
          Create or replace a named keymap profile in the app-local keymap library.

      keymap-library-save <profile.json> [--slot=name] [--directory=path]
          Validate and copy an existing keymap JSON profile into the app-local keymap library.

      keymap-library-list [--directory=path] [--json]
          List saved app-local keymap profiles.

      keymap-library-show <slot> [--directory=path] [--json]
          Show a saved app-local keymap profile.

      keymap-library-export <slot> <output.hex> [--directory=path]
          Export a saved app-local keymap profile to a feature sequence file.

      keymap-library-apply <slot> [--directory=path] \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write a saved app-local keymap profile.

      keymap-library-delete <slot> [--directory=path]
          Delete a saved app-local keymap profile.

      keymap-library-bundle-export <path> [--directory=path]
          Export all saved app-local keymap profiles to one portable JSON bundle.

      keymap-library-bundle-import <path> [--directory=path]
          Validate and import a portable JSON keymap library bundle.

      keymap-map-apply <source=target[:modifier]> [...] \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a full custom-keymap table containing multiple simple remaps.

      keymap-apply <source-key> <target-key-or-hid-hex> [modifier-key-or-hid-hex] \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a full custom-keymap table containing only this simple remap.

      keymap-clear \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write an empty custom-keymap table, likely clearing custom remaps.

      short-op-template <path> [empty|static-80]
          Write the candidate 04 13 short lighting/profile operation sequence without HID.

      short-op-validate <path>
          Validate an exported candidate 04 13 short operation sequence without HID.

      short-op-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported 04 13 short operation sequence.

      keyboard-settings-export <path> [--profile=byte] [field=byte|offset=byte ...]
          Write the candidate 04 17 keyboard/settings payload sequence without HID.
          Named fields: gamemode, disable-alttab, disable-altf4, disable-win,
          fn-switchfunction, sleep-light. Boolean fields accept on/off or 1/0.

      keyboard-settings-validate <path>
          Validate an exported candidate 04 17 keyboard/settings payload sequence without HID.

      keyboard-settings-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported 04 17 keyboard/settings sequence.

      lighting-custom-rgb-export <path> [--brightness=N|PCT%] [key=rrggbb ...]
          Write the candidate 04 23 custom-lighting RGB sequence to a file without HID.
          Brightness is applied like Windows before export: (channel * scale) >> 8,
          where N is 0...256 and 100% maps to 256.

      lighting-custom-rgb-validate <path> [--json]
          Validate an exported candidate custom-lighting RGB sequence without HID.

      lighting-custom-rgb-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported custom-lighting RGB sequence file.

      lighting-mode-export <path> [index=hexbyte ...]
          Write the candidate 04 23 selector-03 lighting-mode table sequence without HID.

      lighting-mode-preset-list
          List built-in candidate lighting-mode table presets.

      lighting-mode-preset-export <path> <preset-name>
          Write a built-in candidate lighting-mode table preset without HID.

      lighting-mode-preset-apply <preset-name> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a built-in candidate lighting-mode preset sequence.

      lighting-effect-list
          List Windows-named candidate lighting effects mapped to selector-03 values.

      lighting-effect-export <path> <effect-name>
          Write a Windows-named candidate lighting effect table without HID.

      lighting-effect-apply <effect-name> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a Windows-named candidate lighting effect sequence.

      lighting-mode-validate <path> [--json]
          Validate an exported candidate lighting-mode table sequence without HID.

      lighting-mode-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported lighting-mode sequence file.

      alternate-table-export <path> <source=target[:modifier]> [...]
          Write the candidate 04 27 alternate full-table sequence without HID.

      alternate-table-validate <path> [--json]
          Validate an exported candidate 04 27 alternate full-table sequence without HID.

      alternate-table-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported 04 27 alternate full-table sequence.

    Device target:
      VID 0x05AC, PID 0x024F, usage page 0xFFFF, usage 0x0001
    """)
}
