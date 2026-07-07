import SwiftUI

private struct RGBLayoutChoice: Identifiable {
    let name: String
    let label: String
    var id: String { name }
}

private struct RGBThemeChoice: Identifiable {
    let name: String
    let label: String
    let swatches: [Color]
    var id: String { name }
}

struct RGBPanel: View {
    @ObservedObject var model: DriverModel

    private let effects = [
        "static", "single-on", "single-off", "glittering", "falling", "colourful",
        "breath", "spectrum", "outward", "scrolling", "rolling", "rotating",
        "explode", "launch", "ripples", "flowing", "pulsating", "tilt", "shuttle", "led-off"
    ]

    private let layouts: [RGBLayoutChoice] = [
        RGBLayoutChoice(name: "all", label: "All Keys"),
        RGBLayoutChoice(name: "wasd", label: "WASD"),
        RGBLayoutChoice(name: "arrows", label: "Arrows"),
        RGBLayoutChoice(name: "coding", label: "Coding"),
        RGBLayoutChoice(name: "rows", label: "Rows")
    ]

    private let themes: [RGBThemeChoice] = [
        RGBThemeChoice(name: "off", label: "Off", swatches: [.black]),
        RGBThemeChoice(name: "white", label: "White", swatches: [.white]),
        RGBThemeChoice(name: "red", label: "Red", swatches: [.red]),
        RGBThemeChoice(name: "green", label: "Green", swatches: [.green]),
        RGBThemeChoice(name: "blue", label: "Blue", swatches: [.blue]),
        RGBThemeChoice(name: "purple", label: "Purple", swatches: [Color(red: 0.5, green: 0, blue: 1)]),
        RGBThemeChoice(name: "cyan", label: "Cyan", swatches: [.cyan]),
        RGBThemeChoice(name: "orange", label: "Orange", swatches: [.orange]),
        RGBThemeChoice(name: "yellow", label: "Yellow", swatches: [.yellow]),
        RGBThemeChoice(name: "pink", label: "Pink", swatches: [Color(red: 1, green: 0.18, blue: 0.54)]),
        RGBThemeChoice(name: "gold", label: "Gold", swatches: [Color(red: 1, green: 0.69, blue: 0)]),
        RGBThemeChoice(name: "rainbow", label: "Rainbow", swatches: [.red, .yellow, .green, .blue, .purple]),
        RGBThemeChoice(name: "ocean", label: "Ocean", swatches: [Color(red: 0, green: 0.12, blue: 0.24), .cyan, .blue]),
        RGBThemeChoice(name: "sunset", label: "Sunset", swatches: [Color(red: 0.17, green: 0.06, blue: 0.16), .orange, .red]),
        RGBThemeChoice(name: "fire", label: "Fire", swatches: [Color(red: 0.23, green: 0.04, blue: 0), .red, .orange, .yellow]),
        RGBThemeChoice(name: "ice", label: "Ice", swatches: [Color(red: 0.01, green: 0.11, blue: 0.2), .cyan, .white]),
        RGBThemeChoice(name: "forest", label: "Forest", swatches: [Color(red: 0.02, green: 0.14, blue: 0.05), .green, .yellow]),
        RGBThemeChoice(name: "matrix", label: "Matrix", swatches: [.black, Color(red: 0, green: 1, blue: 0.25)]),
        RGBThemeChoice(name: "aurora", label: "Aurora", swatches: [Color(red: 0.02, green: 0.04, blue: 0.15), .green, .teal, .purple]),
        RGBThemeChoice(name: "cyberpunk", label: "Cyberpunk", swatches: [Color(red: 0.08, green: 0, blue: 0.12), Color(red: 1, green: 0.18, blue: 0.54), .cyan]),
        RGBThemeChoice(name: "pastel", label: "Pastel", swatches: [Color(red: 0.18, green: 0.14, blue: 0.25), Color(red: 1, green: 0.76, blue: 0.89), Color(red: 0.76, green: 1, blue: 0.85)]),
        RGBThemeChoice(name: "lava", label: "Lava", swatches: [Color(red: 0.16, green: 0, blue: 0), .orange, .yellow])
    ]

    private let themeColumns = [GridItem(.adaptive(minimum: 118), spacing: 8)]

