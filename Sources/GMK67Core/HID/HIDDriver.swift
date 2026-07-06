import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

final class HIDDriver {
    private let manager: IOHIDManager

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: GMK67.vendorID,
            kIOHIDProductIDKey: GMK67.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func devices() -> [HIDDeviceInfo] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.map { device in
            HIDDeviceInfo(
                device: device,
                vendorID: intProperty(device, kIOHIDVendorIDKey),
                productID: intProperty(device, kIOHIDProductIDKey),
                usagePage: intProperty(device, kIOHIDDeviceUsagePageKey),
                usage: intProperty(device, kIOHIDDeviceUsageKey),
                primaryUsagePage: intProperty(device, kIOHIDPrimaryUsagePageKey),
                primaryUsage: intProperty(device, kIOHIDPrimaryUsageKey),
                usagePairs: usagePairsProperty(device),
                product: stringProperty(device, kIOHIDProductKey),
                manufacturer: stringProperty(device, kIOHIDManufacturerKey),
                serial: stringProperty(device, kIOHIDSerialNumberKey),
                maxFeatureReportSize: intProperty(device, kIOHIDMaxFeatureReportSizeKey),
                maxInputReportSize: intProperty(device, kIOHIDMaxInputReportSizeKey),
                maxOutputReportSize: intProperty(device, kIOHIDMaxOutputReportSizeKey)
            )
        }
        .sorted {
            if $0.isLikelyConfigurationInterface != $1.isLikelyConfigurationInterface {
                return $0.isLikelyConfigurationInterface && !$1.isLikelyConfigurationInterface
            }
            if $0.maxFeatureReportSize != $1.maxFeatureReportSize {
                return $0.maxFeatureReportSize > $1.maxFeatureReportSize
            }
            return ($0.product, $0.serial) < ($1.product, $1.serial)
        }
    }

    func configurationDevices() -> [HIDDeviceInfo] {
        devices().filter(\.isLikelyConfigurationInterface)
    }

    func firstDevice() throws -> IOHIDDevice {
        guard let info = configurationDevices().first else { throw DriverError.noDevice }
        return try open(info.device)
    }

    func device(at index: Int, configurationOnly: Bool) throws -> IOHIDDevice {
        let infos = configurationOnly ? configurationDevices() : devices()
        guard infos.indices.contains(index) else { throw DriverError.noDevice }
        return try open(infos[index].device)
    }

    private func open(_ device: IOHIDDevice) throws -> IOHIDDevice {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw DriverError.openFailed(result) }
        return device
    }

    func getFeature(reportID: Int, length: Int) throws -> [UInt8] {
        let device = try firstDevice()
        return try getFeature(device: device, reportID: reportID, length: length)
    }

    func getFeature(device: IOHIDDevice, reportID: Int, length: Int) throws -> [UInt8] {
        try getReport(device: device, type: kIOHIDReportTypeFeature, reportID: reportID, length: length)
    }

    func getInput(device: IOHIDDevice, reportID: Int, length: Int) throws -> [UInt8] {
        try getReport(device: device, type: kIOHIDReportTypeInput, reportID: reportID, length: length)
    }

    private func getReport(device: IOHIDDevice, type: IOHIDReportType, reportID: Int, length: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: length)
        var reportLength = buffer.count
        let result = IOHIDDeviceGetReport(
            device,
            type,
            CFIndex(reportID),
            &buffer,
            &reportLength
        )
        guard result == kIOReturnSuccess else { throw DriverError.getReportFailed(result) }
        return Array(buffer.prefix(reportLength))
    }

    func setFeature(reportID: Int, payload: [UInt8]) throws {
        let device = try firstDevice()
        try setFeature(device: device, reportID: reportID, payload: payload)
    }

    func setFeature(device: IOHIDDevice, reportID: Int, payload: [UInt8]) throws {
        var buffer = payload
        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(reportID),
            &buffer,
            buffer.count
        )
        guard result == kIOReturnSuccess else { throw DriverError.setReportFailed(result) }
    }

    func listenInput(device: IOHIDDevice, length: Int, seconds: Double) throws {
        try withInputListener(device: device, length: length, seconds: seconds, decoder: nil, beforeRun: nil)
    }

    func listenKeyboardInput(device: IOHIDDevice, length: Int, seconds: Double) throws {
        let usageNames = try keyboardUsageNamesByCode()
        try withInputListener(device: device, length: length, seconds: seconds, decoder: { bytes in
            decodeBootKeyboardReport(bytes, usageNames: usageNames)
        }, beforeRun: nil)
    }

    func listenAfterWrite(
        listenDevice: IOHIDDevice,
        listenLength: Int,
        seconds: Double,
        writeDevice: IOHIDDevice,
        payload: [UInt8]
    ) throws {
        try withInputListener(device: listenDevice, length: listenLength, seconds: seconds, decoder: nil) {
            try self.setFeature(device: writeDevice, reportID: 0, payload: payload)
            print("Sent feature report 0x00: \(hex(payload))")
        }
    }

    func sendFeature64(device: IOHIDDevice, bytes: [UInt8]) throws {
        guard bytes.count <= 64 else {
            throw DriverError.invalidArgument("Feature payload must be 64 bytes or fewer.")
        }
        let payload = bytes + [UInt8](repeating: 0, count: 64 - bytes.count)
        try setFeature(device: device, reportID: 0, payload: payload)
    }

    private func withInputListener(
        device: IOHIDDevice,
        length: Int,
        seconds: Double,
        decoder: (([UInt8]) -> String?)?,
        beforeRun: (() throws -> Void)?
    ) throws {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        buffer.initialize(repeating: 0, count: length)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            buffer.deinitialize(count: length)
            buffer.deallocate()
        }

        let context = InputReportContext(decoder: decoder)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            length,
            { context, result, _, reportType, reportID, report, reportLength in
                guard result == kIOReturnSuccess else {
                    print("input error: \(ioReturnName(result))")
                    return
                }
                let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                let state = context.map { Unmanaged<InputReportContext>.fromOpaque($0).takeUnretainedValue() }
                state?.count += 1
                let decoded = state?.decoder?(bytes).map { "  \($0)" } ?? ""
                print(String(
                    format: "#%03d type=%d report=0x%02X len=%3d  %@",
                    state?.count ?? 0,
                    reportType.rawValue,
                    reportID,
                    bytes.count,
                    hex(bytes)
                ) + decoded)
            },
            contextPointer
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        try beforeRun?()

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.1, false)
        }
        if context.count == 0 {
            print("No input reports observed.")
        }
    }
}

