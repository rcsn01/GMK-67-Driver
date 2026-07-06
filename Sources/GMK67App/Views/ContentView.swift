import SwiftUI

struct ContentView: View {
    @StateObject private var model = DriverModel()

    var body: some View {
        NavigationSplitView {
            List {
                Section("Device") {
                    ActionButton("Readiness", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                        model.run(["readiness"], title: "Driver readiness")
                    }
                    ActionButton("Doctor", systemImage: "stethoscope") {
                        model.run(["doctor"], title: "Read-only diagnostics")
                    }
                    ActionButton("Open Check", systemImage: "checkmark.shield") {
                        model.run(["doctor", "--open-check"], title: "macOS HID open permission")
                    }
                    ActionButton("Permission", systemImage: "lock.shield") {
                        model.requestInputMonitoringPermission()
                    }
                    ActionButton("Settings", systemImage: "gearshape") {
                        model.openInputMonitoringSettings()
                    }
                    ActionButton("List Interfaces", systemImage: "list.bullet.rectangle") {
                        model.run(["list"], title: "Configuration interfaces")
                    }
                    ActionButton("Dump Layout", systemImage: "keyboard") {
                        model.run(["dump-layout"], title: "Vendor layout")
                    }
                    ActionButton("Key Test", systemImage: "keyboard.badge.ellipsis") {
                        model.runLiveHID(["key-test", "0", "8", "10"], title: "Decoded key tester")
                    }
                    ActionButton("Protocol", systemImage: "doc.text.magnifyingglass") {
                        model.run(["protocol-candidates"], title: "Protocol candidates")
                    }
                    ActionButton("Test Plan", systemImage: "checklist") {
                        model.run(["validation-plan"], title: "Physical validation plan")
                    }
                    ActionButton("Save Report", systemImage: "square.and.arrow.down") {
                        model.saveDiagnosticsReport()
                    }
                    ActionButton("Support Bundle", systemImage: "folder.badge.gearshape") {
                        model.saveSupportBundle()
                    }
                    ActionButton("Factory Reset", systemImage: "exclamationmark.triangle") {
                        model.factoryReset()
                    }
                }

                Section("RGB") {
                    ActionButton("Dump RGB", systemImage: "tablecells") {
                        model.runLiveHID(["rgb-dump", "0", "0", "9"], title: "Current RGB table")
                    }
                    ActionButton("Save RGB", systemImage: "square.and.arrow.down") {
                        model.saveRGBProfile()
                    }
                    ActionButton("Restore RGB", systemImage: "square.and.arrow.up") {
                        model.restoreRGBProfile()
                    }
                    ActionButton("Backups", systemImage: "clock.arrow.circlepath") {
                        model.listRGBBackups()
                    }
                    ActionButton("Restore Latest", systemImage: "arrow.uturn.backward") {
                        model.restoreLatestRGBBackup()
                    }
                }

                Section("Profiles") {
                    ActionButton("Create", systemImage: "doc.badge.plus") {
                        model.createCombinedProfile()
                    }
                    ActionButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateCombinedProfile()
                    }
                    ActionButton("Apply", systemImage: "rectangle.stack.badge.play") {
                        model.applyCombinedProfile()
                    }
                }

                Section("Keymap") {
                    ActionButton("Validate File", systemImage: "doc.badge.gearshape") {
                        model.validateKeymapProfile()
                    }
                    ActionButton("Export Profile", systemImage: "doc.badge.plus") {
                        model.exportKeymapProfile()
                    }
                    ActionButton("Apply Profile", systemImage: "exclamationmark.triangle") {
                        model.applyKeymapProfile()
                    }
                }
            }
            .navigationTitle("GMK67")
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DeviceStatusBanner(model: model)
                        DevicePanel(model: model)
                        QuickPresetsPanel(model: model)
                        VisualKeyboardPanel(model: model)
                        ProfilePanel(model: model)
                        RGBPanel(model: model)
                        KeymapPanel(model: model)
                        MacroPanel(model: model)
                        LightingPanel(model: model)
                        AdvancedPanel(model: model)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                ConsoleView(text: model.output, isRunning: model.isRunning) {
                    model.clearOutput()
                }
                .frame(minHeight: 220)
            }
        }
        .task {
            model.refreshDeviceStatusIfNeeded()
        }
    }
}
