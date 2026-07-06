import AppKit
import Foundation

@MainActor
extension DriverModel {
    private func macroCreateArguments(command: String) -> [String] {
        [
            command,
            "--name=\(macroName)",
            "--repeat=\(macroRepeatCount)"
        ] + splitCommandLine(macroEventSpecs)
    }

    func appendMacroBuilderEvent() {
        let kind = macroBuilderEventKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token: String
        switch kind {
        case "key", "down", "up":
            let key = macroBuilderKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                append("Enter a key for the macro event.")
                return
            }
            token = "\(kind):\(key)"
        case "text":
            let text = macroBuilderText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                append("Enter text for the macro event.")
                return
            }
            token = quoteCommandToken("text:\(text)")
        case "delay":
            let delay = macroBuilderDelay.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Int(delay).map({ $0 >= 0 && $0 <= 60_000 }) == true else {
                append("Enter a delay between 0 and 60000 ms.")
                return
            }
            token = "delay:\(delay)"
        default:
            append("Unsupported macro event kind: \(macroBuilderEventKind)")
            return
        }

        let existing = macroEventSpecs.trimmingCharacters(in: .whitespacesAndNewlines)
        macroEventSpecs = existing.isEmpty ? token : "\(existing) \(token)"
    }

    func clearMacroEvents() {
        macroEventSpecs = ""
    }

    func createMacroProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(macroName)-gmk67-macro.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["macro-create", url.path] + Array(self.macroCreateArguments(command: "macro").dropFirst()), title: "Create macro profile")
            }
        }
    }

    func validateMacroProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["macro-validate", url.path], title: "Validate macro profile")
            }
        }
    }

    func loadMacroProfileFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["macro-show", url.path, "--json"], title: "Load macro file") { text, status in
                    guard status == 0 else { return }
                    do {
                        let macro = try JSONDecoder().decode(AppMacroProfile.self, from: Data(text.utf8))
                        self.loadMacroIntoControls(macro)
                        self.macroLibrarySlot = macro.name
                        self.append("Loaded macro \(macro.name) into the editor.")
                    } catch {
                        self.append("Could not parse macro JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func saveCurrentMacroToLibrary() {
        var args = macroCreateArguments(command: "macro-library-create")
        let slot = macroLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !slot.isEmpty {
            args.append("--slot=\(slot)")
        }
        runCapture(args, title: "Save macro to library") { text, status in
            if !text.isEmpty {
                self.append(text)
            }
            if status == 0 {
                self.refreshMacroLibrary(title: nil, announce: false)
            }
        }
    }

    func importMacroFileToLibrary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                var args = ["macro-library-save", url.path]
                let slot = self.macroLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
                if !slot.isEmpty {
                    args.append("--slot=\(slot)")
                }
                self.runCapture(args, title: "Import macro to library") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshMacroLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    func exportMacroLibraryBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gmk67-macro-library.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["macro-library-bundle-export", url.path], title: "Backup macro library")
            }
        }
    }

    func importMacroLibraryBundle() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["macro-library-bundle-import", url.path], title: "Restore macro library") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshMacroLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    func refreshMacroLibrary() {
        refreshMacroLibrary(title: "Refresh macro library", announce: true)
    }

    func refreshMacroLibrary(title: String? = nil, announce: Bool) {
        runCapture(["macro-library-list", "--json"], title: title) { text, status in
            guard status == 0 else { return }
            do {
                let entries = try JSONDecoder().decode([AppMacroLibraryEntry].self, from: Data(text.utf8))
                self.macroLibraryEntries = entries
                if !entries.isEmpty && !entries.contains(where: { $0.slot == self.macroLibrarySlot }) {
                    self.macroLibrarySlot = entries[0].slot
                }
                if announce {
                    self.append("Loaded \(entries.count) saved macro(s).")
                }
            } catch {
                self.append("Could not parse macro library JSON: \(error.localizedDescription)")
            }
        }
    }

    func loadMacroLibraryEntry() {
        let slot = macroLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a macro library slot to load.")
            return
        }
        runCapture(["macro-library-show", slot, "--json"], title: "Load saved macro") { text, status in
            guard status == 0 else { return }
            do {
                let macro = try JSONDecoder().decode(AppMacroProfile.self, from: Data(text.utf8))
                self.loadMacroIntoControls(macro)
                self.append("Loaded macro \(macro.name) into the editor.")
            } catch {
                self.append("Could not parse saved macro JSON: \(error.localizedDescription)")
            }
        }
    }

    func listMacroLibrary() {
        run(["macro-library-list"], title: "Macro library")
    }

    func deleteMacroLibraryEntry() {
        let slot = macroLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a macro library slot to delete.")
            return
        }
        runCapture(["macro-library-delete", slot], title: "Delete saved macro") { text, status in
            if !text.isEmpty {
                self.append(text)
            }
            if status == 0 {
                self.refreshMacroLibrary(title: nil, announce: false)
            }
        }
    }

    private func loadMacroIntoControls(_ macro: AppMacroProfile) {
        macroName = macro.name
        macroRepeatCount = String(macro.repeatCount)
        macroEventSpecs = macro.events.compactMap { event in
            switch event.type {
            case "key", "down", "up":
                if let key = event.key {
                    return "\(event.type):\(key)"
                }
            case "delay":
                if let delay = event.delayMS {
                    return "delay:\(delay)"
                }
            case "text":
                if let text = event.text {
                    return quoteCommandToken("text:\(text)")
                }
            default:
                return nil
            }
            return nil
        }.joined(separator: " ")
    }
}
