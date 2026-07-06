import SwiftUI
import AppKit
import Foundation
import GMK67Core
import Darwin

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
    @Published var currentRGBSpecs = ""
    @Published var currentRGBReadbackLoaded = false
    @Published var currentRGBStatus = "Waiting for hardware RGB readback"
    @Published var pressedVisualKeys: Set<String> = []
    @Published var lastKeyStatus = "No keys pressed"
    @Published var profileLibraryEntries: [AppProfileLibraryEntry] = []
    @Published var keymapLibraryEntries: [AppKeymapLibraryEntry] = []
    @Published var macroLibraryEntries: [AppMacroLibraryEntry] = []
    var didAutoRefreshDeviceStatus = false
    private var rgbPollTask: Task<Void, Never>?
    private var keyInputMonitor: GMK67KeyInputMonitor?
    private var isLiveRGBReadInFlight = false
    private var pendingRGBRefresh = false
    private var liveMonitoringGeneration = 0

    var appExecutablePath: String? {
        Bundle.main.executableURL?.path
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
        if deferUntilLiveRGBReadFinishes({ self.run(arguments, title: title) }) {
            return
        }

        let commandLine = (["gmk67"] + arguments).joined(separator: " ")
        append("\n$ \(commandLine)")
        if let title {
            append("# \(title)")
        }

        isRunning = true
        let workingDirectory = helperWorkingDirectory

        Task.detached(priority: .userInitiated) {
            let result = runDriverCommandInProcess(arguments, workingDirectory: workingDirectory)

            await MainActor.run {
                if !result.output.isEmpty {
                    self.append(result.output)
                }
                if result.status != 0 {
                    self.append("Command exited with status \(result.status).")
                }
                self.isRunning = false
            }
        }
    }

    func runCapture(_ arguments: [String], title: String? = nil, completion: @escaping (String, Int32) -> Void) {
        guard !isRunning else { return }
        if deferUntilLiveRGBReadFinishes({ self.runCapture(arguments, title: title, completion: completion) }) {
            return
        }

        let commandLine = (["gmk67"] + arguments).joined(separator: " ")
        append("\n$ \(commandLine)")
        if let title {
            append("# \(title)")
        }

        isRunning = true
        let workingDirectory = helperWorkingDirectory

        Task.detached(priority: .userInitiated) {
            let result = runDriverCommandInProcess(arguments, workingDirectory: workingDirectory)

            await MainActor.run {
                if result.status != 0 {
                    if !result.output.isEmpty {
                        self.append(result.output)
                    }
                    self.append("Command exited with status \(result.status).")
                }
                self.isRunning = false
                completion(result.output, result.status)
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

    func runLiveHIDCapture(_ arguments: [String], title: String? = nil, onSuccess: @escaping () -> Void) {
        guard deviceStatusKind == .ready else {
            append("Live keyboard access is not ready. Refresh device status, grant Input Monitoring if requested, quit/reopen the app, and reconnect the keyboard before running this command.")
            if deviceStatusKind == .permissionNeeded {
                append("Current blocker: macOS Input Monitoring permission is not granted.")
            }
            return
        }
        runCapture(arguments, title: title) { text, status in
            guard status == 0 else { return }
            if !text.isEmpty {
                self.append(text)
            }
            onSuccess()
        }
    }

    func visualColorHex(for key: String) -> String? {
        guard currentRGBReadbackLoaded else { return nil }
        return colorForKey(key, in: currentRGBSpecs)
    }

    func isVisualKeyPressed(_ key: String) -> Bool {
        visualKeyIsPressed(key, in: pressedVisualKeys)
    }

    private func deferUntilLiveRGBReadFinishes(_ action: @escaping @MainActor () -> Void) -> Bool {
        guard isLiveRGBReadInFlight else { return false }

        Task { @MainActor in
            for _ in 0..<40 {
                if !self.isLiveRGBReadInFlight {
                    action()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            self.append("Live RGB readback is still active. Try the command again in a moment.")
        }
        return true
    }
}

extension DriverModel {
    func startLiveMonitoring() {
        guard deviceStatusKind == .ready else {
            stopLiveMonitoring(rgbStatus: "Current RGB unavailable")
            return
        }

        let wasStopped = rgbPollTask == nil && keyInputMonitor == nil
        if wasStopped {
            liveMonitoringGeneration += 1
            clearCurrentRGBReadback(status: "Waiting for hardware RGB readback")
        }

        startKeyInputMonitoring()
        startRGBPollingIfNeeded()
        requestCurrentRGBRefresh()
    }

    func stopLiveMonitoring(rgbStatus: String = "Current RGB unavailable") {
        liveMonitoringGeneration += 1
        rgbPollTask?.cancel()
        rgbPollTask = nil
        keyInputMonitor?.stop()
        keyInputMonitor = nil
        isLiveRGBReadInFlight = false
        pendingRGBRefresh = false
        clearCurrentRGBReadback(status: rgbStatus)
        pressedVisualKeys = []
        lastKeyStatus = "No keys pressed"
    }

    func clearCurrentRGBReadback(status: String) {
        currentRGBSpecs = ""
        currentRGBReadbackLoaded = false
        currentRGBStatus = status
    }

    func requestCurrentRGBRefresh(announce: Bool = false) {
        Task { @MainActor in
            await refreshCurrentRGBPreview(announce: announce, force: true)
        }
    }

    func readCurrentRGBRecordsForApp() async throws -> [RGBRecord] {
        try await Task.detached(priority: .utility) {
            try readCurrentRGBRecords(writeIndex: 0, readIndex: 0, chunks: 9)
        }.value
    }

    func readCurrentRGBRecordsForUserAction() async throws -> [RGBRecord] {
        while isLiveRGBReadInFlight {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        isLiveRGBReadInFlight = true
        defer { isLiveRGBReadInFlight = false }
        return try await readCurrentRGBRecordsForApp()
    }

    private func startRGBPollingIfNeeded() {
        guard rgbPollTask == nil else { return }

        rgbPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCurrentRGBPreview(announce: false, force: false)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func startKeyInputMonitoring() {
        guard keyInputMonitor == nil else { return }

        let monitor = GMK67KeyInputMonitor { [weak self] pressedKeys in
            Task { @MainActor in
                self?.updatePressedVisualKeys(fromInputNames: pressedKeys)
            }
        }

        do {
            try monitor.start()
            keyInputMonitor = monitor
            pressedVisualKeys = []
            lastKeyStatus = "No keys pressed"
        } catch {
            keyInputMonitor = nil
            pressedVisualKeys = []
            lastKeyStatus = "Key monitor unavailable"
            append("Key monitor unavailable: \(error)")
        }
    }

    private func refreshCurrentRGBPreview(announce: Bool, force: Bool) async {
        guard deviceStatusKind == .ready else {
            if deviceStatusKind != .checking {
                clearCurrentRGBReadback(status: "Current RGB unavailable")
            }
            return
        }
        guard !isRunning else { return }
        guard !isLiveRGBReadInFlight else {
            pendingRGBRefresh = pendingRGBRefresh || force
            return
        }

        let generation = liveMonitoringGeneration
        isLiveRGBReadInFlight = true
        if !currentRGBReadbackLoaded {
            currentRGBStatus = "Reading current RGB..."
        }

        do {
            let records = try await readCurrentRGBRecordsForApp()
            isLiveRGBReadInFlight = false
            guard generation == liveMonitoringGeneration, deviceStatusKind == .ready else { return }
            loadRGBRecordsIntoCurrentPreview(records, announce: announce)
        } catch {
            isLiveRGBReadInFlight = false
            guard generation == liveMonitoringGeneration, deviceStatusKind == .ready else { return }
            clearCurrentRGBReadback(status: "Current RGB read failed")
            if announce {
                append("Current RGB read failed: \(error)")
            }
        }

        if pendingRGBRefresh {
            pendingRGBRefresh = false
            await refreshCurrentRGBPreview(announce: false, force: true)
        }
    }

    private func updatePressedVisualKeys(fromInputNames inputNames: Set<String>) {
        let visualKeys = Set(inputNames.compactMap { visualKeySpec(forInputName: $0) })
        pressedVisualKeys = visualKeys
        lastKeyStatus = visualKeyStatusText(for: visualKeys)
    }
}

private func runDriverCommandInProcess(_ arguments: [String], workingDirectory: URL) -> (output: String, status: Int32) {
    let originalDirectory = FileManager.default.currentDirectoryPath
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("gmk67-app-output-\(UUID().uuidString).log")

    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
        return ("Could not create command output capture file: \(outputURL.path)\n", 1)
    }

    fflush(nil)
    let originalStdout = dup(STDOUT_FILENO)
    let originalStderr = dup(STDERR_FILENO)
    guard originalStdout >= 0, originalStderr >= 0 else {
        outputHandle.closeFile()
        try? FileManager.default.removeItem(at: outputURL)
        return ("Could not capture command output: failed to duplicate stdout/stderr.\n", 1)
    }
    dup2(outputHandle.fileDescriptor, STDOUT_FILENO)
    dup2(outputHandle.fileDescriptor, STDERR_FILENO)

    var status: Int32 = 0
    let didChangeDirectory = FileManager.default.changeCurrentDirectoryPath(workingDirectory.path)

    do {
        try runGMK67Command(["gmk67"] + arguments)
    } catch {
        fputs("error: \(error)\n", stderr)
        status = 1
    }

    fflush(nil)
    outputHandle.synchronizeFile()
    dup2(originalStdout, STDOUT_FILENO)
    dup2(originalStderr, STDERR_FILENO)
    close(originalStdout)
    close(originalStderr)
    outputHandle.closeFile()
    if didChangeDirectory {
        FileManager.default.changeCurrentDirectoryPath(originalDirectory)
    }

    let data = (try? Data(contentsOf: outputURL)) ?? Data()
    try? FileManager.default.removeItem(at: outputURL)
    return (String(data: data, encoding: .utf8) ?? "", status)
}
