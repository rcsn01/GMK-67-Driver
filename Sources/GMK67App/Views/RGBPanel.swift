import SwiftUI

struct RGBPanel: View {
    @ObservedObject var model: DriverModel
    private let presets = [
        "off", "white", "red", "blue", "green", "purple", "cyan", "orange", "pink", "gold",
        "wasd", "arrows", "coding", "rainbow", "ocean", "sunset",
        "fire", "ice", "forest", "matrix", "aurora", "cyberpunk", "pastel", "lava"
    ]

    var body: some View {
        Panel("RGB") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Preset")
                    Picker("", selection: $model.rgbPresetName) {
                        ForEach(presets, id: \.self) { preset in
                            Text(preset).tag(preset)
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

                GridRow {
                    Text("Key")
                    TextField("W", text: $model.keyName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("Color")
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
                    CommandButton("Set Key", systemImage: "paintbrush") {
                        model.runLiveHID(["rgb-set-key", model.keyName, model.colorHex], title: "Set one key")
                    }
                }

                GridRow {
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
                        model.runLiveHID(["rgb-set-all", model.fillHex], title: "Set all physical keys")
                    }
                    CommandButton("Clear", systemImage: "lightswitch.off") {
                        model.runLiveHID(["rgb-clear"], title: "Clear physical key RGB")
                    }
                    EmptyView()
                }

                GridRow {
                    Text("Map")
                    TextField("W=FF0000 A=00FF00", text: $model.mapSpecs)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(3)
                    CommandButton("Apply Map", systemImage: "rectangle.3.group") {
                        model.runLiveHID(["rgb-map"] + splitCommandLine(model.mapSpecs), title: "Set multiple RGB keys")
                    }
                }

                GridRow {
                    Text("Profile Fill")
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
                    EmptyView()
                }

                GridRow {
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
                    EmptyView()
                }

                GridRow {
                    Text("Editor")
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadRGBProfileIntoEditor()
                    }
                    CommandButton("Load Current", systemImage: "keyboard.badge.ellipsis") {
                        model.loadCurrentRGBIntoEditor()
                    }
                    EmptyView()
                    EmptyView()
                }

                GridRow {
                    Text("Backups")
                    CommandButton("List", systemImage: "clock.arrow.circlepath") {
                        model.listRGBBackups()
                    }
                    CommandButton("Restore Latest", systemImage: "arrow.uturn.backward") {
                        model.restoreLatestRGBBackup()
                    }
                    EmptyView()
                    EmptyView()
                }
            }
        }
    }
}
