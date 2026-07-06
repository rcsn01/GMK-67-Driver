import SwiftUI

struct KeymapPanel: View {
    @ObservedObject var model: DriverModel
    private let presets = ["caps-esc", "wasd-arrows", "vim-arrows", "gaming-layer", "editing-shortcuts", "function-row", "navigation-cluster"]

    var body: some View {
        Panel("Keymap") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preset")
                    Picker("", selection: $model.keymapPresetName) {
                        ForEach(presets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportKeymapPresetProfile()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyKeymapPreset()
                    }
                    CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                        model.loadKeymapPresetIntoEditor()
                    }
                }

                HStack {
                    Text("Source")
                    TextField("A", text: $model.sourceKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("Target")
                    TextField("B", text: $model.targetKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("Modifier")
                    TextField("shift", text: $model.modifierKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    CommandButton("Dry Run", systemImage: "doc.text.magnifyingglass") {
                        var args = ["keymap-dry-run", model.sourceKey, model.targetKey]
                        if !model.modifierKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            args.append(model.modifierKey)
                        }
                        model.run(args, title: "Keymap dry run")
                    }
                }

                HStack {
                    Text("Profile")
                    TextField("W=up A=left S=down D=right", text: $model.keymapSpecs)
                        .textFieldStyle(.roundedBorder)
                    CommandButton("Dry Run Map", systemImage: "doc.text") {
                        model.run(["keymap-map-dry-run"] + splitCommandLine(model.keymapSpecs), title: "Multi-remap dry run")
                    }
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportKeymapProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadKeymapProfileIntoEditor()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyKeymapMap()
                    }
                    CommandButton("Clear", systemImage: "xmark.circle") {
                        model.clearKeymap()
                    }
                }

                HStack {
                    Text("Library")
                    TextField("WASD Arrows", text: $model.keymapProfileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Picker("", selection: $model.keymapLibrarySlot) {
                        if model.keymapLibraryEntries.isEmpty {
                            Text("No saved keymaps").tag(model.keymapLibrarySlot)
                        } else {
                            ForEach(model.keymapLibraryEntries) { entry in
                                Text("\(entry.slot) - \(entry.name)").tag(entry.slot)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    TextField("wasd", text: $model.keymapLibrarySlot)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    CommandButton("Save", systemImage: "tray.and.arrow.down") {
                        model.saveCurrentKeymapToLibrary()
                    }
                    CommandButton("Import", systemImage: "square.and.arrow.down") {
                        model.importKeymapProfileToLibrary()
                    }
                    CommandButton("Refresh", systemImage: "arrow.clockwise") {
                        model.refreshKeymapLibrary()
                    }
                }

                HStack {
                    Text("Saved")
                    CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                        model.loadKeymapLibraryEntry()
                    }
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportKeymapLibraryEntry()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyKeymapLibraryEntry()
                    }
                    CommandButton("List", systemImage: "list.bullet") {
                        model.listKeymapLibrary()
                    }
                    CommandButton("Backup", systemImage: "archivebox") {
                        model.exportKeymapLibraryBundle()
                    }
                    CommandButton("Restore", systemImage: "archivebox.fill") {
                        model.importKeymapLibraryBundle()
                    }
                    CommandButton("Delete", systemImage: "trash") {
                        model.deleteKeymapLibraryEntry()
                    }
                }

                HStack {
                    Text("Alt Table")
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportAlternateTableProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateAlternateTableProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadAlternateTableProfileIntoEditor()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyAlternateTableProfile()
                    }
                    Text("Builds the candidate 04 27 full-table artifact from the profile specs above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Allow unsafe keymap writes", isOn: $model.unsafeKeymapWrites)
                    .toggleStyle(.checkbox)

                Text("Keymap writes are still guarded because board-side keymap backup/readback is not proven. RGB writes use automatic backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.deviceStatusKind != .ready {
                    Text("Live keymap writes are disabled until the Device status is ready. Export and dry-run commands remain available.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear {
            if model.keymapLibraryEntries.isEmpty {
                model.refreshKeymapLibrary()
            }
        }
    }
}
