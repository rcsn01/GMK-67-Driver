import SwiftUI
import AppKit
import Foundation

@MainActor
extension DriverModel {
    func createCombinedProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(combinedProfileName)-gmk67-profile.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                var args = [
                    "profile-create",
                    url.path,
                    "--name=\(self.combinedProfileName)",
                    "--rgb=\(self.rgbPresetName)",
                    "--keymap=\(self.combinedProfileIncludesKeymap ? self.keymapPresetName : "none")"
                ]
                if self.combinedProfileIncludesRGBMap {
                    args.append("--rgb-fill=\(self.profileFillHex)")
                    args += splitCommandLine(self.mapSpecs)
                }
                if self.combinedProfileIncludesKeymapSpecs {
                    args += splitCommandLine(self.keymapSpecs).map { "--remap=\($0)" }
                }
                self.run(args, title: "Create keyboard profile")
            }
        }
    }

    private func composedProfileArguments(command: String) -> [String] {
        var args = [
            command,
            "--name=\(combinedProfileName)",
            "--rgb=\(rgbPresetName)",
            "--keymap=\(combinedProfileIncludesKeymap ? keymapPresetName : "none")"
        ]
        if combinedProfileIncludesRGBMap {
            args.append("--rgb-fill=\(profileFillHex)")
            args += splitCommandLine(mapSpecs)
        }
        if combinedProfileIncludesKeymapSpecs {
            args += splitCommandLine(keymapSpecs).map { "--remap=\($0)" }
        }
        return args
    }

    func previewCurrentProfile() {
        run(composedProfileArguments(command: "profile-preview-spec"), title: "Preview current editor profile")
    }

    func exportCurrentProfileArtifacts() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = combinedProfileName
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let profileArgs = Array(self.composedProfileArguments(command: "profile-export-spec").dropFirst())
                self.run(["profile-export-spec", url.path] + profileArgs, title: "Export current editor profile artifacts")
            }
        }
    }

    func applyCurrentProfile() {
        var args = composedProfileArguments(command: "profile-apply-spec")
        if unsafeKeymapWrites {
            args.append("--unsafe-no-backup")
        }
        runLiveHID(args, title: "Apply current editor profile")
    }

    func saveCurrentProfileToLibrary() {
        var args = composedProfileArguments(command: "profile-library-create")
        let slot = profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !slot.isEmpty {
            args.append("--slot=\(slot)")
        }
        runCapture(args, title: "Save profile to library") { text, status in
            if !text.isEmpty {
                self.append(text)
            }
            if status == 0 {
                self.refreshProfileLibrary(title: nil, announce: false)
            }
        }
    }

    func refreshProfileLibrary() {
        refreshProfileLibrary(title: "Refresh profile library", announce: true)
    }

    func refreshProfileLibrary(title: String? = nil, announce: Bool) {
        runCapture(["profile-library-list", "--json"], title: title) { text, status in
            guard status == 0 else { return }
            do {
                let data = Data(text.utf8)
                let entries = try JSONDecoder().decode([AppProfileLibraryEntry].self, from: data)
                self.profileLibraryEntries = entries
                if !entries.isEmpty && !entries.contains(where: { $0.slot == self.profileLibrarySlot }) {
                    self.profileLibrarySlot = entries[0].slot
                }
                if announce {
                    self.append("Loaded \(entries.count) saved profile(s).")
                }
            } catch {
                self.append("Could not parse profile library JSON: \(error.localizedDescription)")
            }
        }
    }

    func loadProfileLibraryEntry() {
        let slot = profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a profile library slot to load.")
            return
        }
        runCapture(["profile-library-show", slot, "--json"], title: "Load saved profile") { text, status in
            guard status == 0 else { return }
            do {
                let profile = try JSONDecoder().decode(AppCombinedProfile.self, from: Data(text.utf8))
                self.loadProfileIntoControls(profile)
                self.append("Loaded profile \(profile.name) into the editor.")
            } catch {
                self.append("Could not parse saved profile JSON: \(error.localizedDescription)")
            }
        }
    }

    func loadCombinedProfileFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["profile-show", url.path, "--json"], title: "Load profile file") { text, status in
                    guard status == 0 else { return }
                    do {
                        let profile = try JSONDecoder().decode(AppCombinedProfile.self, from: Data(text.utf8))
                        self.loadProfileIntoControls(profile)
                        self.profileLibrarySlot = profile.name
                        self.append("Loaded profile \(profile.name) into the editor.")
                    } catch {
                        self.append("Could not parse profile JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func importProfileFileToLibrary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                var args = ["profile-library-save", url.path]
                let slot = self.profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
                if !slot.isEmpty {
                    args.append("--slot=\(slot)")
                }
                self.runCapture(args, title: "Import profile to library") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshProfileLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    func exportProfileLibraryBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gmk67-profile-library.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["profile-library-bundle-export", url.path], title: "Backup profile library")
            }
        }
    }

    func importProfileLibraryBundle() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["profile-library-bundle-import", url.path], title: "Restore profile library") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshProfileLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    private func loadProfileIntoControls(_ profile: AppCombinedProfile) {
        combinedProfileName = profile.name
        rgbPresetName = profile.rgbPreset
        if let keymapPreset = profile.keymapPreset, !keymapPreset.isEmpty {
            keymapPresetName = keymapPreset
            combinedProfileIncludesKeymap = true
        } else {
            combinedProfileIncludesKeymap = false
        }

        if let rgbFill = profile.rgbFill {
            profileFillHex = rgbFill
            profileFillColor = colorFromHex(rgbFill)
        } else {
            profileFillHex = "000000"
            profileFillColor = .black
        }

        mapSpecs = (profile.rgbAssignments ?? []).joined(separator: " ")
        combinedProfileIncludesRGBMap = profile.rgbFill != nil || !(profile.rgbAssignments ?? []).isEmpty

        keymapSpecs = (profile.keymapRemaps ?? []).joined(separator: " ")
        combinedProfileIncludesKeymapSpecs = !(profile.keymapRemaps ?? []).isEmpty
    }

    func listProfileLibrary() {
        run(["profile-library-list"], title: "Profile library")
    }

    func previewProfileLibraryEntry() {
        let slot = profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a profile library slot to preview.")
            return
        }
        run(["profile-library-preview", slot], title: "Preview saved profile")
    }

    func exportProfileLibraryEntry() {
        let slot = profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a profile library slot to export.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(slot)-profile"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["profile-library-export", slot, url.path], title: "Export saved profile")
            }
        }
    }

    func applyProfileLibraryEntry() {
        let slot = profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a profile library slot to apply.")
            return
        }
        var args = ["profile-library-apply", slot]
        if unsafeKeymapWrites {
            args.append("--unsafe-no-backup")
        }
        runLiveHID(args, title: "Apply saved profile")
    }

    func deleteProfileLibraryEntry() {
        let slot = profileLibrarySlot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slot.isEmpty else {
            append("Enter a profile library slot to delete.")
            return
        }
        runCapture(["profile-library-delete", slot], title: "Delete saved profile") { text, status in
            if !text.isEmpty {
                self.append(text)
            }
            if status == 0 {
                self.refreshProfileLibrary(title: nil, announce: false)
            }
        }
    }

    func validateCombinedProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["profile-validate", url.path], title: "Validate keyboard profile")
            }
        }
    }

    func previewCombinedProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["profile-preview", url.path], title: "Preview keyboard profile")
            }
        }
    }

    func exportCombinedProfileArtifacts() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.begin { response in
            guard response == .OK, let profileURL = openPanel.url else { return }
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = profileURL.deletingPathExtension().lastPathComponent
            savePanel.allowedContentTypes = []
            savePanel.begin { saveResponse in
                guard saveResponse == .OK, let prefixURL = savePanel.url else { return }
                Task { @MainActor in
                    self.run(["profile-export", profileURL.path, prefixURL.path], title: "Export keyboard profile artifacts")
                }
            }
        }
    }

    func applyCombinedProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                var args = ["profile-apply", url.path]
                if self.unsafeKeymapWrites {
                    args.append("--unsafe-no-backup")
                }
                self.runLiveHID(args, title: "Apply keyboard profile")
            }
        }
    }

    func createCombinedProfilePreset() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(profilePresetName)-gmk67-profile.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["profile-preset-create", url.path, self.profilePresetName], title: "Create keyboard profile preset")
            }
        }
    }

    func applyCombinedProfilePreset() {
        var args = ["profile-preset-apply", profilePresetName]
        if unsafeKeymapWrites {
            args.append("--unsafe-no-backup")
        }
        runLiveHID(args, title: "Apply keyboard profile preset")
    }

    func loadCombinedProfilePresetIntoEditor() {
        runCapture(["profile-preset-show", profilePresetName, "--editor-json"], title: "Load keyboard profile preset into editor") { text, status in
            guard status == 0 else { return }
            do {
                let profile = try JSONDecoder().decode(AppCombinedProfile.self, from: Data(text.utf8))
                self.loadProfileIntoControls(profile)
                self.profileLibrarySlot = profile.name
                self.append("Loaded profile preset \(self.profilePresetName) into the editor.")
            } catch {
                self.append("Could not parse profile preset JSON: \(error.localizedDescription)")
            }
        }
    }
}
