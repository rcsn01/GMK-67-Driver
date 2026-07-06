import SwiftUI

struct DeveloperToolsPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Quick Actions") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
                CommandButton("Dump RGB", systemImage: "tablecells") {
                    model.runLiveHID(["rgb-dump", "0", "0", "9"], title: "Current RGB table")
                }
                CommandButton("Doctor", systemImage: "stethoscope") {
                    model.run(["doctor"], title: "Read-only diagnostics")
                }
                CommandButton("List Interfaces", systemImage: "list.bullet.rectangle") {
                    model.run(["list"], title: "Configuration interfaces")
                }
                CommandButton("Dump Layout", systemImage: "keyboard") {
                    model.run(["dump-layout"], title: "Vendor layout")
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
                CommandButton("Factory Reset", systemImage: "exclamationmark.triangle") {
                    model.factoryReset()
                }
            }
        }
    }
}
