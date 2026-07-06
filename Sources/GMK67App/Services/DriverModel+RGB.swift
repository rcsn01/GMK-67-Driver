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
                let readback = try await readCurrentRGBReadbackForUserAction()
                loadRGBReadbackIntoEditor(readback)
                loadRGBReadbackIntoCurrentPreview(readback, announce: false)
                append("Loaded \(readback.count) current RGB key color(s) into the editor.")
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

    func loadRGBReadbackIntoEditor(_ readback: [AppRGBLightReadback]) {
        let specs = rgbSpecs(from: readback)
        mapSpecs = specs.joined(separator: " ")
        combinedProfileIncludesRGBMap = !specs.isEmpty
    }

    func loadRGBReadbackIntoCurrentPreview(_ readback: [AppRGBLightReadback], announce: Bool) {
        let colors = visualRGBColors(from: readback)
        currentRGBColorsByVisualKeyToken = colors
        currentRGBReadbackLoaded = true
        currentRGBStatus = colors.isEmpty ? "Current RGB: all off" : "Current RGB: \(colors.count) visible lit key(s)"
        updateSelectedVisualRGBStatus()
        if let selectedColor = visualColorHex(for: selectedVisualKey) {
            colorHex = selectedColor
            keyColor = colorFromHex(selectedColor)
        } else {
            colorHex = "000000"
            keyColor = .black
        }
        if announce {
            append(colors.isEmpty ? "Synced current RGB: all physical keys are off." : "Synced current RGB for \(colors.count) visible key(s).")
        }
    }

    private func visualRGBColors(from readback: [AppRGBLightReadback]) -> [String: String] {
        var colors: [String: String] = [:]
        for record in readback where record.isLit {
            guard let key = visualKeySpec(forLightIndex: record.lightIndex, keyName: record.keyName) else {
                continue
            }
            colors[specKeyToken(key)] = record.rgbHex
        }
        return colors
    }

    func updateSelectedVisualRGBStatus() {
        guard currentRGBReadbackLoaded else {
            selectedVisualRGBStatus = "Selected RGB: not loaded"
            return
        }
        if let color = visualColorHex(for: selectedVisualKey) {
            selectedVisualRGBStatus = "\(selectedVisualKey) #\(color)"
        } else {
            selectedVisualRGBStatus = "\(selectedVisualKey): no live RGB"
        }
    }

    private func rgbSpecs(from readback: [AppRGBLightReadback]) -> [String] {
        readback.compactMap { record -> String? in
            guard record.isLit, let key = visualKeySpec(forLightIndex: record.lightIndex, keyName: record.keyName) else {
                return nil
            }
            return "\(key)=\(record.rgbHex)"
        }
    }

    private func rgbSpecs(from records: [AppRGBRecord]) -> [String] {
        records.compactMap { record -> String? in
            guard let key = rgbSpecTarget(for: record) else {
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

    private func rgbSpecTarget(for record: AppRGBRecord) -> String? {
        if let spec = record.spec?.trimmingCharacters(in: .whitespacesAndNewlines), !spec.isEmpty {
            return spec
        }

        guard let key = record.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }

        let token = specKeyToken(key)
        if token == "shift" || token == "alt" {
            return String(format: "0x%02X", record.index)
        }
        return visualKeySpec(forInputName: key) ?? key
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
