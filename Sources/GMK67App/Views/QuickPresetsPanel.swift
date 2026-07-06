import SwiftUI

private struct QuickColorPreset: Identifiable {
    let label: String
    let preset: String
    let swatches: [Color]
    var id: String { preset }
}

struct QuickPresetsPanel: View {
    @ObservedObject var model: DriverModel

    private let colorPresets: [QuickColorPreset] = [
        QuickColorPreset(label: "Red", preset: "red", swatches: [Color(red: 1, green: 0, blue: 0)]),
        QuickColorPreset(label: "Green", preset: "green", swatches: [Color(red: 0, green: 1, blue: 0)]),
        QuickColorPreset(label: "Blue", preset: "blue", swatches: [Color(red: 0, green: 0, blue: 1)]),
        QuickColorPreset(label: "Cyan", preset: "cyan", swatches: [Color(red: 0, green: 1, blue: 1)]),
        QuickColorPreset(label: "Purple", preset: "purple", swatches: [Color(red: 0.5, green: 0, blue: 1)]),
        QuickColorPreset(label: "Pink", preset: "pink", swatches: [Color(red: 1, green: 0.18, blue: 0.54)]),
        QuickColorPreset(label: "Orange", preset: "orange", swatches: [Color(red: 1, green: 0.42, blue: 0)]),
        QuickColorPreset(label: "Gold", preset: "gold", swatches: [Color(red: 1, green: 0.69, blue: 0)]),
        QuickColorPreset(label: "White", preset: "white", swatches: [.white]),
        QuickColorPreset(label: "Off", preset: "off", swatches: [.black]),
        QuickColorPreset(label: "Rainbow", preset: "rainbow", swatches: [.red, .yellow, .green, .blue, .purple]),
        QuickColorPreset(label: "Ocean", preset: "ocean", swatches: [Color(red: 0, green: 0.12, blue: 0.24), .cyan, .blue]),
        QuickColorPreset(label: "Sunset", preset: "sunset", swatches: [Color(red: 0.17, green: 0.06, blue: 0.16), .orange, .red]),
        QuickColorPreset(label: "Fire", preset: "fire", swatches: [Color(red: 0.23, green: 0.04, blue: 0), .red, .orange, .yellow]),
        QuickColorPreset(label: "Ice", preset: "ice", swatches: [Color(red: 0.01, green: 0.11, blue: 0.2), .cyan, .white]),
        QuickColorPreset(label: "Forest", preset: "forest", swatches: [Color(red: 0.02, green: 0.14, blue: 0.05), .green, .yellow]),
        QuickColorPreset(label: "Matrix", preset: "matrix", swatches: [.black, Color(red: 0, green: 1, blue: 0.25)]),
        QuickColorPreset(label: "Aurora", preset: "aurora", swatches: [Color(red: 0.02, green: 0.04, blue: 0.15), .green, .teal, .purple]),
        QuickColorPreset(label: "Cyberpunk", preset: "cyberpunk", swatches: [Color(red: 0.08, green: 0, blue: 0.12), Color(red: 1, green: 0.18, blue: 0.54), .cyan]),
        QuickColorPreset(label: "Pastel", preset: "pastel", swatches: [Color(red: 0.18, green: 0.14, blue: 0.25), Color(red: 1, green: 0.76, blue: 0.89), Color(red: 0.76, green: 1, blue: 0.85)]),
        QuickColorPreset(label: "Lava", preset: "lava", swatches: [Color(red: 0.16, green: 0, blue: 0), .orange, .yellow]),
        QuickColorPreset(label: "WASD", preset: "wasd", swatches: [Color(red: 0.06, green: 0.06, blue: 0.09), .red, .yellow, .green]),
        QuickColorPreset(label: "Coding", preset: "coding", swatches: [Color(red: 0.08, green: 0.08, blue: 0.08), .yellow, .cyan, .purple]),
        QuickColorPreset(label: "Arrows", preset: "arrows", swatches: [Color(red: 0.02, green: 0.03, blue: 0.04), .white, .yellow])
    ]

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8)]

    var body: some View {
        Panel("One-Click RGB Presets") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Solid Colors and Themes")
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(colorPresets) { item in
                        Button {
                            model.runLiveHID(["rgb-preset-apply", item.preset], title: "Apply \(item.label) preset")
                        } label: {
                            HStack(spacing: 6) {
                                HStack(spacing: 2) {
                                    ForEach(Array(item.swatches.enumerated()), id: \.offset) { _, swatch in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(swatch)
                                            .frame(width: 10, height: 10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 2)
                                                    .stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                                            )
                                    }
                                }
                                Text(item.label)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    CommandButton("Undo (Restore Backup)", systemImage: "arrow.uturn.backward") {
                        model.restoreLatestRGBBackup()
                    }
                    Text("Every one-click apply saves an automatic RGB backup first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.deviceStatusKind != .ready {
                    Text("One-click presets are disabled until the Device status is ready.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
