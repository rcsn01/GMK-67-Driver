import SwiftUI

private struct QuickRGBLayout: Identifiable {
    let name: String
    let label: String
    var id: String { name }
}

private struct QuickRGBTheme: Identifiable {
    let name: String
    let label: String
    let swatches: [Color]
    var id: String { name }
}

struct QuickPresetsPanel: View {
    @ObservedObject var model: DriverModel

    private let layouts: [QuickRGBLayout] = [
        QuickRGBLayout(name: "all", label: "All Keys"),
        QuickRGBLayout(name: "wasd", label: "WASD"),
        QuickRGBLayout(name: "arrows", label: "Arrows"),
        QuickRGBLayout(name: "coding", label: "Coding"),
        QuickRGBLayout(name: "rows", label: "Rows")
    ]

    private let themes: [QuickRGBTheme] = [
        QuickRGBTheme(name: "off", label: "Off", swatches: [.black]),
        QuickRGBTheme(name: "white", label: "White", swatches: [.white]),
        QuickRGBTheme(name: "red", label: "Red", swatches: [.red]),
        QuickRGBTheme(name: "green", label: "Green", swatches: [.green]),
        QuickRGBTheme(name: "blue", label: "Blue", swatches: [.blue]),
        QuickRGBTheme(name: "purple", label: "Purple", swatches: [Color(red: 0.5, green: 0, blue: 1)]),
        QuickRGBTheme(name: "cyan", label: "Cyan", swatches: [.cyan]),
        QuickRGBTheme(name: "orange", label: "Orange", swatches: [.orange]),
        QuickRGBTheme(name: "yellow", label: "Yellow", swatches: [.yellow]),
        QuickRGBTheme(name: "pink", label: "Pink", swatches: [Color(red: 1, green: 0.18, blue: 0.54)]),
        QuickRGBTheme(name: "gold", label: "Gold", swatches: [Color(red: 1, green: 0.69, blue: 0)]),
        QuickRGBTheme(name: "rainbow", label: "Rainbow", swatches: [.red, .yellow, .green, .blue, .purple]),
        QuickRGBTheme(name: "ocean", label: "Ocean", swatches: [Color(red: 0, green: 0.12, blue: 0.24), .cyan, .blue]),
        QuickRGBTheme(name: "sunset", label: "Sunset", swatches: [Color(red: 0.17, green: 0.06, blue: 0.16), .orange, .red]),
        QuickRGBTheme(name: "fire", label: "Fire", swatches: [Color(red: 0.23, green: 0.04, blue: 0), .red, .orange, .yellow]),
        QuickRGBTheme(name: "ice", label: "Ice", swatches: [Color(red: 0.01, green: 0.11, blue: 0.2), .cyan, .white]),
        QuickRGBTheme(name: "forest", label: "Forest", swatches: [Color(red: 0.02, green: 0.14, blue: 0.05), .green, .yellow]),
        QuickRGBTheme(name: "matrix", label: "Matrix", swatches: [.black, Color(red: 0, green: 1, blue: 0.25)]),
        QuickRGBTheme(name: "aurora", label: "Aurora", swatches: [Color(red: 0.02, green: 0.04, blue: 0.15), .green, .teal, .purple]),
        QuickRGBTheme(name: "cyberpunk", label: "Cyberpunk", swatches: [Color(red: 0.08, green: 0, blue: 0.12), Color(red: 1, green: 0.18, blue: 0.54), .cyan]),
        QuickRGBTheme(name: "pastel", label: "Pastel", swatches: [Color(red: 0.18, green: 0.14, blue: 0.25), Color(red: 1, green: 0.76, blue: 0.89), Color(red: 0.76, green: 1, blue: 0.85)]),
        QuickRGBTheme(name: "lava", label: "Lava", swatches: [Color(red: 0.16, green: 0, blue: 0), .orange, .yellow])
    ]

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8)]

    var body: some View {
        Panel("RGB Preset") {
            VStack(alignment: .leading, spacing: 12) {
                ControlGrid {
                    Text("Preset")
                    Picker("", selection: $model.rgbPresetName) {
                        ForEach(layouts) { layout in
                            Text(layout.label).tag(layout.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Text("Theme")
                    Picker("", selection: $model.rgbThemeName) {
                        ForEach(themes) { theme in
                            Text(theme.label).tag(theme.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    CommandButton("Apply", systemImage: "paintpalette") {
                        model.applyRGBLayoutTheme()
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(themes) { theme in
                        Button {
                            model.rgbThemeName = theme.name
                            model.applyRGBLayoutTheme()
                        } label: {
                            HStack(spacing: 6) {
                                HStack(spacing: 2) {
                                    ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, swatch in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(swatch)
                                            .frame(width: 10, height: 10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 2)
                                                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                                            )
                                    }
                                }
                                Text(theme.label)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    CommandButton("Undo (Restore Backup)", systemImage: "arrow.uturn.backward") {
                        model.restoreLatestRGBBackup()
                    }
                    Text("Apply uses the selected preset layout with the selected color theme.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.deviceStatusKind != .ready {
                    Text("RGB presets are disabled until the Device status is ready.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