    var body: some View {
        Panel("RGB") {
            TabView {
                effectTab
                    .tabItem {
                        Label("Effect", systemImage: "sparkles")
                    }

                staticLayoutTab
                    .tabItem {
                        Label("Static Layout", systemImage: "keyboard")
                    }
            }
            .frame(minHeight: 520)
        }
    }

    private var effectTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlGrid {
                Text("Effect")
                Picker("", selection: $model.lightingEffectName) {
                    ForEach(effects, id: \.self) { effect in
                        Text(effect).tag(effect)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
                Text("Color")
                ColorPicker("", selection: Binding(
                    get: { model.lightingEffectColor },
                    set: {
                        model.lightingEffectColor = $0
                        model.lightingEffectColorHex = rgbHex($0)
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
                TextField("FFFFFF", text: $model.lightingEffectColorHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                CommandButton("Apply Effect", systemImage: "sparkles") {
                    model.applyLightingEffect()
                }
            }

            Text("Built-in firmware effect modes use the confirmed mode+color write path.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var staticLayoutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            ControlGrid {
                Text("Existing Layout")
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
                    model.applyRGBPreset()
                }
                CommandButton("Create File", systemImage: "doc.badge.plus") {
                    model.createRGBPresetProfile()
                }
                CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                    model.loadRGBPresetIntoEditor()
                }
            }

            LazyVGrid(columns: themeColumns, alignment: .leading, spacing: 8) {
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

            Divider()

            ControlGrid {
                Text("Selected Key")
                Text(model.selectedVisualKey)
                    .monospaced()
                    .frame(width: 90, alignment: .leading)
                Text("Color")
                keyColorPicker
                CommandButton("Apply Color", systemImage: "paintbrush") {
                    model.assignSelectedKeyColor()
                }
                CommandButton("No Color", systemImage: "lightswitch.off") {
                    model.clearSelectedKeyColor()
                }
            }

            ControlGrid {
                Text("Manual Key")
                TextField("W", text: $model.keyName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("Color")
                keyColorPicker
                CommandButton("Set Key", systemImage: "paintbrush") {
                    model.setRGBKey()
                }
            }

            ControlGrid {
                Text("All Keys")
                ColorPicker("", selection: Binding(
                    get: { model.allKeysColor },
                    set: {
                        model.allKeysColor = $0
                        model.fillHex = rgbHex($0)
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
                TextField("000000", text: $model.fillHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                CommandButton("Set All", systemImage: "paintpalette") {
                    model.setAllRGBKeys()
                }
                CommandButton("Clear", systemImage: "lightswitch.off") {
                    model.clearRGB()
                }
            }

            ControlGrid(minimumWidth: 180) {
                Text("Map")
                TextField("W=FF0000 A=00FF00", text: $model.mapSpecs)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                CommandButton("Apply Map", systemImage: "rectangle.3.group") {
                    model.applyRGBMap()
                }
            }

            ControlGrid {
                Text("New Layout")
                ColorPicker("", selection: Binding(
                    get: { model.profileFillColor },
                    set: {
                        model.profileFillColor = $0
                        model.profileFillHex = rgbHex($0)
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44)
                TextField("000000", text: $model.profileFillHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                CommandButton("Create", systemImage: "doc.badge.plus") {
                    model.createRGBProfile()
                }
            }

            ControlGrid {
                Text("Profiles")
                CommandButton("Save", systemImage: "square.and.arrow.down") {
                    model.saveRGBProfile()
                }
                CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                    model.validateRGBProfile()
                }
                CommandButton("Restore", systemImage: "square.and.arrow.up") {
                    model.restoreRGBProfile()
                }
            }

            ControlGrid {
                Text("Editor")
                CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                    model.loadRGBProfileIntoEditor()
                }
                CommandButton("Load Current", systemImage: "keyboard.badge.ellipsis") {
                    model.loadCurrentRGBIntoEditor()
                }
            }

            ControlGrid {
                Text("Backups")
                CommandButton("List", systemImage: "clock.arrow.circlepath") {
                    model.listRGBBackups()
                }
                CommandButton("Restore Latest", systemImage: "arrow.uturn.backward") {
                    model.restoreLatestRGBBackup()
                }
            }
        }
        .padding(.top, 8)
    }

    private var keyColorPicker: some View {
        Group {
            ColorPicker("", selection: Binding(
                get: { model.keyColor },
                set: {
                    model.keyColor = $0
                    model.colorHex = rgbHex($0)
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 44)
            TextField("FF0000", text: $model.colorHex)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }
}
