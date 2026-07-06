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
    @Published var rgbThemeName = "rainbow"
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
    @Published var lightingBrightnessPercent = 100.0
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
    @Published var currentRGBColorsByVisualKeyToken: [String: String] = [:]
    @Published var currentRawRGBColorsByVisualKeyToken: [String: String] = [:]
    @Published var currentRGBReadbackLoaded = false
    @Published var currentRGBStatus = "Waiting for hardware RGB readback"
    @Published var selectedVisualRGBStatus = "Selected RGB: not loaded"
    @Published var pressedVisualKeys: Set<String> = []
    @Published var lastKeyStatus = "No keys pressed"
    @Published var profileLibraryEntries: [AppProfileLibraryEntry] = []
    @Published var keymapLibraryEntries: [AppKeymapLibraryEntry] = []
    @Published var macroLibraryEntries: [AppMacroLibraryEntry] = []
    var didAutoRefreshDeviceStatus = false
    private var keyInputMonitor: ReadOnlyKeyInputMonitor?
    private var rgbRefreshTask: Task<Void, Never>?
    private var pendingRGBRefresh = false
    private var pendingRGBRefreshAnnounce = false
    private var lastKeyInputAt = Date.distantPast
    private var isLiveRGBReadInFlight = false

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
        return currentRGBColorsByVisualKeyToken[specKeyToken(key)]
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

        if !currentRGBReadbackLoaded {
            clearCurrentRGBReadback(status: "Waiting for hardware RGB readback")
        }
        startKeyInputMonitoring()
        lastKeyInputAt = Date()
        pressedVisualKeys = []
        requestCurrentRGBRefresh()
    }

    func stopLiveMonitoring(rgbStatus: String = "Current RGB unavailable") {
        rgbRefreshTask?.cancel()
        rgbRefreshTask = nil
        pendingRGBRefresh = false
        pendingRGBRefreshAnnounce = false
        keyInputMonitor?.stop()
        keyInputMonitor = nil
        isLiveRGBReadInFlight = false
        clearCurrentRGBReadback(status: rgbStatus)
        pressedVisualKeys = []
        lastKeyStatus = "No keys pressed"
    }

    func clearCurrentRGBReadback(status: String) {
        currentRGBColorsByVisualKeyToken = [:]
        currentRawRGBColorsByVisualKeyToken = [:]
        currentRGBReadbackLoaded = false
        currentRGBStatus = status
        selectedVisualRGBStatus = "Selected RGB: not loaded"
    }

    func requestCurrentRGBRefresh(announce: Bool = false) {
        guard deviceStatusKind == .ready else {
            clearCurrentRGBReadback(status: "Current RGB unavailable")
            return
        }
        pendingRGBRefresh = true
        pendingRGBRefreshAnnounce = pendingRGBRefreshAnnounce || announce
        if !currentRGBReadbackLoaded {
            currentRGBStatus = "Waiting for hardware RGB readback"
        }
        scheduleRGBRefreshIfNeeded()
    }

    func requestCurrentRGBRefreshAfterWrite() {
        requestCurrentRGBRefresh()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.requestCurrentRGBRefresh()
        }
    }

    func readCurrentRGBReadbackForUserAction() async throws -> [RGBLightReadback] {
        while isLiveRGBReadInFlight {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        await waitForKeyInputIdle()
        isLiveRGBReadInFlight = true
        defer { isLiveRGBReadInFlight = false }
        return try await Task.detached(priority: .utility) {
            try readCurrentRGBReadback(writeIndex: 0, readIndex: 0, chunks: 9)
        }.value
    }

    private func startKeyInputMonitoring() {
        guard keyInputMonitor == nil else { return }

        let monitor = ReadOnlyKeyInputMonitor { [weak self] pressedKeys in
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
            lastKeyStatus = "Read-only key preview unavailable"
            append("Key monitor unavailable: \(error)")
        }
    }

    private func scheduleRGBRefreshIfNeeded() {
        guard rgbRefreshTask == nil else { return }

        rgbRefreshTask = Task { @MainActor in
            defer { self.rgbRefreshTask = nil }
            while self.pendingRGBRefresh, !Task.isCancelled {
                self.pendingRGBRefresh = false
                let announce = self.pendingRGBRefreshAnnounce
                self.pendingRGBRefreshAnnounce = false
                await self.refreshCurrentRGBPreviewWhenIdle(announce: announce)
            }
        }
    }

    private func refreshCurrentRGBPreviewWhenIdle(announce: Bool) async {
        guard deviceStatusKind == .ready else {
            clearCurrentRGBReadback(status: "Current RGB unavailable")
            return
        }
        guard !isRunning else {
            pendingRGBRefresh = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            return
        }

        await waitForKeyInputIdle()
        guard deviceStatusKind == .ready, !isRunning, !Task.isCancelled else { return }
        guard !isLiveRGBReadInFlight else {
            pendingRGBRefresh = true
            return
        }

        isLiveRGBReadInFlight = true
        if !currentRGBReadbackLoaded {
            currentRGBStatus = "Reading current RGB..."
        }

        do {
            let readback = try await Task.detached(priority: .utility) {
                try readCurrentRGBReadback(writeIndex: 0, readIndex: 0, chunks: 9)
            }.value
            isLiveRGBReadInFlight = false
            guard deviceStatusKind == .ready, !Task.isCancelled else { return }
            loadRGBReadbackIntoCurrentPreview(readback, announce: announce)
        } catch {
            isLiveRGBReadInFlight = false
            guard deviceStatusKind == .ready, !Task.isCancelled else { return }
            clearCurrentRGBReadback(status: "Current RGB read failed")
            if announce {
                append("Current RGB read failed: \(error)")
            }
        }
    }

    private func waitForKeyInputIdle() async {
        while !Task.isCancelled {
            let idleTime = Date().timeIntervalSince(lastKeyInputAt)
            if pressedVisualKeys.isEmpty, idleTime >= 0.75 {
                return
            }
            if currentRGBReadbackLoaded {
                currentRGBStatus = "Current RGB: paused while typing"
            } else {
                currentRGBStatus = "Waiting for typing to pause"
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func updatePressedVisualKeys(fromInputNames inputNames: Set<String>) {
        lastKeyInputAt = Date()
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
