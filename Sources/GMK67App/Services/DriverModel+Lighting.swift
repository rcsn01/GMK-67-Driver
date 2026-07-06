import AppKit
import Foundation

@MainActor
extension DriverModel {
    func exportCustomLightingProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "custom-lighting-rgb.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let specs = splitCommandLine(self.lightingSpecs)
            let brightness = Int(self.lightingBrightnessPercent.rounded())
            Task { @MainActor in
                var command = ["lighting-custom-rgb-export", url.path]
                if brightness != 100 {
                    command.append("--brightness=\(brightness)%")
                }
                command += specs
                self.run(command, title: "Export custom lighting RGB profile")
            }
        }
    }

    func validateCustomLightingProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["lighting-custom-rgb-validate", url.path], title: "Validate custom lighting RGB profile")
            }
        }
    }

    func loadCustomLightingProfileIntoEditor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["lighting-custom-rgb-validate", url.path, "--json"], title: "Load custom lighting RGB into editor") { text, status in
                    guard status == 0 else { return }
                    do {
                        let records = try JSONDecoder().decode([AppRGBRecord].self, from: Data(text.utf8))
                        let specs = records.compactMap { record -> String? in
                            guard let key = record.key, !key.isEmpty else { return nil }
                            return "\(key)=\(record.rgb)"
                        }
                        self.lightingSpecs = specs.joined(separator: " ")
                        self.append("Loaded \(specs.count) custom-lighting RGB record(s) into the editor.")
                    } catch {
                        self.append("Could not parse custom-lighting RGB JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func applyCustomLightingProfile() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe candidate writes before applying a custom-lighting sequence. Lighting readback/backup is not proven yet.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runLiveHID(["lighting-custom-rgb-apply", url.path, "--unsafe-no-backup"], title: "Apply custom lighting RGB profile")
            }
        }
    }

    func exportLightingModeProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "lighting-mode.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let specs = splitCommandLine(self.lightingModeSpecs)
            Task { @MainActor in
                self.run(["lighting-mode-export", url.path] + specs, title: "Export lighting mode profile")
            }
        }
    }

    func exportLightingModePresetProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(lightingModePresetName)-lighting-mode.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["lighting-mode-preset-export", url.path, self.lightingModePresetName], title: "Export lighting mode preset")
            }
        }
    }

    func validateLightingModeProfile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["lighting-mode-validate", url.path], title: "Validate lighting mode profile")
            }
        }
    }

    func loadLightingModeProfileIntoEditor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["lighting-mode-validate", url.path, "--json"], title: "Load lighting mode into editor") { text, status in
                    guard status == 0 else { return }
                    do {
                        let records = try JSONDecoder().decode([AppByteRecord].self, from: Data(text.utf8))
                        let specs = records.compactMap { $0.spec }.filter { !$0.isEmpty }
                        self.lightingModeSpecs = specs.joined(separator: " ")
                        self.append("Loaded \(specs.count) lighting-mode record(s) into the editor.")
                    } catch {
                        self.append("Could not parse lighting-mode JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func applyLightingModePreset() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe candidate writes before applying a lighting-mode preset. Lighting readback/backup is not proven yet.")
            return
        }
        runLiveHID(["lighting-mode-preset-apply", lightingModePresetName, "--unsafe-no-backup"], title: "Apply lighting mode preset")
    }

    func exportLightingEffectProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(lightingEffectName)-lighting-effect.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["lighting-effect-export", url.path, self.lightingEffectName], title: "Export lighting effect")
            }
        }
    }

    func applyLightingEffect() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe candidate writes before applying a lighting effect. Lighting readback/backup is not proven yet.")
            return
        }
        runLiveHID(["lighting-effect-apply", lightingEffectName, "--unsafe-no-backup"], title: "Apply lighting effect")
    }

    func applyLightingModeProfile() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe candidate writes before applying a lighting-mode sequence. Lighting readback/backup is not proven yet.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runLiveHID(["lighting-mode-apply", url.path, "--unsafe-no-backup"], title: "Apply lighting mode profile")
            }
        }
    }
}
