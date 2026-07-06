import AppKit
import Foundation

@MainActor
extension DriverModel {
    func exportKeymapProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "keymap-profile.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let specs = splitCommandLine(self.keymapSpecs)
            Task { @MainActor in
                self.run(["keymap-map-export", url.path] + specs, title: "Export keymap profile")
            }
        }
    }

    func validateKeymapProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["keymap-sequence-validate", url.path], title: "Validate keymap profile")
            }
        }
    }

    func loadKeymapProfileIntoEditor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["keymap-sequence-validate", url.path, "--json"], title: "Load keymap profile into editor") { text, status in
                    guard status == 0 else { return }
                    do {
                        let records = try JSONDecoder().decode([AppKeymapRecord].self, from: Data(text.utf8))
                        let specs = records.compactMap { $0.spec }.filter { !$0.isEmpty }
                        self.keymapSpecs = specs.joined(separator: " ")
                        self.combinedProfileIncludesKeymapSpecs = !specs.isEmpty
                        self.append("Loaded \(specs.count) keymap remap(s) into the editor.")
                    } catch {
                        self.append("Could not parse keymap records JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func exportKeymapPresetProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(keymapPresetName)-keymap.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["keymap-preset-export", url.path, self.keymapPresetName], title: "Export keymap preset")
            }
        }
    }

    func applyKeymapPreset() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe keymap writes before applying a keymap preset. Keymap backup/readback is not proven yet.")
            return
        }
        runLiveHID(["keymap-preset-apply", keymapPresetName, "--unsafe-no-backup"], title: "Apply keymap preset")
    }

    func loadKeymapPresetIntoEditor() {
        runCapture(["keymap-preset-show", keymapPresetName, "--json"], title: "Load keymap preset into editor") { text, status in
            guard status == 0 else { return }
            do {
                let preset = try JSONDecoder().decode(AppKeymapPreset.self, from: Data(text.utf8))
                self.keymapPresetName = preset.name
                self.keymapProfileName = preset.title
                self.keymapSpecs = preset.remaps.joined(separator: " ")
                self.combinedProfileIncludesKeymapSpecs = !preset.remaps.isEmpty
                self.append("Loaded keymap preset \(preset.name) into the editor: \(preset.description)")
            } catch {
                self.append("Could not parse keymap preset JSON: \(error.localizedDescription)")
            }
        }
    }

    func applyKeymapMap() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe keymap writes before applying a custom keymap. Keymap backup/readback is not proven yet.")
            return
        }
        let specs = splitCommandLine(keymapSpecs)
        guard !specs.isEmpty else {
            append("Enter at least one keymap assignment, for example W=up A=left S=down D=right.")
            return
        }
        runLiveHID(["keymap-map-apply"] + specs + ["--unsafe-no-backup"], title: "Apply custom keymap")
    }

    func clearKeymap() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe keymap writes before clearing the custom keymap. Keymap backup/readback is not proven yet.")
            return
        }
        runLiveHID(["keymap-clear", "--unsafe-no-backup"], title: "Clear custom keymap")
    }

    private func keymapLibraryCreateArguments(command: String) -> [String] {
        [
            command,
            "--name=\(keymapProfileName)"
        ] + splitCommandLine(keymapSpecs)
    }

    func saveCurrentKeymapToLibrary() {
        var args = keymapLibraryCreateArguments(command: "keymap-library-create")
        let slot = keymapLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !slot.isEmpty {
            args.append("--slot=\(slot)")
        }
        runCapture(args, title: "Save keymap to library") { text, status in
            if !text.isEmpty {
                self.append(text)
            }
            if status == 0 {
                self.refreshKeymapLibrary(title: nil, announce: false)
            }
        }
    }

    func importKeymapProfileToLibrary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                var args = ["keymap-library-save", url.path]
                let slot = self.keymapLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
                if !slot.isEmpty {
                    args.append("--slot=\(slot)")
                }
                self.runCapture(args, title: "Import keymap to library") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshKeymapLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    func refreshKeymapLibrary() {
        refreshKeymapLibrary(title: "Refresh keymap library", announce: true)
    }

    func refreshKeymapLibrary(title: String? = nil, announce: Bool) {
        runCapture(["keymap-library-list", "--json"], title: title) { text, status in
            guard status == 0 else { return }
            do {
                let entries = try JSONDecoder().decode([AppKeymapLibraryEntry].self, from: Data(text.utf8))
                self.keymapLibraryEntries = entries
                if !entries.isEmpty && !entries.contains(where: { $0.slot == self.keymapLibrarySlot }) {
                    self.keymapLibrarySlot = entries[0].slot
                }
                if announce {
                    self.append("Loaded \(entries.count) saved keymap profile(s).")
                }
            } catch {
                self.append("Could not parse keymap library JSON: \(error.localizedDescription)")
            }
        }
    }

    func loadKeymapLibraryEntry() {
        let slot = keymapLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a keymap library slot to load.")
            return
        }
        runCapture(["keymap-library-show", slot, "--json"], title: "Load saved keymap") { text, status in
            guard status == 0 else { return }
            do {
                let profile = try JSONDecoder().decode(AppKeymapProfile.self, from: Data(text.utf8))
                self.keymapProfileName = profile.name
                self.keymapSpecs = profile.remaps.joined(separator: " ")
                self.combinedProfileIncludesKeymapSpecs = !profile.remaps.isEmpty
                self.append("Loaded keymap profile \(profile.name) into the editor.")
            } catch {
                self.append("Could not parse saved keymap JSON: \(error.localizedDescription)")
            }
        }
    }

    func exportKeymapLibraryEntry() {
        let slot = keymapLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a keymap library slot to export.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(slot)-keymap.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["keymap-library-export", slot, url.path], title: "Export saved keymap")
            }
        }
    }

    func applyKeymapLibraryEntry() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe keymap writes before applying a saved keymap. Keymap backup/readback is not proven yet.")
            return
        }
        let slot = keymapLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a keymap library slot to apply.")
            return
        }
        runLiveHID(["keymap-library-apply", slot, "--unsafe-no-backup"], title: "Apply saved keymap")
    }

    func listKeymapLibrary() {
        run(["keymap-library-list"], title: "Keymap library")
    }

    func deleteKeymapLibraryEntry() {
        let slot = keymapLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a keymap library slot to delete.")
            return
        }
        runCapture(["keymap-library-delete", slot], title: "Delete saved keymap") { text, status in
            if !text.isEmpty {
                self.append(text)
            }
            if status == 0 {
                self.refreshKeymapLibrary(title: nil, announce: false)
            }
        }
    }

    func exportKeymapLibraryBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gmk67-keymap-library.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["keymap-library-bundle-export", url.path], title: "Backup keymap library")
            }
        }
    }

    func importKeymapLibraryBundle() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["keymap-library-bundle-import", url.path], title: "Restore keymap library") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshKeymapLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    func exportAlternateTableProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "alternate-table.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let specs = splitCommandLine(self.keymapSpecs)
            Task { @MainActor in
                self.run(["alternate-table-export", url.path] + specs, title: "Export alternate full-table profile")
            }
        }
    }

    func validateAlternateTableProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["alternate-table-validate", url.path], title: "Validate alternate full-table profile")
            }
        }
    }

    func loadAlternateTableProfileIntoEditor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["alternate-table-validate", url.path, "--json"], title: "Load alternate full-table into editor") { text, status in
                    guard status == 0 else { return }
                    do {
                        let records = try JSONDecoder().decode([AppKeymapRecord].self, from: Data(text.utf8))
                        let specs = records.compactMap { $0.spec }.filter { !$0.isEmpty }
                        self.keymapSpecs = specs.joined(separator: " ")
                        self.combinedProfileIncludesKeymapSpecs = !specs.isEmpty
                        self.append("Loaded \(specs.count) alternate-table remap(s) into the editor.")
                    } catch {
                        self.append("Could not parse alternate-table JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func applyAlternateTableProfile() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe candidate writes before applying an alternate full-table sequence. Readback/backup is not proven yet.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runLiveHID(["alternate-table-apply", url.path, "--unsafe-no-backup"], title: "Apply alternate full-table profile")
            }
        }
    }
}
