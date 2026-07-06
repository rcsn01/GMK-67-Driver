import SwiftUI

struct MacroPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Macros") {
            VStack(alignment: .leading, spacing: 10) {
                ControlGrid {
                    Text("Name")
                    TextField("Combo", text: $model.macroName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Text("Repeat")
                    TextField("1", text: $model.macroRepeatCount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    CommandButton("Create", systemImage: "doc.badge.plus") {
                        model.createMacroProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateMacroProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadMacroProfileFile()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ControlGrid {
                        Text("Add Event")
                        Picker("", selection: $model.macroBuilderEventKind) {
                            Text("Tap Key").tag("key")
                            Text("Key Down").tag("down")
                            Text("Key Up").tag("up")
                            Text("Text").tag("text")
                            Text("Delay").tag("delay")
                        }
                        .labelsHidden()
                        .frame(width: 130)

                        if model.macroBuilderEventKind == "text" {
                            TextField("hello world", text: $model.macroBuilderText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                        } else if model.macroBuilderEventKind == "delay" {
                            TextField("50", text: $model.macroBuilderDelay)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("ms")
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("A", text: $model.macroBuilderKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        CommandButton("Append", systemImage: "plus") {
                            model.appendMacroBuilderEvent()
                        }
                        CommandButton("Clear Events", systemImage: "xmark.circle") {
                            model.clearMacroEvents()
                        }
                    }

                    ControlGrid(minimumWidth: 180) {
                        Text("Events")
                        TextField("down:control key:C up:control delay:50", text: $model.macroEventSpecs)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                    }
                }

                ControlGrid {
                    Text("Library")
                    Picker("", selection: $model.macroLibrarySlot) {
                        if model.macroLibraryEntries.isEmpty {
                            Text("No saved macros").tag(model.macroLibrarySlot)
                        } else {
                            ForEach(model.macroLibraryEntries) { entry in
                                Text("\(entry.slot) - \(entry.name)").tag(entry.slot)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    TextField("combo", text: $model.macroLibrarySlot)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    CommandButton("Save", systemImage: "tray.and.arrow.down") {
                        model.saveCurrentMacroToLibrary()
                    }
                    CommandButton("Import", systemImage: "square.and.arrow.down") {
                        model.importMacroFileToLibrary()
                    }
                    CommandButton("Backup", systemImage: "archivebox") {
                        model.exportMacroLibraryBundle()
                    }
                    CommandButton("Restore", systemImage: "archivebox.fill") {
                        model.importMacroLibraryBundle()
                    }
                    CommandButton("Refresh", systemImage: "arrow.clockwise") {
                        model.refreshMacroLibrary()
                    }
                    CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                        model.loadMacroLibraryEntry()
                    }
                    CommandButton("List", systemImage: "list.bullet") {
                        model.listMacroLibrary()
                    }
                    CommandButton("Delete", systemImage: "trash") {
                        model.deleteMacroLibraryEntry()
                    }
                }

                Text("Macro profiles are app-local JSON artifacts for now. The Windows app exposes Macro Manager, but the board-side macro write/readback protocol is still unmapped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if model.macroLibraryEntries.isEmpty {
                model.refreshMacroLibrary()
            }
        }
    }
}
