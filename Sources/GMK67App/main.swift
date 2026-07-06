import SwiftUI
import AppKit
import CoreGraphics

@main
struct GMK67Application: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AppProfileLibraryEntry: Codable, Identifiable {
    let slot: String
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let customRGB: Int
    let customRemaps: Int

    var id: String { slot }
    var summary: String {
        let keymap = keymapPreset ?? "-"
        return "rgb=\(rgbPreset) keymap=\(keymap) custom-rgb=\(customRGB) custom-remaps=\(customRemaps)"
    }
}

struct AppCombinedProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let rgbFill: String?
    let rgbAssignments: [String]?
    let keymapRemaps: [String]?
}

struct AppMacroLibraryEntry: Codable, Identifiable {
    let slot: String
    let name: String
    let repeatCount: Int
    let eventCount: Int

    var id: String { slot }
}

struct AppKeymapLibraryEntry: Codable, Identifiable {
    let slot: String
    let name: String
    let remapCount: Int

    var id: String { slot }
}

struct AppKeymapProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let remaps: [String]
}

struct AppRGBPreset: Codable {
    let name: String
    let title: String
    let description: String
    let fill: String
    let assignments: [String]
}

struct AppKeymapPreset: Codable {
    let name: String
    let title: String
    let description: String
    let remaps: [String]
}

struct AppMacroProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let repeatCount: Int
    let events: [AppMacroEvent]
}

struct AppMacroEvent: Codable {
    let type: String
    let key: String?
    let usage: String?
    let text: String?
    let delayMS: Int?
}

struct AppRGBRecord: Codable {
    let chunk: Int
    let offset: Int
    let index: Int
    let key: String?
    let rgb: String
}

struct AppKeymapRecord: Codable {
    let offset: Int
    let keyIndex: Int
    let source: String?
    let target: String
    let targetUsage: String
    let targetEncoded: String
    let modifier: String?
    let modifierUsage: String?
    let modifierEncoded: String
    let record: String
    let spec: String?
    let warning: String?
}

struct AppByteRecord: Codable {
    let offset: Int
    let key: String?
    let value: String
    let spec: String?
}

enum DeviceStatusKind {
    case checking
    case ready
    case permissionNeeded
    case disconnected
    case partial
}

@MainActor
final class DriverModel: ObservableObject {
    @Published var output = "GMK67 Driver App\n"
    @Published var isRunning = false
    @Published var deviceStatusKind: DeviceStatusKind = .checking
    @Published var deviceStatusTitle = "Checking keyboard"
    @Published var deviceStatusDetail = "Connect the GMK67 by USB, then refresh status."
    @Published var keyName = "W"
    @Published var keyColor = Color.red
    @Published var colorHex = "FF0000"
    @Published var allKeysColor = Color.black
    @Published var fillHex = "000000"
    @Published var profileFillColor = Color.black
    @Published var profileFillHex = "000000"
    @Published var profileName = "rgb-profile.hex"
    @Published var mapSpecs = "W=FF0000 A=00FF00 S=0000FF D=00FFFF"
    @Published var rgbPresetName = "wasd"
    @Published var combinedProfileName = "Gaming"
    @Published var combinedProfileIncludesKeymap = true
    @Published var combinedProfileIncludesRGBMap = false
    @Published var combinedProfileIncludesKeymapSpecs = false
    @Published var profilePresetName = "gaming"
    @Published var profileLibrarySlot = "gaming"
    @Published var sourceKey = "A"
    @Published var targetKey = "B"
    @Published var modifierKey = ""
    @Published var keymapSpecs = "W=up A=left S=down D=right"
    @Published var keymapPresetName = "wasd-arrows"
    @Published var keymapProfileName = "WASD Arrows"
    @Published var keymapLibrarySlot = "wasd"
    @Published var unsafeKeymapWrites = false
    @Published var lightingSpecs = "W=FF0000 A=00FF00 S=0000FF D=00FFFF"
    @Published var lightingModeSpecs = "W=01 A=02 S=03 D=04"
    @Published var lightingModePresetName = "wasd-steps"
    @Published var lightingEffectName = "breath"
    @Published var macroName = "Combo"
    @Published var macroRepeatCount = "1"
    @Published var macroEventSpecs = "down:control key:C up:control delay:50"
    @Published var macroBuilderEventKind = "key"
    @Published var macroBuilderKey = "A"
    @Published var macroBuilderText = "hello world"
    @Published var macroBuilderDelay = "50"
    @Published var macroLibrarySlot = "combo"
    @Published var advancedCommand = "doctor"
    @Published var selectedVisualKey = "W"
    @Published var profileLibraryEntries: [AppProfileLibraryEntry] = []
    @Published var keymapLibraryEntries: [AppKeymapLibraryEntry] = []
    @Published var macroLibraryEntries: [AppMacroLibraryEntry] = []
    private var didAutoRefreshDeviceStatus = false

