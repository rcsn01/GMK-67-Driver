import SwiftUI

struct ProfilePanel: View {
    @ObservedObject var model: DriverModel
    private let presets = ["gaming", "navigation", "coding", "editing", "ocean-rgb", "lights-off"]

    var body: some View {
        Panel("Keyboard Profile") {
            VStack(alignment: .leading, spacing: 10) {
                ControlGrid {
                    Text("Preset")
                    Picker("", selection: $model.profilePresetName) {
                        ForEach(presets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    CommandButton("Create", systemImage: "doc.badge.plus") {
                        model.createCombinedProfilePreset()
                    }
                    CommandButton("Apply", systemImage: "rectangle.stack.badge.play") {
                        model.applyCombinedProfilePreset()
                    }
                    CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                        model.loadCombinedProfilePresetIntoEditor()
                    }
                }

                ControlGrid {
                    Text("Name")
                    TextField("Gaming", text: $model.combinedProfileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Text("RGB")
                    Text(model.rgbPresetName)
                        .monospaced()
                        .frame(width: 110, alignment: .leading)
                    Text("Keymap")
                    Text(model.combinedProfileIncludesKeymap ? model.keymapPresetName : "-")
                        .monospaced()
                        .frame(width: 140, alignment: .leading)
                    Toggle("Include", isOn: $model.combinedProfileIncludesKeymap)
                        .toggleStyle(.checkbox)
                    Toggle("RGB Map", isOn: $model.combinedProfileIncludesRGBMap)
                        .toggleStyle(.checkbox)
                    Toggle("Remaps", isOn: $model.combinedProfileIncludesKeymapSpecs)
                        .toggleStyle(.checkbox)
                    CommandButton("Create", systemImage: "doc.badge.plus") {
                        model.createCombinedProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateCombinedProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadCombinedProfileFile()
                    }
                    CommandButton("Preview Current", systemImage: "eye") {
                        model.previewCurrentProfile()
                    }
                    CommandButton("Export Current", systemImage: "square.and.arrow.down") {
                        model.exportCurrentProfileArtifacts()
                    }
                    CommandButton("Apply Current", systemImage: "rectangle.stack.badge.play") {
                        model.applyCurrentProfile()
                    }
                    CommandButton("Preview", systemImage: "eye") {
                        model.previewCombinedProfile()
                    }
                    CommandButton("Export", systemImage: "square.and.arrow.down") {
                        model.exportCombinedProfileArtifacts()
                    }
                    CommandButton("Apply", systemImage: "rectangle.stack") {
                        model.applyCombinedProfile()
                    }
                }

                ControlGrid {
                    Text("Library")
                    Picker("", selection: $model.profileLibrarySlot) {
                        if model.profileLibraryEntries.isEmpty {
                            Text("No saved profiles").tag(model.profileLibrarySlot)
                        } else {
                            ForEach(model.profileLibraryEntries) { entry in
                                Text("\(entry.slot) - \(entry.name)").tag(entry.slot)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    TextField("gaming", text: $model.profileLibrarySlot)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    CommandButton("Save", systemImage: "tray.and.arrow.down") {
                        model.saveCurrentProfileToLibrary()
                    }
                    CommandButton("Import", systemImage: "square.and.arrow.down") {
                        model.importProfileFileToLibrary()
                    }
                    CommandButton("Backup", systemImage: "externaldrive.badge.timemachine") {
                        model.exportProfileLibraryBundle()
                    }
                    CommandButton("Restore", systemImage: "externaldrive.badge.plus") {
                        model.importProfileLibraryBundle()
                    }
                    CommandButton("Refresh", systemImage: "arrow.clockwise") {
                        model.refreshProfileLibrary()
                    }
                    CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                        model.loadProfileLibraryEntry()
                    }
                    CommandButton("List", systemImage: "list.bullet") {
                        model.listProfileLibrary()
                    }
                    CommandButton("Preview", systemImage: "eye") {
                        model.previewProfileLibraryEntry()
                    }
                    CommandButton("Export", systemImage: "square.and.arrow.down") {
                        model.exportProfileLibraryEntry()
                    }
                    CommandButton("Apply", systemImage: "rectangle.stack.badge.play") {
                        model.applyProfileLibraryEntry()
                    }
                    CommandButton("Delete", systemImage: "trash") {
                        model.deleteProfileLibraryEntry()
                    }
                }
            }
        }
        .onAppear {
            if model.profileLibraryEntries.isEmpty {
                model.refreshProfileLibrary()
            }
        }
    }
}
