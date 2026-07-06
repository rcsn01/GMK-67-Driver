import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func inputMonitoringPermissionReport(request: Bool) -> String {
    var lines: [String] = []
    func add(_ line: String = "") {
        lines.append(line)
    }

    add("GMK67 macOS Input Monitoring permission")
    add("No HID reports are sent by this command.")
    add("Checked executable: \(Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "gmk67")")
    add("")

    let preflight = CGPreflightListenEventAccess()
    add("Current status: \(preflight ? "GRANTED" : "NOT GRANTED")")

    if request && !preflight {
        add("Requesting Input Monitoring access...")
        let granted = CGRequestListenEventAccess()
        add("Request result: \(granted ? "GRANTED" : "NOT GRANTED")")
    } else if request {
        add("Request skipped: permission is already granted.")
    }

    add("")
    add("If permission is not granted:")
    add("  1. Open System Settings > Privacy & Security > Input Monitoring.")
    add("  2. Enable the executable shown above, GMK67.app, or the terminal/Cursor/Codex host app, depending on what macOS lists.")
    add("  3. Quit and reopen the app or terminal, then unplug/replug the keyboard.")
    add("")
    add("Settings URL:")
    add("  x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")

    return lines.joined(separator: "\n") + "\n"
}
