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
