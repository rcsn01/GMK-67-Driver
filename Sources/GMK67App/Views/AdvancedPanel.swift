import SwiftUI

struct AdvancedPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Advanced") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("All Libraries")
                    CommandButton("Backup", systemImage: "externaldrive.badge.timemachine") {
                        model.exportAppLibraryBundle()
                    }
                    CommandButton("Restore", systemImage: "externaldrive.badge.plus") {
                        model.importAppLibraryBundle()
                    }
                    Text("Profiles, keymaps, and macros in one portable JSON bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("doctor", text: $model.advancedCommand)
                        .textFieldStyle(.roundedBorder)
                    CommandButton("Run", systemImage: "terminal") {
                        model.runAdvanced()
                    }
                }
                Text("Enter any helper command without the gmk67 prefix, for example: feature-scan 0 00 FF 64")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
