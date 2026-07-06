import SwiftUI

struct DevicePanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Device") {
            HStack {
                CommandButton("Refresh", systemImage: "arrow.clockwise") {
                    model.refreshDeviceStatus()
                }
                CommandButton("Readiness", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    model.run(["readiness"], title: "Driver readiness")
                }
                CommandButton("Doctor", systemImage: "stethoscope") {
                    model.run(["doctor"], title: "Read-only diagnostics")
                }
                CommandButton("Open Check", systemImage: "checkmark.shield") {
                    model.run(["doctor", "--open-check"], title: "macOS HID open permission")
                }
                CommandButton("Permission", systemImage: "lock.shield") {
                    model.requestInputMonitoringPermission()
                }
                CommandButton("Settings", systemImage: "gearshape") {
                    model.openInputMonitoringSettings()
                }
                CommandButton("List", systemImage: "list.bullet.rectangle") {
                    model.run(["list"], title: "Configuration interfaces")
                }
                CommandButton("Self Test", systemImage: "checkmark.seal") {
                    model.run(["self-test"], title: "Offline self-test")
                }
                CommandButton("Key Test", systemImage: "keyboard.badge.ellipsis") {
                    model.runLiveHID(["key-test", "0", "8", "10"], title: "Decoded key tester")
                }
                CommandButton("Protocol", systemImage: "doc.text.magnifyingglass") {
                    model.run(["protocol-candidates"], title: "Protocol candidates")
                }
                CommandButton("Test Plan", systemImage: "checklist") {
                    model.run(["validation-plan"], title: "Physical validation plan")
                }
                CommandButton("Save Report", systemImage: "square.and.arrow.down") {
                    model.saveDiagnosticsReport()
                }
                CommandButton("Support Bundle", systemImage: "folder.badge.gearshape") {
                    model.saveSupportBundle()
                }
            }
        }
    }
}
