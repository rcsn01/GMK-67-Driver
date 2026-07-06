import SwiftUI
import AppKit
import Foundation
import GMK67Core

@MainActor
extension DriverModel {
    func saveRGBProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = profileName
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runLiveHID(["rgb-save", url.path], title: "Save RGB profile")
            }
        }
    }

    func restoreRGBProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runRGBWrite(["rgb-restore", url.path], title: "Restore RGB profile")
            }
        }
    }

    func validateRGBProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["rgb-restore-dry-run", url.path], title: "Validate RGB profile")
            }
        }
    }

    func loadRGBProfileIntoEditor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["rgb-file-dump", url.path, "--json"], title: "Load RGB profile into editor") { text, status in
                    guard status == 0 else { return }
                    self.decodeRGBRecordsIntoEditor(text)
                }
            }
        }
    }

    func loadCurrentRGBIntoEditor() {
        guard deviceStatusKind == .ready else {
            append("Live keyboard access is not ready. Load a saved RGB file or built-in preset, or grant Input Monitoring and refresh status before loading current RGB.")
            return
        }
        guard !isRunning else {
            append("Wait for the current driver command to finish before loading current RGB.")
            return
        }
        Task { @MainActor in
            do {
                let records = try await readCurrentRGBRecordsForUserAction()
                loadRGBRecordsIntoEditor(records)
                loadRGBRecordsIntoCurrentPreview(records, announce: false)
                append("Loaded \(records.count) current RGB record(s) into the editor.")
            } catch {
                clearCurrentRGBReadback(status: "Current RGB read failed")
                append("Could not read current RGB from keyboard: \(error)")
            }
        }
    }

    func runRGBWrite(_ arguments: [String], title: String) {
        runLiveHIDCapture(arguments, title: title) {
            self.requestCurrentRGBRefresh()
        }
    }

    func applyRGBPreset(named preset: String, title: String) {
        runRGBWrite(["rgb-preset-apply", preset], title: title)
    }

    func setRGBKey() {
        runRGBWrite(["rgb-set-key", keyName, colorHex], title: "Set one key")
    }

    func setAllRGBKeys() {
        runRGBWrite(["rgb-set-all", fillHex], title: "Set all physical keys")
    }

    func clearRGB() {
        runRGBWrite(["rgb-clear"], title: "Clear physical key RGB")
    }

    func applyRGBMap() {
        runRGBWrite(["rgb-map"] + splitCommandLine(mapSpecs), title: "Set multiple RGB keys")
    }

    private func decodeRGBRecordsIntoEditor(_ text: String) {
        do {
            let records = try JSONDecoder().decode([AppRGBRecord].self, from: Data(text.utf8))
            loadRGBRecordsIntoEditor(records)
            append("Loaded \(records.count) RGB record(s) into the editor.")
        } catch {
            append("Could not parse RGB records JSON: \(error.localizedDescription)")
        }
    }

    func loadRGBRecordsIntoEditor(_ records: [AppRGBRecord]) {
        let specs = rgbSpecs(from: records)
        mapSpecs = specs.joined(separator: " ")
        combinedProfileIncludesRGBMap = !specs.isEmpty
    }

    func loadRGBRecordsIntoCurrentPreview(_ records: [AppRGBRecord], announce: Bool) {
        let specs = rgbSpecs(from: records)
        currentRGBSpecs = specs.joined(separator: " ")
        currentRGBReadbackLoaded = true
        currentRGBStatus = specs.isEmpty ? "Current RGB: all off" : "Current RGB: \(specs.count) lit key(s)"
        if let selectedColor = visualColorHex(for: selectedVisualKey) {
            colorHex = selectedColor
            keyColor = colorFromHex(selectedColor)
        } else {
            colorHex = "000000"
            keyColor = .black
        }
        if announce {
            append(specs.isEmpty ? "Synced current RGB: all physical keys are off." : "Synced current RGB for \(specs.count) visible key(s).")
        }
    }

    private func rgbSpecs(from records: [AppRGBRecord]) -> [String] {
        records.compactMap { record -> String? in
            guard
                let key = record.key?.trimmingCharacters(in: .whitespacesAndNewlines),
                !key.isEmpty
            else {
                return nil
            }
            let rgb = record.rgb.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
                .uppercased()
            guard rgb.count == 6, Int(rgb, radix: 16) != nil else {
                return nil
            }
            return "\(key)=\(rgb)"
        }
    }

    func listRGBBackups() {
        run(["rgb-backups"], title: "List RGB backups")
    }

    func restoreLatestRGBBackup() {
        runRGBWrite(["rgb-restore-latest"], title: "Restore latest RGB backup")
    }

    func createRGBProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = profileName
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let specs = splitCommandLine(self.mapSpecs)
            Task { @MainActor in
                self.run(["rgb-profile-create", url.path, "--fill=\(self.profileFillHex)"] + specs, title: "Create RGB profile")
            }
        }
    }

    func createRGBPresetProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(rgbPresetName)-rgb.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["rgb-preset-create", url.path, self.rgbPresetName], title: "Create RGB preset profile")
            }
        }
    }

    func applyRGBPreset() {
        applyRGBPreset(named: rgbPresetName, title: "Apply RGB preset")
    }

    func loadRGBPresetIntoEditor() {
        runCapture(["rgb-preset-show", rgbPresetName, "--json"], title: "Load RGB preset into editor") { text, status in
            guard status == 0 else { return }
            do {
                let preset = try JSONDecoder().decode(AppRGBPreset.self, from: Data(text.utf8))
                self.rgbPresetName = preset.name
                self.profileFillHex = preset.fill.uppercased()
                self.mapSpecs = preset.assignments.joined(separator: " ")
                self.combinedProfileIncludesRGBMap = true
                self.append("Loaded RGB preset \(preset.name) into the editor: \(preset.description)")
            } catch {
                self.append("Could not parse RGB preset JSON: \(error.localizedDescription)")
            }
        }
    }
}
