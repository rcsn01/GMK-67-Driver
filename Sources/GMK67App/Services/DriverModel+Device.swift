import AppKit
import Foundation

@MainActor
extension DriverModel {
    func refreshDeviceStatusIfNeeded() {
        guard !didAutoRefreshDeviceStatus else { return }
        didAutoRefreshDeviceStatus = true
        refreshDeviceStatus(announce: false)
    }

    func refreshDeviceStatus(announce: Bool = true) {
        deviceStatusKind = .checking
        deviceStatusTitle = "Checking keyboard"
        deviceStatusDetail = "Reading USB and macOS permission status."
        runCapture(["readiness", "--open-check"], title: announce ? "Driver readiness" : nil) { text, status in
            self.updateDeviceStatus(from: text, exitStatus: status)
            if announce, !text.isEmpty {
                self.append(text)
            }
        }
    }

    private func updateDeviceStatus(from text: String, exitStatus: Int32) {
        if text.contains("Overall: READY") {
            deviceStatusKind = .ready
            deviceStatusTitle = "Keyboard ready"
            deviceStatusDetail = "USB and Input Monitoring permission are available for live RGB and keymap writes."
            return
        }

        if text.contains("USB device: OK") && text.contains("macOS HID open permission: FAIL") {
            deviceStatusKind = .permissionNeeded
            deviceStatusTitle = "Permission needed"
            deviceStatusDetail = "The GMK67 is connected, but macOS is blocking HID access. Use Permission to request access for the bundled helper, then quit/reopen and reconnect the keyboard."
            return
        }

        if text.contains("USB device: FAIL") || text.localizedCaseInsensitiveContains("not found") {
            deviceStatusKind = .disconnected
            deviceStatusTitle = "Keyboard not detected"
            deviceStatusDetail = "Connect the GMK67 by USB and refresh status."
            return
        }

        deviceStatusKind = .partial
        deviceStatusTitle = exitStatus == 0 ? "Partially ready" : "Status check failed"
        deviceStatusDetail = "Open the output log for details before running live writes."
    }

    func requestInputMonitoringPermission() {
        runCapture(["permission-request"], title: "macOS Input Monitoring permission") { text, status in
            guard status == 0 else { return }
            if text.contains("Current status: GRANTED") || text.contains("Request result: GRANTED") {
                self.refreshDeviceStatus(announce: false)
            } else {
                self.openInputMonitoringSettings()
            }
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            append("Could not build the Input Monitoring settings URL.")
            return
        }
        if NSWorkspace.shared.open(url) {
            append("Opened System Settings > Privacy & Security > Input Monitoring.")
        } else {
            append("Could not open System Settings. Open Privacy & Security > Input Monitoring manually.")
        }
    }
}
