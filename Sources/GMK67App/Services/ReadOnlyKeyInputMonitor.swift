import AppKit
import Foundation

final class ReadOnlyKeyInputMonitor {
    typealias PressedKeysHandler = (Set<String>) -> Void

    private let onPressedKeysChanged: PressedKeysHandler
    private let stateLock = NSLock()
    private var localMonitor: Any?
    private var pressedKeyCodes: [UInt16: String] = [:]
    private var staleReleaseTasks: [UInt16: DispatchWorkItem] = [:]
    private var pressedKeys: Set<String> = []
    private var isStarted = false

    init(onPressedKeysChanged: @escaping PressedKeysHandler) {
        self.onPressedKeysChanged = onPressedKeysChanged
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isStarted else { return }

        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged],
            handler: { [weak self] event in
                self?.handle(event)
                return event
            }
        )

        guard let localMonitor else {
            throw ReadOnlyKeyInputMonitorError.unavailable
        }

        self.localMonitor = localMonitor
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        isStarted = false
        updatePressedKeyCodes([:])
    }

    private func handle(_ event: NSEvent) {
        let keyCode = event.keyCode

        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            guard let keyName = Self.keyName(for: event) else { return }
            setKeyCode(keyCode, name: keyName, isPressed: true)
        case .keyUp:
            setKeyCode(keyCode, name: "", isPressed: false)
        case .flagsChanged:
            if let keyName = modifierKeyNamesByVirtualKeyCode[keyCode] {
                handleModifierFlagsChanged(keyCode: keyCode, name: keyName, flags: event.modifierFlags)
            } else {
                setKeyCode(keyCode, name: "", isPressed: false)
            }
        default:
            break
        }
    }

    private func handleModifierFlagsChanged(keyCode: UInt16, name: String, flags: NSEvent.ModifierFlags) {
        stateLock.lock()
        let wasPressed = pressedKeyCodes[keyCode] != nil
        stateLock.unlock()

        if wasPressed {
            setKeyCode(keyCode, name: name, isPressed: false)
        } else {
            setKeyCode(keyCode, name: name, isPressed: Self.modifierFlagIsSet(keyCode: keyCode, flags: flags))
        }
    }

    private func setKeyCode(_ keyCode: UInt16, name: String, isPressed: Bool) {
        stateLock.lock()
        var nextPressedKeyCodes = pressedKeyCodes
        if isPressed {
            nextPressedKeyCodes[keyCode] = name
        } else {
            nextPressedKeyCodes.removeValue(forKey: keyCode)
        }
        stateLock.unlock()

        if isPressed {
            scheduleStaleRelease(for: keyCode)
        } else {
            cancelStaleRelease(for: keyCode)
        }
        updatePressedKeyCodes(nextPressedKeyCodes)
    }

    private func scheduleStaleRelease(for keyCode: UInt16) {
        cancelStaleRelease(for: keyCode)

        let task = DispatchWorkItem { [weak self] in
            self?.setKeyCode(keyCode, name: "", isPressed: false)
        }
        stateLock.lock()
        staleReleaseTasks[keyCode] = task
        stateLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: task)
    }

    private func cancelStaleRelease(for keyCode: UInt16) {
        stateLock.lock()
        let task = staleReleaseTasks.removeValue(forKey: keyCode)
        stateLock.unlock()
        task?.cancel()
    }

    private func updatePressedKeyCodes(_ newPressedKeyCodes: [UInt16: String]) {
        let newPressedKeys = Set(newPressedKeyCodes.values.filter { !$0.isEmpty })
        stateLock.lock()
        let previousPressedCodes = Set(pressedKeyCodes.keys)
        let newPressedCodes = Set(newPressedKeyCodes.keys)
        let releasedKeyCodes = previousPressedCodes.subtracting(newPressedCodes)
        let didChange = newPressedKeys != pressedKeys
        pressedKeyCodes = newPressedKeyCodes
        pressedKeys = newPressedKeys
        stateLock.unlock()

        for keyCode in releasedKeyCodes {
            cancelStaleRelease(for: keyCode)
        }

        if didChange {
            onPressedKeysChanged(newPressedKeys)
        }
    }

    private static func modifierFlagIsSet(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)
        switch keyCode {
        case 55, 54:
            return deviceIndependentFlags.contains(.command)
        case 56, 60:
            return deviceIndependentFlags.contains(.shift)
        case 58, 61:
            return deviceIndependentFlags.contains(.option)
        case 59, 62:
            return deviceIndependentFlags.contains(.control)
        case 57:
            return deviceIndependentFlags.contains(.capsLock)
        case 63:
            return deviceIndependentFlags.contains(.function)
        default:
            return false
        }
    }

    private static func keyName(for event: NSEvent) -> String? {
        if let specialKeyName = specialKeyNamesByVirtualKeyCode[event.keyCode] {
            return specialKeyName
        }

        let characters = event.charactersIgnoringModifiers ?? event.characters ?? ""
        guard let character = characters.first else { return nil }
        let value = String(character)
        switch value {
        case " ":
            return "space"
        case "\u{7F}":
            return "backspace"
        case "\u{1B}":
            return "esc"
        case "\r", "\n":
            return "enter"
        case "\t":
            return "tab"
        case "\\":
            return "\\|"
        default:
            return value.uppercased()
        }
    }
}

private enum ReadOnlyKeyInputMonitorError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        switch self {
        case .unavailable:
            return "Could not start the read-only key preview monitor."
        }
    }
}

private let specialKeyNamesByVirtualKeyCode: [UInt16: String] = [
    48: "tab",
    49: "space",
    51: "backspace",
    53: "esc",
    117: "del",
    116: "pageup",
    121: "pagedown",
    123: "left",
    124: "right",
    125: "down",
    126: "up"
]

private let modifierKeyNamesByVirtualKeyCode: [UInt16: String] = [
    54: "right-command",
    55: "left-command",
    56: "left-shift",
    57: "caps",
    58: "left-alt",
    59: "left-control",
    60: "right-shift",
    61: "right-alt",
    62: "right-control",
    63: "fn"
]