final class InputReportContext {
    var count = 0
    let decoder: (([UInt8]) -> String?)?

    init(decoder: (([UInt8]) -> String?)? = nil) {
        self.decoder = decoder
    }
}

public final class GMK67KeyInputMonitor {
    public typealias PressedKeysHandler = (Set<String>) -> Void

    private let onPressedKeysChanged: PressedKeysHandler
    private let stateLock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var context: KeyInputMonitorContext?
    private var pressedKeyCodes: [Int: String] = [:]
    private var pressedKeys: Set<String> = []
    private var isStarted = false

    public init(onPressedKeysChanged: @escaping PressedKeysHandler) {
        self.onPressedKeysChanged = onPressedKeysChanged
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isStarted else { return }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }

        let context = KeyInputMonitorContext(monitor: self)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.keyEventMask,
            callback: keyInputEventTapCallback,
            userInfo: contextPointer
        )
        guard let eventTap else {
            throw DriverError.invalidArgument("Could not start passive key monitor. Grant Input Monitoring permission to GMK67.app, then quit and reopen the app.")
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw DriverError.invalidArgument("Could not create key monitor run loop source.")
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        self.context = context
        self.isStarted = true
    }

    public func stop() {
        guard isStarted else { return }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        eventTap = nil
        runLoopSource = nil
        context = nil
        isStarted = false
        updatePressedKeys([])
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let keyName = Self.keyName(forKeyCode: keyCode) else { return }

        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            setKeyCode(keyCode, name: keyName, isPressed: true)
        case .keyUp:
            setKeyCode(keyCode, name: keyName, isPressed: false)
        case .flagsChanged:
            handleModifierFlagsChanged(keyCode: keyCode, name: keyName, flags: event.flags)
        default:
            break
        }
    }

    fileprivate func handleTapDisabledByTimeout() {
        updatePressedKeyCodes([:])
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handleModifierFlagsChanged(keyCode: Int, name: String, flags: CGEventFlags) {
        stateLock.lock()
        let wasPressed = pressedKeyCodes[keyCode] != nil
        stateLock.unlock()

        if wasPressed {
            setKeyCode(keyCode, name: name, isPressed: false)
        } else {
            setKeyCode(keyCode, name: name, isPressed: Self.modifierFlagIsSet(keyCode: keyCode, flags: flags))
        }
    }

    private func setKeyCode(_ keyCode: Int, name: String, isPressed: Bool) {
        stateLock.lock()
        var nextPressedKeyCodes = pressedKeyCodes
        if isPressed {
            nextPressedKeyCodes[keyCode] = name
        } else {
            nextPressedKeyCodes.removeValue(forKey: keyCode)
        }
        stateLock.unlock()
        updatePressedKeyCodes(nextPressedKeyCodes)
    }

    private func updatePressedKeyCodes(_ newPressedKeyCodes: [Int: String]) {
        let newPressedKeys = Set(newPressedKeyCodes.values)
        stateLock.lock()
        let didChange = newPressedKeys != pressedKeys
        pressedKeyCodes = newPressedKeyCodes
        pressedKeys = newPressedKeys
        stateLock.unlock()

        if didChange {
            onPressedKeysChanged(newPressedKeys)
        }
    }

    private func updatePressedKeys(_ newPressedKeys: Set<String>) {
        stateLock.lock()
        let didChange = newPressedKeys != pressedKeys
        pressedKeyCodes = [:]
        pressedKeys = newPressedKeys
        stateLock.unlock()

        if didChange {
            onPressedKeysChanged(newPressedKeys)
        }
    }

    private static let keyEventMask: CGEventMask = [
        CGEventType.keyDown,
        CGEventType.keyUp,
        CGEventType.flagsChanged
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    private static func modifierFlagIsSet(keyCode: Int, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 55, 54:
            return flags.contains(.maskCommand)
        case 56, 60:
            return flags.contains(.maskShift)
        case 58, 61:
            return flags.contains(.maskAlternate)
        case 59, 62:
            return flags.contains(.maskControl)
        case 57:
            return flags.contains(.maskAlphaShift)
        case 63:
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    private static func keyName(forKeyCode keyCode: Int) -> String? {
        keyNamesByVirtualKeyCode[keyCode]
    }
}

private func keyInputEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<KeyInputMonitorContext>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout:
        context.monitor?.handleTapDisabledByTimeout()
    case .keyDown, .keyUp, .flagsChanged:
        context.monitor?.handleEvent(type: type, event: event)
    default:
        break
    }

    return Unmanaged.passUnretained(event)
}