    private var helperURL: URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Helper/gmk67")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let sibling = executableDirectory?.appendingPathComponent("gmk67")
        if let sibling, FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let debug = cwd.appendingPathComponent(".build/debug/gmk67")
        if FileManager.default.isExecutableFile(atPath: debug.path) {
            return debug
        }

        return nil
    }

    private var bundledResourcesDirectory: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let vendorLayout = resourceURL.appendingPathComponent("Resources/vendor/KeyboardLayout.xml")
        return FileManager.default.fileExists(atPath: vendorLayout.path) ? resourceURL : nil
    }

    private var helperWorkingDirectory: URL {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = base.appendingPathComponent("GMK67", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
    }

    func append(_ text: String) {
        output += text
        if !output.hasSuffix("\n") {
            output += "\n"
        }
    }

    func clearOutput() {
        output = ""
    }

    func run(_ arguments: [String], title: String? = nil) {
        guard !isRunning else { return }
        guard let helperURL else {
            append("Could not find bundled gmk67 helper. Build with Scripts/build-app.sh or run swift build first.")
            return
        }

        let commandLine = ([helperURL.lastPathComponent] + arguments).joined(separator: " ")
        append("\n$ \(commandLine)")
        if let title {
            append("# \(title)")
        }

        isRunning = true
        let workingDirectory = helperWorkingDirectory
        let resourcesDirectory = bundledResourcesDirectory

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = helperURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            if let resourcesDirectory {
                var environment = ProcessInfo.processInfo.environment
                environment["GMK67_RESOURCES_DIR"] = resourcesDirectory.path
                process.environment = environment
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                let status = process.terminationStatus

                await MainActor.run {
                    if !text.isEmpty {
                        self.append(text)
                    }
                    if status != 0 {
                        self.append("Command exited with status \(status).")
                    }
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.append("Could not run helper: \(error.localizedDescription)")
                    self.isRunning = false
                }
            }
        }
    }

    func runCapture(_ arguments: [String], title: String? = nil, completion: @escaping (String, Int32) -> Void) {
        guard !isRunning else { return }
        guard let helperURL else {
            append("Could not find bundled gmk67 helper. Build with Scripts/build-app.sh or run swift build first.")
            return
        }

        let commandLine = ([helperURL.lastPathComponent] + arguments).joined(separator: " ")
        append("\n$ \(commandLine)")
        if let title {
            append("# \(title)")
        }

        isRunning = true
        let workingDirectory = helperWorkingDirectory
        let resourcesDirectory = bundledResourcesDirectory

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = helperURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            if let resourcesDirectory {
                var environment = ProcessInfo.processInfo.environment
                environment["GMK67_RESOURCES_DIR"] = resourcesDirectory.path
                process.environment = environment
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let outputText = String(data: outputData, encoding: .utf8) ?? ""
                let errorText = String(data: errorData, encoding: .utf8) ?? ""
                let status = process.terminationStatus

                await MainActor.run {
                    if !errorText.isEmpty {
                        self.append(errorText)
                    }
                    if status != 0 {
                        if !outputText.isEmpty {
                            self.append(outputText)
                        }
                        self.append("Command exited with status \(status).")
                    }
                    self.isRunning = false
                    completion(outputText, status)
                }
            } catch {
                await MainActor.run {
                    self.append("Could not run helper: \(error.localizedDescription)")
                    self.isRunning = false
                }
            }
        }
    }

    func runAdvanced() {
        let args = splitCommandLine(advancedCommand)
        guard !args.isEmpty else {
            append("Enter a command, for example: rgb-dump 0 0 9")
            return
        }
        run(args, title: "Advanced command")
    }

    func runLiveHID(_ arguments: [String], title: String? = nil) {
        guard deviceStatusKind == .ready else {
            append("Live keyboard access is not ready. Refresh device status, grant Input Monitoring if requested, quit/reopen the app, and reconnect the keyboard before running this command.")
            if deviceStatusKind == .permissionNeeded {
                append("Current blocker: macOS Input Monitoring permission is not granted.")
            }
            return
        }
        run(arguments, title: title)
    }

    func refreshDeviceStatusIfNeeded() {
        guard !didAutoRefreshDeviceStatus else { return }
        didAutoRefreshDeviceStatus = true
        refreshDeviceStatus(announce: false)
    }

    func refreshDeviceStatus(announce: Bool = true) {
        deviceStatusKind = .checking
        deviceStatusTitle = "Checking keyboard"
        deviceStatusDetail = "Reading USB and macOS permission status."
        runCapture(["readiness", "--open-check"], title: announce ? "Driver readiness" : nil) { text, status in
            self.updateDeviceStatus(from: text, exitStatus: status)
            if announce, !text.isEmpty {
                self.append(text)
            }
        }
    }

    private func updateDeviceStatus(from text: String, exitStatus: Int32) {
        if text.contains("Overall: READY") {
            deviceStatusKind = .ready
            deviceStatusTitle = "Keyboard ready"
            deviceStatusDetail = "USB and Input Monitoring permission are available for live RGB and keymap writes."
            return
        }

        if text.contains("USB device: OK") && text.contains("macOS HID open permission: FAIL") {
            deviceStatusKind = .permissionNeeded
            deviceStatusTitle = "Permission needed"
            deviceStatusDetail = "The GMK67 is connected, but macOS is blocking HID access. Enable Input Monitoring for GMK67 or the terminal/Codex host, then quit/reopen and reconnect the keyboard."
            return
        }

        if text.contains("USB device: FAIL") || text.localizedCaseInsensitiveContains("not found") {
            deviceStatusKind = .disconnected
            deviceStatusTitle = "Keyboard not detected"
            deviceStatusDetail = "Connect the GMK67 by USB and refresh status."
            return
        }

        deviceStatusKind = .partial
        deviceStatusTitle = exitStatus == 0 ? "Partially ready" : "Status check failed"
        deviceStatusDetail = "Open the output log for details before running live writes."
    }

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

    func requestInputMonitoringPermission() {
        append("\n$ macOS Input Monitoring permission request")
        let preflight = CGPreflightListenEventAccess()
        append("Current status: \(preflight ? "GRANTED" : "NOT GRANTED")")
        if preflight {
            return
        }

        let granted = CGRequestListenEventAccess()
        append("Request result: \(granted ? "GRANTED" : "NOT GRANTED")")
        if !granted {
            append("Enable GMK67 or its helper in System Settings > Privacy & Security > Input Monitoring, then quit/reopen the app and reconnect the keyboard.")
            openInputMonitoringSettings()
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            append("Could not build the Input Monitoring settings URL.")
            return
        }
        if NSWorkspace.shared.open(url) {
            append("Opened System Settings > Privacy & Security > Input Monitoring.")
        } else {
            append("Could not open System Settings. Open Privacy & Security > Input Monitoring manually.")
        }
    }

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
                self.runLiveHID(["rgb-restore", url.path], title: "Restore RGB profile")
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
        runCapture(["rgb-dump", "0", "0", "9", "--json"], title: "Load current RGB into editor") { text, status in
            guard status == 0 else { return }
            self.decodeRGBRecordsIntoEditor(text)
        }
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

    private func loadRGBRecordsIntoEditor(_ records: [AppRGBRecord]) {
        let specs = records.compactMap { record -> String? in
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
        mapSpecs = specs.joined(separator: " ")
        combinedProfileIncludesRGBMap = !specs.isEmpty
    }

    func listRGBBackups() {
        run(["rgb-backups"], title: "List RGB backups")
    }

    func restoreLatestRGBBackup() {
        runLiveHID(["rgb-restore-latest"], title: "Restore latest RGB backup")
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
        runLiveHID(["rgb-preset-apply", rgbPresetName], title: "Apply RGB preset")
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

    func selectVisualKey(_ key: String) {
        selectedVisualKey = key
        keyName = key
        sourceKey = key
        if let remap = remapForKey(key, in: keymapSpecs) {
            targetKey = remap.target
            modifierKey = remap.modifier ?? ""
        }
    }

    func assignSelectedKeyColor() {
        let key = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        mapSpecs = upsertSpec(mapSpecs, key: key, value: colorHex)
        keyName = key
        combinedProfileIncludesRGBMap = true
    }

    func clearSelectedKeyColor() {
        let key = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        mapSpecs = removeSpec(mapSpecs, key: key)
    }

    func assignSelectedKeyRemap() {
        let source = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else { return }
        let modifier = modifierKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = modifier.isEmpty ? target : "\(target):\(modifier)"
        keymapSpecs = upsertSpec(keymapSpecs, key: source, value: value)
        sourceKey = source
        combinedProfileIncludesKeymapSpecs = true
    }

    func clearSelectedKeyRemap() {
        let key = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keymapSpecs = removeSpec(keymapSpecs, key: key)
        if sourceKey.caseInsensitiveCompare(key) == .orderedSame {
            targetKey = ""
            modifierKey = ""
        }
    }

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

    private func refreshProfileLibrary(title: String? = nil, announce: Bool) {
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

    private func refreshMacroLibrary(title: String? = nil, announce: Bool) {
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

    func applyKeymapProfile() {
        guard unsafeKeymapWrites else {
            append("Enable unsafe keymap writes before applying a keymap profile. Keymap backup/readback is not proven yet.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.runLiveHID(["keymap-file-apply", url.path, "--unsafe-no-backup"], title: "Apply keymap profile")
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

    private func refreshKeymapLibrary(title: String? = nil, announce: Bool) {
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

    func exportCustomLightingProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "custom-lighting-rgb.hex"
        panel.allowedContentTypes = []
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let specs = splitCommandLine(self.lightingSpecs)
            Task { @MainActor in
                self.run(["lighting-custom-rgb-export", url.path] + specs, title: "Export custom lighting RGB profile")
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

struct ContentView: View {
    @StateObject private var model = DriverModel()

    var body: some View {
        NavigationSplitView {
            List {
                Section("Device") {
                    ActionButton("Readiness", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                        model.run(["readiness"], title: "Driver readiness")
                    }
                    ActionButton("Doctor", systemImage: "stethoscope") {
                        model.run(["doctor"], title: "Read-only diagnostics")
                    }
                    ActionButton("Open Check", systemImage: "checkmark.shield") {
                        model.run(["doctor", "--open-check"], title: "macOS HID open permission")
                    }
                    ActionButton("Permission", systemImage: "lock.shield") {
                        model.requestInputMonitoringPermission()
                    }
                    ActionButton("Settings", systemImage: "gearshape") {
                        model.openInputMonitoringSettings()
                    }
                    ActionButton("List Interfaces", systemImage: "list.bullet.rectangle") {
                        model.run(["list"], title: "Configuration interfaces")
                    }
                    ActionButton("Dump Layout", systemImage: "keyboard") {
                        model.run(["dump-layout"], title: "Vendor layout")
                    }
                    ActionButton("Key Test", systemImage: "keyboard.badge.ellipsis") {
                        model.runLiveHID(["key-test", "0", "8", "10"], title: "Decoded key tester")
                    }
                    ActionButton("Protocol", systemImage: "doc.text.magnifyingglass") {
                        model.run(["protocol-candidates"], title: "Protocol candidates")
                    }
                    ActionButton("Test Plan", systemImage: "checklist") {
                        model.run(["validation-plan"], title: "Physical validation plan")
                    }
                    ActionButton("Save Report", systemImage: "square.and.arrow.down") {
                        model.saveDiagnosticsReport()
                    }
                    ActionButton("Support Bundle", systemImage: "folder.badge.gearshape") {
                        model.saveSupportBundle()
                    }
                    ActionButton("Factory Reset", systemImage: "exclamationmark.triangle") {
                        model.factoryReset()
                    }
                }

                Section("RGB") {
                    ActionButton("Dump RGB", systemImage: "tablecells") {
                        model.runLiveHID(["rgb-dump", "0", "0", "9"], title: "Current RGB table")
                    }
                    ActionButton("Save RGB", systemImage: "square.and.arrow.down") {
                        model.saveRGBProfile()
                    }
                    ActionButton("Restore RGB", systemImage: "square.and.arrow.up") {
                        model.restoreRGBProfile()
                    }
                    ActionButton("Backups", systemImage: "clock.arrow.circlepath") {
                        model.listRGBBackups()
                    }
                    ActionButton("Restore Latest", systemImage: "arrow.uturn.backward") {
                        model.restoreLatestRGBBackup()
                    }
                }

                Section("Profiles") {
                    ActionButton("Create", systemImage: "doc.badge.plus") {
                        model.createCombinedProfile()
                    }
                    ActionButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateCombinedProfile()
                    }
                    ActionButton("Apply", systemImage: "rectangle.stack.badge.play") {
                        model.applyCombinedProfile()
                    }
                }

                Section("Keymap") {
                    ActionButton("Validate File", systemImage: "doc.badge.gearshape") {
                        model.validateKeymapProfile()
                    }
                    ActionButton("Export Profile", systemImage: "doc.badge.plus") {
                        model.exportKeymapProfile()
                    }
                    ActionButton("Apply Profile", systemImage: "exclamationmark.triangle") {
                        model.applyKeymapProfile()
                    }
                }
            }
            .navigationTitle("GMK67")
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DeviceStatusBanner(model: model)
                        DevicePanel(model: model)
                        VisualKeyboardPanel(model: model)
                        ProfilePanel(model: model)
                        RGBPanel(model: model)
                        KeymapPanel(model: model)
                        MacroPanel(model: model)
                        LightingPanel(model: model)
                        AdvancedPanel(model: model)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                ConsoleView(text: model.output, isRunning: model.isRunning) {
                    model.clearOutput()
                }
                .frame(minHeight: 220)
            }
        }
        .task {
            model.refreshDeviceStatusIfNeeded()
        }
    }
}

struct DeviceStatusBanner: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.deviceStatusTitle)
                    .font(.headline)
                Text(model.deviceStatusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if model.deviceStatusKind == .permissionNeeded {
                CommandButton("Permission", systemImage: "lock.shield") {
                    model.requestInputMonitoringPermission()
                }
                CommandButton("Settings", systemImage: "gearshape") {
                    model.openInputMonitoringSettings()
                }
            }
            CommandButton("Refresh", systemImage: "arrow.clockwise") {
                model.refreshDeviceStatus()
            }
        }
        .padding(14)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch model.deviceStatusKind {
        case .checking:
            return "clock"
        case .ready:
            return "checkmark.seal.fill"
        case .permissionNeeded:
            return "lock.trianglebadge.exclamationmark"
        case .disconnected:
            return "cable.connector.slash"
        case .partial:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch model.deviceStatusKind {
        case .checking:
            return .accentColor
        case .ready:
            return .green
        case .permissionNeeded:
            return .orange
        case .disconnected:
            return .red
        case .partial:
            return .yellow
        }
    }
}

struct DevicePanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Device") {
            HStack {
                CommandButton("Refresh", systemImage: "arrow.clockwise") {
                    model.refreshDeviceStatus()
                }
                CommandButton("Readiness", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                    model.run(["readiness"], title: "Driver readiness")
                }
                CommandButton("Doctor", systemImage: "stethoscope") {
                    model.run(["doctor"], title: "Read-only diagnostics")
                }
                CommandButton("Open Check", systemImage: "checkmark.shield") {
                    model.run(["doctor", "--open-check"], title: "macOS HID open permission")
                }
                CommandButton("Permission", systemImage: "lock.shield") {
                    model.requestInputMonitoringPermission()
                }
                CommandButton("Settings", systemImage: "gearshape") {
                    model.openInputMonitoringSettings()
                }
                CommandButton("List", systemImage: "list.bullet.rectangle") {
                    model.run(["list"], title: "Configuration interfaces")
                }
                CommandButton("Self Test", systemImage: "checkmark.seal") {
                    model.run(["self-test"], title: "Offline self-test")
                }
                CommandButton("Key Test", systemImage: "keyboard.badge.ellipsis") {
                    model.runLiveHID(["key-test", "0", "8", "10"], title: "Decoded key tester")
                }
                CommandButton("Protocol", systemImage: "doc.text.magnifyingglass") {
                    model.run(["protocol-candidates"], title: "Protocol candidates")
                }
                CommandButton("Test Plan", systemImage: "checklist") {
                    model.run(["validation-plan"], title: "Physical validation plan")
                }
                CommandButton("Save Report", systemImage: "square.and.arrow.down") {
                    model.saveDiagnosticsReport()
                }
                CommandButton("Support Bundle", systemImage: "folder.badge.gearshape") {
                    model.saveSupportBundle()
                }
            }
        }
    }
}

struct VisualKeyboardPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Keyboard") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visualKeyboardRows) { row in
                        HStack(spacing: 6) {
                            ForEach(row.keys) { key in
                                VisualKeyButton(
                                    key: key,
                                    isSelected: model.selectedVisualKey.caseInsensitiveCompare(key.spec) == .orderedSame,
                                    colorHex: visualColorForKey(key.spec, in: model.mapSpecs, fillHex: model.profileFillHex),
                                    remap: remapForKey(key.spec, in: model.keymapSpecs)
                                ) {
                                    model.selectVisualKey(key.spec)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("Selected")
                        Text(model.selectedVisualKey)
                            .monospaced()
                            .frame(width: 90, alignment: .leading)
                        ColorPicker("", selection: Binding(
                            get: { model.keyColor },
                            set: {
                                model.keyColor = $0
                                model.colorHex = rgbHex($0)
                            }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44)
                        TextField("FF0000", text: $model.colorHex)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        CommandButton("Color", systemImage: "paintbrush") {
                            model.assignSelectedKeyColor()
                        }
                        CommandButton("No Color", systemImage: "lightswitch.off") {
                            model.clearSelectedKeyColor()
                        }
                    }

                    GridRow {
                        Text("Remap")
                        Text(model.selectedVisualKey)
                            .monospaced()
                            .frame(width: 90, alignment: .leading)
                        Text("Target")
                        TextField("B", text: $model.targetKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        Text("Modifier")
                        TextField("shift", text: $model.modifierKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        CommandButton("Set", systemImage: "arrow.triangle.branch") {
                            model.assignSelectedKeyRemap()
                        }
                        CommandButton("Clear", systemImage: "xmark.circle") {
                            model.clearSelectedKeyRemap()
                        }
                    }
                }
            }
        }
    }
}

struct VisualKey: Identifiable {
    let id = UUID()
    let spec: String
    let label: String
    let width: CGFloat
}

struct VisualKeyRow: Identifiable {
    let id = UUID()
    let keys: [VisualKey]
}

private func vk(_ spec: String, _ label: String? = nil, width: CGFloat = 38) -> VisualKey {
    VisualKey(spec: spec, label: label ?? spec, width: width)
}

private let visualKeyboardRows: [VisualKeyRow] = [
    VisualKeyRow(keys: [
        vk("esc", width: 38), vk("1"), vk("2"), vk("3"), vk("4"), vk("5"), vk("6"), vk("7"),
        vk("8"), vk("9"), vk("0"), vk("-"), vk("equal", "=", width: 38), vk("backspace", "backspace", width: 86)
    ]),
    VisualKeyRow(keys: [
        vk("tab", width: 60), vk("Q"), vk("W"), vk("E"), vk("R"), vk("T"), vk("Y"), vk("U"),
        vk("I"), vk("O"), vk("P"), vk("["), vk("]"), vk("\\|", "\\|", width: 64), vk("del")
    ]),
    VisualKeyRow(keys: [
        vk("Caps", width: 70), vk("A"), vk("S"), vk("D"), vk("F"), vk("G"), vk("H"), vk("J"),
        vk("K"), vk("L"), vk(";"), vk("quote", "'\"", width: 38), vk("enter", width: 96), vk("pageup", "pg up")
    ]),
    VisualKeyRow(keys: [
        vk("0x49", "shift", width: 94), vk("Z"), vk("X"), vk("C"), vk("V"), vk("B"), vk("N"), vk("M"),
        vk("comma", "<"), vk("period", ">"), vk("slash", "?"), vk("0x54", "shift", width: 70), vk("up", "up"), vk("pagedown", "pg dn")
    ]),
    VisualKeyRow(keys: [
        vk("control", "ctrl", width: 48), vk("win", width: 48), vk("0x5D", "alt", width: 48),
        vk("space", width: 286), vk("0x5F", "alt", width: 48), vk("fn", width: 48),
        vk("left", "left"), vk("down", "down"), vk("right", "right")
    ])
]

struct VisualKeyButton: View {
    let key: VisualKey
    let isSelected: Bool
    let colorHex: String?
    let remap: VisualRemap?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(keyFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
                    )
                Text(key.label)
                    .font(.system(size: key.width > 70 ? 10 : 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if let remap {
                    Text(remap.badge)
                        .font(.system(size: key.width > 70 ? 9 : 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if let colorHex {
                    Rectangle()
                        .fill(colorFromHex(colorHex))
                        .frame(height: 5)
                        .clipShape(.rect(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                }
            }
            .frame(width: key.width, height: 38)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var keyFill: Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)
    }

    private var helpText: String {
        if let remap {
            return "\(key.label) (\(key.spec)) -> \(remap.target)\(remap.modifier.map { " + \($0)" } ?? "")"
        }
        return key.label == key.spec ? key.spec : "\(key.label) (\(key.spec))"
    }
}

struct ProfilePanel: View {
    @ObservedObject var model: DriverModel
    private let presets = ["gaming", "navigation", "coding", "editing", "ocean-rgb", "lights-off"]

    var body: some View {
        Panel("Keyboard Profile") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
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

                HStack {
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

                HStack {
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

struct RGBPanel: View {
    @ObservedObject var model: DriverModel
    private let presets = ["off", "white", "red", "blue", "wasd", "arrows", "coding", "rainbow", "ocean", "sunset"]

    var body: some View {
        Panel("RGB") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Preset")
                    Picker("", selection: $model.rgbPresetName) {
                        ForEach(presets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    CommandButton("Apply", systemImage: "paintpalette") {
                        model.applyRGBPreset()
                    }
                    CommandButton("Create File", systemImage: "doc.badge.plus") {
                        model.createRGBPresetProfile()
                    }
                    CommandButton("Load", systemImage: "square.and.arrow.down.on.square") {
                        model.loadRGBPresetIntoEditor()
                    }
                }

                GridRow {
                    Text("Key")
                    TextField("W", text: $model.keyName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("Color")
                    ColorPicker("", selection: Binding(
                        get: { model.keyColor },
                        set: {
                            model.keyColor = $0
                            model.colorHex = rgbHex($0)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
                    TextField("FF0000", text: $model.colorHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    CommandButton("Set Key", systemImage: "paintbrush") {
                        model.runLiveHID(["rgb-set-key", model.keyName, model.colorHex], title: "Set one key")
                    }
                }

                GridRow {
                    Text("All Keys")
                    ColorPicker("", selection: Binding(
                        get: { model.allKeysColor },
                        set: {
                            model.allKeysColor = $0
                            model.fillHex = rgbHex($0)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
                    TextField("000000", text: $model.fillHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    CommandButton("Set All", systemImage: "paintpalette") {
                        model.runLiveHID(["rgb-set-all", model.fillHex], title: "Set all physical keys")
                    }
                    CommandButton("Clear", systemImage: "lightswitch.off") {
                        model.runLiveHID(["rgb-clear"], title: "Clear physical key RGB")
                    }
                    EmptyView()
                }

                GridRow {
                    Text("Map")
                    TextField("W=FF0000 A=00FF00", text: $model.mapSpecs)
                        .textFieldStyle(.roundedBorder)
                        .gridCellColumns(3)
                    CommandButton("Apply Map", systemImage: "rectangle.3.group") {
                        model.runLiveHID(["rgb-map"] + splitCommandLine(model.mapSpecs), title: "Set multiple RGB keys")
                    }
                }

                GridRow {
                    Text("Profile Fill")
                    ColorPicker("", selection: Binding(
                        get: { model.profileFillColor },
                        set: {
                            model.profileFillColor = $0
                            model.profileFillHex = rgbHex($0)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
                    TextField("000000", text: $model.profileFillHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    CommandButton("Create", systemImage: "doc.badge.plus") {
                        model.createRGBProfile()
                    }
                    EmptyView()
                }

                GridRow {
                    Text("Profiles")
                    CommandButton("Save", systemImage: "square.and.arrow.down") {
                        model.saveRGBProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateRGBProfile()
                    }
                    CommandButton("Restore", systemImage: "square.and.arrow.up") {
                        model.restoreRGBProfile()
                    }
                    EmptyView()
                }

                GridRow {
                    Text("Editor")
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadRGBProfileIntoEditor()
                    }
                    CommandButton("Load Current", systemImage: "keyboard.badge.ellipsis") {
                        model.loadCurrentRGBIntoEditor()
                    }
                    EmptyView()
                    EmptyView()
                }

                GridRow {
                    Text("Backups")
                    CommandButton("List", systemImage: "clock.arrow.circlepath") {
                        model.listRGBBackups()
                    }
                    CommandButton("Restore Latest", systemImage: "arrow.uturn.backward") {
                        model.restoreLatestRGBBackup()
                    }
                    EmptyView()
                    EmptyView()
                }
            }
        }
    }
}

func rgbHex(_ color: Color) -> String {
    let nsColor = NSColor(color)
    guard let rgb = nsColor.usingColorSpace(.sRGB) else {
        return "000000"
    }

    let red = UInt8(max(0, min(255, Int((rgb.redComponent * 255).rounded()))))
    let green = UInt8(max(0, min(255, Int((rgb.greenComponent * 255).rounded()))))
    let blue = UInt8(max(0, min(255, Int((rgb.blueComponent * 255).rounded()))))
    return String(format: "%02X%02X%02X", red, green, blue)
}

func colorFromHex(_ hex: String) -> Color {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
        return Color(nsColor: .separatorColor)
    }

    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
}

func colorForKey(_ key: String, in specs: String) -> String? {
    valueForSpecKey(key, in: specs).flatMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        return trimmed.count == 6 && Int(trimmed, radix: 16) != nil ? trimmed.uppercased() : nil
    }
}

func visualColorForKey(_ key: String, in specs: String, fillHex: String) -> String? {
    if let explicit = colorForKey(key, in: specs) {
        return explicit
    }

    let fill = fillHex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
    guard fill.count == 6, Int(fill, radix: 16) != nil, fill != "000000" else {
        return nil
    }
    return fill
}

struct VisualRemap {
    let target: String
    let modifier: String?

    var badge: String {
        let targetLabel = shortKeyLabel(target)
        guard let modifier, !modifier.isEmpty else {
            return "->\(targetLabel)"
        }
        return "\(shortKeyLabel(modifier))+\(targetLabel)"
    }
}

func remapForKey(_ key: String, in specs: String) -> VisualRemap? {
    guard let value = valueForSpecKey(key, in: specs) else { return nil }
    let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard let targetPart = parts.first else { return nil }
    let target = String(targetPart).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty else { return nil }
    let modifier: String?
    if parts.count == 2 {
        let parsed = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        modifier = parsed.isEmpty ? nil : parsed
    } else {
        modifier = nil
    }
    return VisualRemap(target: target, modifier: modifier)
}

private func shortKeyLabel(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch specKeyToken(normalized) {
    case "control", "ctrl":
        return "C"
    case "shift":
        return "S"
    case "alt", "option":
        return "A"
    case "command", "cmd", "win":
        return "M"
    case "left":
        return "L"
    case "right":
        return "R"
    case "up":
        return "U"
    case "down":
        return "D"
    case "escape":
        return "Esc"
    case "backspace":
        return "Bksp"
    case "pageup":
        return "PgU"
    case "pagedown":
        return "PgD"
    default:
        if normalized.count <= 4 {
            return normalized
        }
        return String(normalized.prefix(4))
    }
}

func upsertSpec(_ specs: String, key: String, value: String) -> String {
    let normalizedKey = specKeyToken(key)
    let replacement = "\(key)=\(value)"
    var didReplace = false
    var tokens = splitCommandLine(specs).compactMap { token -> String? in
        guard let equalsIndex = token.firstIndex(of: "=") else { return token }
        let existingKey = String(token[..<equalsIndex])
        if specKeyToken(existingKey) == normalizedKey {
            if didReplace {
                return nil
            }
            didReplace = true
            return replacement
        }
        return token
    }

    if !didReplace {
        tokens.append(replacement)
    }
    return tokens.joined(separator: " ")
}

func removeSpec(_ specs: String, key: String) -> String {
    let normalizedKey = specKeyToken(key)
    return splitCommandLine(specs).filter { token in
        guard let equalsIndex = token.firstIndex(of: "=") else { return true }
        let existingKey = String(token[..<equalsIndex])
        return specKeyToken(existingKey) != normalizedKey
    }.joined(separator: " ")
}

private func valueForSpecKey(_ key: String, in specs: String) -> String? {
    let normalizedKey = specKeyToken(key)
    for token in splitCommandLine(specs) {
        guard let equalsIndex = token.firstIndex(of: "=") else { continue }
        let existingKey = String(token[..<equalsIndex])
        guard specKeyToken(existingKey) == normalizedKey else { continue }
        return String(token[token.index(after: equalsIndex)...])
    }
    return nil
}

private func specKeyToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
}

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

struct MacroPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Macros") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
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

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
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

                    GridRow {
                        Text("Events")
                        TextField("down:control key:C up:control delay:50", text: $model.macroEventSpecs)
                            .textFieldStyle(.roundedBorder)
                            .gridCellColumns(5)
                    }
                }

                HStack {
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

struct LightingPanel: View {
    @ObservedObject var model: DriverModel
    private let lightingEffects = [
        "static", "single-on", "single-off", "glittering", "falling", "colourful",
        "breath", "spectrum", "outward", "scrolling", "rolling", "rotating",
        "explode", "launch", "ripples", "flowing", "pulsating", "tilt",
        "shuttle", "led-off", "inwards", "floweriness"
    ]
    private let lightingModePresets = ["empty", "wasd-steps", "nav-steps", "row-steps"]

    var body: some View {
        Panel("Lighting") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Custom RGB")
                    TextField("W=FF0000 A=00FF00", text: $model.lightingSpecs)
                        .textFieldStyle(.roundedBorder)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportCustomLightingProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateCustomLightingProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadCustomLightingProfileIntoEditor()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyCustomLightingProfile()
                    }
                }

                HStack {
                    Text("Effect Preset")
                    Picker("", selection: $model.lightingEffectName) {
                        ForEach(lightingEffects, id: \.self) { effect in
                            Text(effect).tag(effect)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportLightingEffectProfile()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyLightingEffect()
                    }
                }

                HStack {
                    Text("Mode Preset")
                    Picker("", selection: $model.lightingModePresetName) {
                        ForEach(lightingModePresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportLightingModePresetProfile()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyLightingModePreset()
                    }
                }

                HStack {
                    Text("Mode Table")
                    TextField("W=01 A=02", text: $model.lightingModeSpecs)
                        .textFieldStyle(.roundedBorder)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportLightingModeProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateLightingModeProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadLightingModeProfileIntoEditor()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyLightingModeProfile()
                    }
                }

                Toggle("Allow unsafe lighting writes", isOn: $model.unsafeKeymapWrites)
                    .toggleStyle(.checkbox)

                Text("Candidate lighting writes require the unsafe toggle because lighting readback/backup is not proven yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.deviceStatusKind != .ready {
                    Text("Live lighting writes are disabled until the Device status is ready. Export and validate commands remain available.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

struct AdvancedPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Advanced") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("All Libraries")
                    CommandButton("Backup", systemImage: "externaldrive.badge.timemachine") {
                        model.exportAppLibraryBundle()
                    }
                    CommandButton("Restore", systemImage: "externaldrive.badge.plus") {
                        model.importAppLibraryBundle()
                    }
                    Text("Profiles, keymaps, and macros in one portable JSON bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("doctor", text: $model.advancedCommand)
                        .textFieldStyle(.roundedBorder)
                    CommandButton("Run", systemImage: "terminal") {
                        model.runAdvanced()
                    }
                }
                Text("Enter any helper command without the gmk67 prefix, for example: feature-scan 0 00 FF 64")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ConsoleView: View {
    let text: String
    let isRunning: Bool
    let clear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Output")
                    .font(.headline)
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 18, height: 18)
                }
                Spacer()
                Button("Clear", action: clear)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollView {
                Text(text.isEmpty ? "No output yet." : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            content
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

func splitCommandLine(_ text: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    var isEscaping = false

    for character in text {
        if isEscaping {
            current.append(character)
            isEscaping = false
            continue
        }

        if character == "\\" {
            isEscaping = true
            continue
        }

        if character == "\"" || character == "'" {
            if quote == character {
                quote = nil
            } else if quote == nil {
                quote = character
            } else {
                current.append(character)
            }
            continue
        }

        if character.isWhitespace && quote == nil {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
            continue
        }

        current.append(character)
    }

    if !current.isEmpty {
        result.append(current)
    }
    return result
}

func quoteCommandToken(_ token: String) -> String {
    guard token.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }) else {
        return token
    }
    var quoted = "\""
    for character in token {
        if character == "\"" || character == "\\" {
            quoted.append("\\")
        }
        quoted.append(character)
    }
    quoted.append("\"")
    return quoted
}
