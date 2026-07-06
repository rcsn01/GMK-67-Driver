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

    private let manager: IOHIDManager
    private let onPressedKeysChanged: PressedKeysHandler
    private let stateLock = NSLock()
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var reportBufferLength = 0
    private var context: KeyInputMonitorContext?
    private var usageNames: [UInt8: String] = [:]
    private var pressedKeys: Set<String> = []
    private var scheduledRunLoop: CFRunLoop?
    private var isStarted = false

    public init(onPressedKeysChanged: @escaping PressedKeysHandler) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.onPressedKeysChanged = onPressedKeysChanged
    }

    deinit {
        stop()
    }

    public var currentPressedKeys: Set<String> {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pressedKeys
    }

    public func start() throws {
        guard !isStarted else { return }

        usageNames = try keyboardUsageNamesByCode()
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: GMK67.vendorID,
            kIOHIDProductIDKey: GMK67.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let managerOpenResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerOpenResult == kIOReturnSuccess else {
            throw DriverError.openFailed(managerOpenResult)
        }

        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !set.isEmpty else {
            throw DriverError.noDevice
        }

        let infos = set.map { device in
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

        guard let info = Self.inputDeviceCandidate(from: infos) else {
            throw DriverError.noDevice
        }

        let openResult = IOHIDDeviceOpen(info.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw DriverError.openFailed(openResult)
        }
        guard let runLoop = CFRunLoopGetMain() else {
            IOHIDDeviceClose(info.device, IOOptionBits(kIOHIDOptionsTypeNone))
            throw DriverError.invalidArgument("Could not access the main run loop for keyboard input monitoring.")
        }

        let length = max(info.maxInputReportSize, 8)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
        buffer.initialize(repeating: 0, count: length)

        let context = KeyInputMonitorContext(monitor: self)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            info.device,
            buffer,
            length,
            { context, result, _, _, _, report, reportLength in
                guard let context else {
                    return
                }
                let state = Unmanaged<KeyInputMonitorContext>.fromOpaque(context).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
                state.monitor?.handleInputReport(result: result, bytes: bytes)
            },
            contextPointer
        )

        IOHIDDeviceScheduleWithRunLoop(info.device, runLoop, CFRunLoopMode.defaultMode.rawValue)

        self.device = info.device
        self.reportBuffer = buffer
        self.reportBufferLength = length
        self.context = context
        self.scheduledRunLoop = runLoop
        self.isStarted = true
    }

    public func stop() {
        guard isStarted else { return }

        if let device, let runLoop = scheduledRunLoop {
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        }
        if let device, let reportBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportBufferLength, nil, nil)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        if let reportBuffer {
            reportBuffer.deinitialize(count: reportBufferLength)
            reportBuffer.deallocate()
        }

        device = nil
        reportBuffer = nil
        reportBufferLength = 0
        context = nil
        scheduledRunLoop = nil
        isStarted = false
        updatePressedKeys([])
    }

    private func handleInputReport(result: IOReturn, bytes: [UInt8]) {
        guard result == kIOReturnSuccess else { return }
        guard let pressed = pressedKeyNamesFromBootKeyboardReport(bytes, usageNames: usageNames) else { return }
        updatePressedKeys(pressed)
    }

    private func updatePressedKeys(_ newPressedKeys: Set<String>) {
        stateLock.lock()
        let didChange = newPressedKeys != pressedKeys
        pressedKeys = newPressedKeys
        stateLock.unlock()

        if didChange {
            onPressedKeysChanged(newPressedKeys)
        }
    }

    private static func inputDeviceCandidate(from infos: [HIDDeviceInfo]) -> HIDDeviceInfo? {
        let sorted = infos.sorted { lhs, rhs in
            if lhs.isBootKeyboardInputInterface != rhs.isBootKeyboardInputInterface {
                return lhs.isBootKeyboardInputInterface
            }
            if lhs.isLikelyConfigurationInterface != rhs.isLikelyConfigurationInterface {
                return !lhs.isLikelyConfigurationInterface
            }
            if lhs.maxInputReportSize != rhs.maxInputReportSize {
                return lhs.maxInputReportSize < rhs.maxInputReportSize
            }
            return lhs.primaryUsage < rhs.primaryUsage
        }
        return sorted.first { $0.maxInputReportSize >= 8 }
    }
}

private final class KeyInputMonitorContext {
    weak var monitor: GMK67KeyInputMonitor?

    init(monitor: GMK67KeyInputMonitor) {
        self.monitor = monitor
    }
}

private extension HIDDeviceInfo {
    var isBootKeyboardInputInterface: Bool {
        maxInputReportSize >= 8 && (
            (primaryUsagePage == 0x0001 && primaryUsage == 0x0006) ||
            (usagePage == 0x0001 && usage == 0x0006) ||
            usagePairs.contains { $0.page == 0x0001 && $0.usage == 0x0006 }
        )
    }
}

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