private final class KeyInputMonitorContext {
    weak var monitor: GMK67KeyInputMonitor?

    init(monitor: GMK67KeyInputMonitor) {
        self.monitor = monitor
    }
}

private let keyNamesByVirtualKeyCode: [Int: String] = [
    0: "A",
    1: "S",
    2: "D",
    3: "F",
    4: "H",
    5: "G",
    6: "Z",
    7: "X",
    8: "C",
    9: "V",
    11: "B",
    12: "Q",
    13: "W",
    14: "E",
    15: "R",
    16: "Y",
    17: "T",
    18: "1",
    19: "2",
    20: "3",
    21: "4",
    22: "6",
    23: "5",
    24: "equal",
    25: "9",
    26: "7",
    27: "-",
    28: "8",
    29: "0",
    30: "]",
    31: "O",
    32: "U",
    33: "[",
    34: "I",
    35: "P",
    36: "enter",
    37: "L",
    38: "J",
    39: "quote",
    40: "K",
    41: ";",
    42: "\\|",
    43: "comma",
    44: "slash",
    45: "N",
    46: "M",
    47: "period",
    48: "tab",
    49: "space",
    51: "backspace",
    53: "esc",
    54: "right-command",
    55: "left-command",
    56: "left-shift",
    57: "caps",
    58: "left-alt",
    59: "left-control",
    60: "right-shift",
    61: "right-alt",
    62: "right-control",
    63: "fn",
    117: "del",
    116: "pageup",
    121: "pagedown",
    123: "left",
    124: "right",
    125: "down",
    126: "up"
]


func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
    if CFGetTypeID(value) == CFNumberGetTypeID() {
        return (value as! NSNumber).intValue
    }
    return 0
}

func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return "" }
    return String(describing: value)
}

func usagePairsProperty(_ device: IOHIDDevice) -> [(page: Int, usage: Int)] {
    guard let value = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) else {
        return []
    }
    guard let pairs = value as? [[String: Any]] else { return [] }
    return pairs.compactMap { pair in
        guard
            let page = pair[kIOHIDDeviceUsagePageKey] as? NSNumber,
            let usage = pair[kIOHIDDeviceUsageKey] as? NSNumber
        else {
            return nil
        }
        return (page.intValue, usage.intValue)
    }
}
