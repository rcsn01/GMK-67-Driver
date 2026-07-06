import AppKit
import Foundation

@MainActor
extension DriverModel {
    func exportAppLibraryBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gmk67-app-library.json"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["app-library-bundle-export", url.path], title: "Backup all app libraries")
            }
        }
    }

    func importAppLibraryBundle() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runCapture(["app-library-bundle-import", url.path], title: "Restore all app libraries") { text, status in
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status == 0 {
                        self.refreshProfileLibrary(title: nil, announce: false)
                        self.refreshKeymapLibrary(title: nil, announce: false)
                        self.refreshMacroLibrary(title: nil, announce: false)
                    }
                }
            }
        }
    }

    func saveDiagnosticsReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gmk67-diagnostics.txt"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["diagnostics", url.path], title: "Save diagnostics report")
            }
        }
    }

    func saveSupportBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gmk67-support"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.run(["support-bundle", url.path], title: "Save support bundle")
            }
        }
    }

    func factoryReset() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe keymap writes before running modeled factory reset. It includes an unbacked custom-keymap clear.")
            return
        }
        runLiveHID(["factory-reset", "--unsafe-no-backup"], title: "Modeled factory reset")
    }
}
