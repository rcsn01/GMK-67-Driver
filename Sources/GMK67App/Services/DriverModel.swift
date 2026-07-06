import SwiftUI
import AppKit
import Foundation

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
    var didAutoRefreshDeviceStatus = false

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
}
