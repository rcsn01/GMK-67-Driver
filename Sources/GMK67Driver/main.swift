import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

private enum GMK67 {
    static let vendorID = 0x05AC
    static let productID = 0x024F
    static let usagePage = 0xFFFF
    static let usage = 0x0001
    static let productName = "USB DEVICE"
}

private struct KeyItem {
    let code: Int
    let name: String
    let desc: String
    let keyIndex: Int
    let lightIndex: Int
}

private struct KeymapRemap {
    let source: KeyItem
    let targetUsage: UInt8
    let modifierUsage: UInt8?
}

private struct KeymapProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let remaps: [String]
}

private struct KeymapLibraryListItem: Codable {
    let slot: String
    let name: String
    let remapCount: Int
}

private struct KeymapLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profiles: [KeymapLibraryBundleEntry]
}

private struct KeymapLibraryBundleEntry: Codable {
    let slot: String
    let profile: KeymapProfile
}

private struct RGBAssignment {
    let lightIndex: Int
    let label: String
    let color: [UInt8]
}

private struct ByteAssignment {
    let index: Int
    let label: String
    let value: UInt8
}

private struct RGBPresetDefinition: Codable {
    let name: String
    let title: String
    let description: String
    let fill: String
    let assignments: [String]
}

private struct KeymapPresetDefinition: Codable {
    let name: String
    let title: String
    let description: String
    let remaps: [String]
}

private struct LightingModePresetDefinition {
    let name: String
    let title: String
    let description: String
    let assignments: [String]
}

private struct LightingEffectDefinition {
    let name: String
    let title: String
    let value: UInt8
}

private struct CombinedProfilePresetDefinition {
    let name: String
    let title: String
    let description: String
    let rgbPreset: String
    let keymapPreset: String?
}

private struct CombinedProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let rgbFill: String?
    let rgbAssignments: [String]?
    let keymapRemaps: [String]?

    init(
        format: String,
        version: Int,
        name: String,
        rgbPreset: String,
        keymapPreset: String?,
        rgbFill: String? = nil,
        rgbAssignments: [String]? = nil,
        keymapRemaps: [String]? = nil
    ) {
        self.format = format
        self.version = version
        self.name = name
        self.rgbPreset = rgbPreset
        self.keymapPreset = keymapPreset
        self.rgbFill = rgbFill
        self.rgbAssignments = rgbAssignments
        self.keymapRemaps = keymapRemaps
    }
}

private struct MacroProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let repeatCount: Int
    let events: [MacroEvent]
}

private struct MacroEvent: Codable {
    let type: String
    let key: String?
    let usage: String?
    let text: String?
    let delayMS: Int?
}

private struct MacroLibraryListItem: Codable {
    let slot: String
    let name: String
    let repeatCount: Int
    let eventCount: Int
}

private struct MacroLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let macros: [MacroLibraryBundleEntry]
}

private struct MacroLibraryBundleEntry: Codable {
    let slot: String
    let macro: MacroProfile
}

private struct ProfileLibraryListItem: Codable {
    let slot: String
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let customRGB: Int
    let customRemaps: Int
}

private struct ProfileLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profiles: [ProfileLibraryBundleEntry]
}

private struct ProfileLibraryBundleEntry: Codable {
    let slot: String
    let profile: CombinedProfile
}

private struct AppLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profiles: [ProfileLibraryBundleEntry]
    let keymaps: [KeymapLibraryBundleEntry]
    let macros: [MacroLibraryBundleEntry]
}

private struct RGBRecordJSON: Codable {
    let chunk: Int
    let offset: Int
    let index: Int
    let key: String?
    let rgb: String
}

private struct KeymapRecordJSON: Codable {
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

private struct ByteRecordJSON: Codable {
    let offset: Int
    let key: String?
    let value: String
    let spec: String?
}

private struct RGBBackupFile {
    let url: URL
    let frameCount: Int
}

private struct HIDDeviceInfo {
    let device: IOHIDDevice
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int
    let primaryUsagePage: Int
    let primaryUsage: Int
    let usagePairs: [(page: Int, usage: Int)]
    let product: String
    let manufacturer: String
    let serial: String
    let maxFeatureReportSize: Int
    let maxInputReportSize: Int
    let maxOutputReportSize: Int

    var isLikelyConfigurationInterface: Bool {
        maxFeatureReportSize >= 64 ||
            usagePairs.contains { $0.page == GMK67.usagePage && $0.usage == GMK67.usage } ||
            (primaryUsagePage == GMK67.usagePage && primaryUsage == GMK67.usage)
    }
}

private let unsafeKeymapFlag = "--unsafe-no-backup"
private let rgbBackupPrefix = ".gmk67-rgb-backup-"
private let rgbBackupSuffix = ".hex"

private enum DriverError: Error, CustomStringConvertible {
    case noDevice
    case openFailed(IOReturn)
    case getReportFailed(IOReturn)
    case setReportFailed(IOReturn)
    case invalidHex(String)
    case invalidArgument(String)
    case layoutNotFound
    case layoutParseFailed(String)

    var description: String {
        switch self {
        case .noDevice:
            return "No GMK67 configuration HID interface found. Connect the keyboard over USB and make sure it is in wired mode."
        case .openFailed(let code):
            if code == kIOReturnNotPermitted {
                return "Could not open HID device: not permitted. On macOS, grant Input Monitoring permission to the terminal/Codex host app, then reconnect the keyboard and retry."
            }
            return "Could not open HID device: \(ioReturnName(code))"
        case .getReportFailed(let code):
            return "Report read failed: \(ioReturnName(code))"
        case .setReportFailed(let code):
            return "Feature report write failed: \(ioReturnName(code))"
        case .invalidHex(let value):
            return "Invalid hex byte string: \(value)"
        case .invalidArgument(let message):
            return message
        case .layoutNotFound:
            return "Could not find Resources/vendor/KeyboardLayout.xml"
        case .layoutParseFailed(let message):
            return "Could not parse KeyboardLayout.xml: \(message)"
        }
    }
}

private final class HIDDriver {
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

private final class InputReportContext {
    var count = 0
    let decoder: (([UInt8]) -> String?)?

    init(decoder: (([UInt8]) -> String?)? = nil) {
        self.decoder = decoder
    }
}

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
    if CFGetTypeID(value) == CFNumberGetTypeID() {
        return (value as! NSNumber).intValue
    }
    return 0
}

private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return "" }
    return String(describing: value)
}

private func usagePairsProperty(_ device: IOHIDDevice) -> [(page: Int, usage: Int)] {
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

private func loadKeyboardLayout() throws -> [KeyItem] {
    var candidates: [URL] = []

    if let resourceDirectory = ProcessInfo.processInfo.environment["GMK67_RESOURCES_DIR"], !resourceDirectory.isEmpty {
        candidates.append(
            URL(fileURLWithPath: resourceDirectory)
                .appendingPathComponent("Resources/vendor/KeyboardLayout.xml")
        )
        candidates.append(
            URL(fileURLWithPath: resourceDirectory)
                .appendingPathComponent("vendor/KeyboardLayout.xml")
        )
    }

    candidates.append(contentsOf: [
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/vendor/KeyboardLayout.xml"),
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/vendor/KeyboardLayout.xml")
    ])

    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        throw DriverError.layoutNotFound
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    let lines = text.split(whereSeparator: \.isNewline)
    var keys: [KeyItem] = []

    for line in lines where line.contains("<key ") {
        let attributes = parseAttributes(String(line))
        guard
            let codeText = attributes["code"],
            let keyIndexText = attributes["key_index"],
            let lightIndexText = attributes["light_index"],
            let code = Int(codeText.replacingOccurrences(of: "0x", with: ""), radix: 16),
            let keyIndex = Int(keyIndexText),
            let lightIndex = Int(lightIndexText)
        else {
            continue
        }

        keys.append(KeyItem(
            code: code,
            name: xmlUnescape(attributes["name"] ?? ""),
            desc: xmlUnescape(attributes["desc"] ?? ""),
            keyIndex: keyIndex,
            lightIndex: lightIndex
        ))
    }

    guard !keys.isEmpty else {
        throw DriverError.layoutParseFailed("no <key> entries found in \(url.path)")
    }
    return keys
}

private func parseAttributes(_ line: String) -> [String: String] {
    var attributes: [String: String] = [:]
    var index = line.startIndex

    while index < line.endIndex {
        while index < line.endIndex, !isAttributeStart(line[index]) {
            index = line.index(after: index)
        }
        let keyStart = index
        while index < line.endIndex, isAttributeName(line[index]) {
            index = line.index(after: index)
        }
        guard keyStart < index, index < line.endIndex, line[index] == "=" else {
            if index < line.endIndex {
                index = line.index(after: index)
            }
            continue
        }

        let key = String(line[keyStart..<index])
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == "\"" else { continue }
        index = line.index(after: index)
        let valueStart = index
        while index < line.endIndex, line[index] != "\"" {
            index = line.index(after: index)
        }
        guard index < line.endIndex else { break }
        attributes[key] = String(line[valueStart..<index])
        index = line.index(after: index)
    }
    return attributes
}

private func isAttributeStart(_ character: Character) -> Bool {
    character == "_" || character.isLetter
}

private func isAttributeName(_ character: Character) -> Bool {
    character == "_" || character.isLetter || character.isNumber
}

private func xmlUnescape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
}

private let bootModifierNames: [(mask: UInt8, name: String)] = [
    (0x01, "left-control"),
    (0x02, "left-shift"),
    (0x04, "left-alt"),
    (0x08, "left-command"),
    (0x10, "right-control"),
    (0x20, "right-shift"),
    (0x40, "right-alt"),
    (0x80, "right-command")
]

private func keyboardUsageNamesByCode() throws -> [UInt8: String] {
    var names: [UInt8: String] = [:]
    for key in try loadKeyboardLayout() where key.code >= 0 && key.code <= 0xFF {
        names[UInt8(key.code)] = key.name
    }
    for (name, usage) in hidUsageAliases where names[usage] == nil {
        names[usage] = name
    }
    for modifier in bootModifierNames.enumerated() {
        names[UInt8(0xE0 + modifier.offset)] = modifier.element.name
    }
    return names
}

private func decodeBootKeyboardReport(_ bytes: [UInt8], usageNames: [UInt8: String]) -> String? {
    guard bytes.count >= 8 else { return nil }
    let modifierByte = bytes[0]
    let modifiers = bootModifierNames.compactMap { modifierByte & $0.mask == 0 ? nil : $0.name }
    let usages = bytes[2..<min(bytes.count, 8)].filter { $0 != 0 }

    if modifiers.isEmpty && usages.isEmpty {
        return "release"
    }

    let keyNames = usages.map { usage -> String in
        usageNames[usage] ?? String(format: "0x%02X", usage)
    }

    var parts: [String] = []
    if !modifiers.isEmpty {
        parts.append("mods=\(modifiers.joined(separator: "+"))")
    }
    if !keyNames.isEmpty {
        parts.append("keys=\(keyNames.joined(separator: "+"))")
    }
    return parts.joined(separator: " ")
}

private func parseHexBytes(_ text: String) throws -> [UInt8] {
    let cleaned = text
        .replacingOccurrences(of: "0x", with: "")
        .replacingOccurrences(of: ",", with: " ")
        .replacingOccurrences(of: ":", with: " ")
        .replacingOccurrences(of: "-", with: " ")
    let chunks = cleaned.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
    if chunks.count > 1 {
        return try chunks.map { chunk in
            guard let byte = UInt8(chunk, radix: 16) else { throw DriverError.invalidHex(String(chunk)) }
            return byte
        }
    }
    guard let only = chunks.first else { return [] }
    let compact = String(only)
    guard compact.count % 2 == 0 else { throw DriverError.invalidHex(text) }
    var bytes: [UInt8] = []
    var index = compact.startIndex
    while index < compact.endIndex {
        let next = compact.index(index, offsetBy: 2)
        let part = compact[index..<next]
        guard let byte = UInt8(part, radix: 16) else { throw DriverError.invalidHex(String(part)) }
        bytes.append(byte)
        index = next
    }
    return bytes
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func printRGBRecords(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) {
    for record in rgbRecordJSON(chunks, keyByLightIndex: keyByLightIndex, recordByteLimit: recordByteLimit) {
        let label = record.key.map { " key=\($0)" } ?? ""
        let rgbBytes = try? parseHexBytes(record.rgb)
        if let rgbBytes, rgbBytes.count == 3 {
            print(String(
                format: "  chunk=%02d offset=%02d index=0x%02X%@ rgb=%02X %02X %02X",
                record.chunk,
                record.offset,
                record.index,
                label,
                rgbBytes[0],
                rgbBytes[1],
                rgbBytes[2]
            ))
        }
    }
}

private func rgbRecordJSON(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) -> [RGBRecordJSON] {
    var records: [RGBRecordJSON] = []
    for (chunkIndex, bytes) in chunks.enumerated() {
        var offset = 0
        while offset + 3 < bytes.count {
            let tableOffset = chunkIndex * 64 + offset
            if let recordByteLimit, tableOffset + 3 >= recordByteLimit {
                break
            }
            let record = Array(bytes[offset..<(offset + 4)])
            let index = record[0]
            let red = record[1]
            let green = record[2]
            let blue = record[3]
            if red != 0 || green != 0 || blue != 0 {
                let key = keyByLightIndex[Int(index)]
                records.append(RGBRecordJSON(
                    chunk: chunkIndex,
                    offset: offset,
                    index: Int(index),
                    key: key?.name,
                    rgb: String(format: "%02X%02X%02X", red, green, blue)
                ))
            }
            offset += 4
        }
    }
    return records
}

private func printRGBRecordsJSON(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(rgbRecordJSON(chunks, keyByLightIndex: keyByLightIndex, recordByteLimit: recordByteLimit))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

private func printByteTableRecords(_ chunks: [[UInt8]], byteLimit: Int, keyByLightIndex: [Int: KeyItem] = [:]) {
    let table = Array(chunks.joined())
    let limit = min(byteLimit, table.count)
    for offset in 0..<limit {
        let value = table[offset]
        if value != 0 {
            let key = keyByLightIndex[offset]
            let label = key.map { " key=\($0.name)" } ?? ""
            print(String(format: "  offset=0x%03X%@ value=0x%02X", offset, label, value))
        }
    }
}

private func parseableSpecTarget(for key: KeyItem?, offset: Int, duplicateKeyTokens: Set<String>) -> String {
    guard let key else {
        return String(format: "0x%02X", offset)
    }
    let token = keyLookupToken(key.name)
    guard !duplicateKeyTokens.contains(token) else {
        return String(format: "0x%02X", offset)
    }
    if let alias = parseableSpecTargetAliases[key.name] {
        return alias
    }
    guard key.name.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
        return String(format: "0x%02X", offset)
    }
    return key.name
}

private func duplicateKeyNameTokens(_ keys: [KeyItem]) -> Set<String> {
    var counts: [String: Int] = [:]
    for key in keys {
        counts[keyLookupToken(key.name), default: 0] += 1
    }
    return Set(counts.filter { !$0.key.isEmpty && $0.value > 1 }.map(\.key))
}

private func byteRecordJSON(_ chunks: [[UInt8]], byteLimit: Int, keyByLightIndex: [Int: KeyItem] = [:]) -> [ByteRecordJSON] {
    let table = Array(chunks.joined())
    let limit = min(byteLimit, table.count)
    var records: [ByteRecordJSON] = []
    let duplicateTokens = duplicateKeyNameTokens(Array(keyByLightIndex.values))
    for offset in 0..<limit {
        let value = table[offset]
        guard value != 0 else { continue }
        let key = keyByLightIndex[offset]
        let target = parseableSpecTarget(for: key, offset: offset, duplicateKeyTokens: duplicateTokens)
        let valueHex = String(format: "%02X", value)
        records.append(ByteRecordJSON(
            offset: offset,
            key: key?.name,
            value: valueHex,
            spec: "\(target)=\(valueHex)"
        ))
    }
    return records
}

private func printByteRecordsJSON(_ chunks: [[UInt8]], byteLimit: Int, keyByLightIndex: [Int: KeyItem] = [:]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(byteRecordJSON(chunks, byteLimit: byteLimit, keyByLightIndex: keyByLightIndex))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

private func rgbFramesToRecords(_ frames: [[UInt8]]) -> [Int: (red: UInt8, green: UInt8, blue: UInt8)] {
    var records: [Int: (red: UInt8, green: UInt8, blue: UInt8)] = [:]
    for bytes in frames {
        var offset = 0
        while offset + 3 < bytes.count {
            records[Int(bytes[offset])] = (bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
            offset += 4
        }
    }
    return records
}

private func setRGBRecord(frames: inout [[UInt8]], lightIndex: Int, color: [UInt8]) throws {
    guard color.count == 3 else {
        throw DriverError.invalidArgument("RGB color must contain exactly three bytes.")
    }
    let frameIndex = lightIndex / 16
    let recordOffset = (lightIndex % 16) * 4
    guard frames.indices.contains(frameIndex), recordOffset + 3 < frames[frameIndex].count else {
        throw DriverError.invalidArgument("Light index 0x\(String(format: "%02X", lightIndex)) is outside the RGB table.")
    }
    frames[frameIndex][recordOffset] = UInt8(lightIndex)
    frames[frameIndex][recordOffset + 1] = color[0]
    frames[frameIndex][recordOffset + 2] = color[1]
    frames[frameIndex][recordOffset + 3] = color[2]
}

private func readRGBFrames(driver: HIDDriver, writeDevice: IOHIDDevice, readDevice: IOHIDDevice, chunks: Int = 9) throws -> [[UInt8]] {
    var readRequest = [UInt8](repeating: 0, count: 64)
    readRequest[0] = 0x04
    readRequest[1] = 0xF5
    readRequest[8] = UInt8(chunks)
    try driver.setFeature(device: writeDevice, reportID: 0, payload: readRequest)

    var frames: [[UInt8]] = []
    for _ in 0..<chunks {
        usleep(50_000)
        frames.append(try driver.getInput(device: readDevice, reportID: 0, length: 64))
    }
    return frames
}

private func writeRGBFrames(driver: HIDDriver, writeDevice: IOHIDDevice, frames: [[UInt8]]) throws {
    guard frames.count >= 8, frames.prefix(8).allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("RGB restore requires at least eight 64-byte frames.")
    }
    try driver.sendFeature64(device: writeDevice, bytes: [0x04, 0x20, 0, 0, 0, 0, 0, 0, 0x08])
    usleep(30_000)
    for frame in frames.prefix(8) {
        try driver.setFeature(device: writeDevice, reportID: 0, payload: frame)
        usleep(30_000)
    }
    try driver.sendFeature64(device: writeDevice, bytes: [0x04, 0x02])
}

private func writeRGBFramesFile(_ frames: [[UInt8]], path: String) throws {
    let text = frames.map(hex).joined(separator: "\n") + "\n"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

private func backupRGBFrames(_ frames: [[UInt8]]) throws -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let basePath = "\(rgbBackupPrefix)\(formatter.string(from: Date()))"
    var path = "\(basePath)\(rgbBackupSuffix)"
    var suffix = 1
    while FileManager.default.fileExists(atPath: path) {
        path = "\(basePath)-\(suffix)\(rgbBackupSuffix)"
        suffix += 1
    }
    try writeRGBFramesFile(frames, path: path)
    return path
}

private func readRGBFramesFile(_ path: String) throws -> [[UInt8]] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let frames = try text
        .split(whereSeparator: \.isNewline)
        .map { try parseHexBytes(String($0)) }
    guard (frames.count == 8 || frames.count == 9), frames.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("RGB table file must contain 8 or 9 lines of 64 hex bytes.")
    }
    return frames
}

private func rgbBackupFiles(directoryPath: String = ".") -> [RGBBackupFile] {
    let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsSubdirectoryDescendants]
    ) else {
        return []
    }

    return urls.compactMap { url -> RGBBackupFile? in
        let name = url.lastPathComponent
        guard name.hasPrefix(rgbBackupPrefix), name.hasSuffix(rgbBackupSuffix) else {
            return nil
        }
        guard let frames = try? readRGBFramesFile(url.path) else {
            return nil
        }
        return RGBBackupFile(url: url, frameCount: frames.count)
    }
    .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
}

private func latestRGBBackup(directoryPath: String = ".") throws -> RGBBackupFile {
    guard let latest = rgbBackupFiles(directoryPath: directoryPath).first else {
        throw DriverError.invalidArgument("No valid RGB backup files found in \(directoryPath).")
    }
    return latest
}

private let keyNameAliases: [String: String] = [
    "escape": "esc",
    "delete": "del",
    "equal": "=",
    "equals": "=",
    "minus": "-",
    "dash": "-",
    "leftbracket": "[",
    "rightbracket": "]",
    "lbracket": "[",
    "rbracket": "]",
    "semicolon": ";",
    "quote": "'\"",
    "apostrophe": "'\"",
    "backslash": "\\|",
    "pipe": "\\|",
    "comma": "<",
    "period": ">",
    "dot": ">",
    "slash": "?",
    "pgup": "page up",
    "pageup": "page up",
    "pgdn": "page down",
    "pagedown": "page down",
    "return": "enter",
    "cmd": "win",
    "command": "win",
    "option": "alt",
    "ctrl": "control"
]

private let parseableSpecTargetAliases: [String: String] = [
    "=": "equal",
    "[": "lbracket",
    "]": "rbracket",
    ";": "semicolon",
    "'\"": "quote",
    "\\|": "backslash",
    "<": "comma",
    ">": "period",
    "?": "slash",
    "page up": "pageup",
    "page down": "pagedown",
    "←": "left",
    "↓": "down",
    "↑": "up",
    "→": "right"
]

private let hidUsageAliases: [String: UInt8] = [
    "esc": 0x29,
    "escape": 0x29,
    "backspace": 0x2A,
    "tab": 0x2B,
    "enter": 0x28,
    "return": 0x28,
    "space": 0x2C,
    "delete": 0x4C,
    "del": 0x4C,
    "insert": 0x49,
    "ins": 0x49,
    "home": 0x4A,
    "end": 0x4D,
    "pageup": 0x4B,
    "pgup": 0x4B,
    "pagedown": 0x4E,
    "pgdn": 0x4E,
    "arrowright": 0x4F,
    "right": 0x4F,
    "arrowleft": 0x50,
    "left": 0x50,
    "arrowdown": 0x51,
    "down": 0x51,
    "arrowup": 0x52,
    "up": 0x52,
    "f1": 0x3A,
    "f2": 0x3B,
    "f3": 0x3C,
    "f4": 0x3D,
    "f5": 0x3E,
    "f6": 0x3F,
    "f7": 0x40,
    "f8": 0x41,
    "f9": 0x42,
    "f10": 0x43,
    "f11": 0x44,
    "f12": 0x45
]

private let preferredHIDUsageNames: [UInt8: String] = [
    0x28: "enter",
    0x29: "esc",
    0x2A: "backspace",
    0x2B: "tab",
    0x2C: "space",
    0x3A: "f1",
    0x3B: "f2",
    0x3C: "f3",
    0x3D: "f4",
    0x3E: "f5",
    0x3F: "f6",
    0x40: "f7",
    0x41: "f8",
    0x42: "f9",
    0x43: "f10",
    0x44: "f11",
    0x45: "f12",
    0x49: "insert",
    0x4A: "home",
    0x4B: "pageup",
    0x4C: "del",
    0x4D: "end",
    0x4E: "pagedown",
    0x4F: "right",
    0x50: "left",
    0x51: "down",
    0x52: "up"
]

private let modifierNameByEncodedUsage: [UInt8: String] = [
    0x01: "control",
    0x02: "shift",
    0x04: "alt",
    0x08: "win",
    0x10: "control",
    0x20: "shift",
    0x40: "alt",
    0x80: "win"
]

private let modifierUsageByEncodedUsage: [UInt8: UInt8] = [
    0x01: 0xE0,
    0x02: 0xE1,
    0x04: 0xE2,
    0x08: 0xE3,
    0x10: 0xE4,
    0x20: 0xE5,
    0x40: 0xE6,
    0x80: 0xE7
]

private let rgbPresetDefinitions: [RGBPresetDefinition] = [
    RGBPresetDefinition(name: "off", title: "Off", description: "Turn all mapped physical key LEDs off.", fill: "000000", assignments: []),
    RGBPresetDefinition(name: "white", title: "White", description: "Set all mapped physical keys to white.", fill: "FFFFFF", assignments: []),
    RGBPresetDefinition(name: "red", title: "Red", description: "Set all mapped physical keys to red.", fill: "FF0000", assignments: []),
    RGBPresetDefinition(name: "blue", title: "Blue", description: "Set all mapped physical keys to blue.", fill: "0000FF", assignments: []),
    RGBPresetDefinition(name: "wasd", title: "WASD", description: "Highlight WASD and arrow keys for games.", fill: "101018", assignments: [
        "W=FF3B30", "A=FFCC00", "S=34C759", "D=00C7BE",
        "up=5E5CE6", "left=FFCC00", "down=34C759", "right=00C7BE",
        "shift=FF2D55", "space=FFFFFF"
    ]),
    RGBPresetDefinition(name: "arrows", title: "Arrows", description: "Dim board with bright navigation keys.", fill: "05070A", assignments: [
        "up=FFFFFF", "left=FFCC00", "down=34C759", "right=00C7BE",
        "page up=AF52DE", "page down=5E5CE6", "del=FF3B30"
    ]),
    RGBPresetDefinition(name: "coding", title: "Coding", description: "Quiet base with syntax-colored punctuation and modifiers.", fill: "151515", assignments: [
        "esc=FF453A", "tab=64D2FF", "Caps=BF5AF2", "enter=30D158",
        "[=FFD60A", "]=FFD60A", ";=FF9F0A", "\\|=FFD60A",
        "control=64D2FF", "alt=64D2FF", "space=FFFFFF"
    ]),
    RGBPresetDefinition(name: "rainbow", title: "Rainbow Rows", description: "Simple row-based rainbow layout.", fill: "000000", assignments: [
        "esc=FF3B30", "1=FF3B30", "2=FF453A", "3=FF9F0A", "4=FFCC00", "5=FFD60A", "6=34C759", "7=30D158", "8=00C7BE", "9=64D2FF", "0=0A84FF", "-=5E5CE6", "equal=BF5AF2", "backspace=FF2D55",
        "tab=FF9F0A", "Q=FFCC00", "W=FFD60A", "E=34C759", "R=30D158", "T=00C7BE", "Y=64D2FF", "U=0A84FF", "I=5E5CE6", "O=BF5AF2", "P=FF2D55",
        "Caps=34C759", "A=30D158", "S=00C7BE", "D=64D2FF", "F=0A84FF", "G=5E5CE6", "H=BF5AF2", "J=FF2D55", "K=FF3B30", "L=FF9F0A", "enter=FFD60A",
        "shift=5E5CE6", "Z=BF5AF2", "X=FF2D55", "C=FF3B30", "V=FF9F0A", "B=FFCC00", "N=FFD60A", "M=34C759", "up=64D2FF",
        "control=0A84FF", "win=5E5CE6", "alt=BF5AF2", "space=FFFFFF", "fn=5E5CE6", "left=FFCC00", "down=34C759", "right=00C7BE"
    ]),
    RGBPresetDefinition(name: "ocean", title: "Ocean", description: "Blue and cyan board preset.", fill: "001E3C", assignments: [
        "W=00C7BE", "A=64D2FF", "S=0A84FF", "D=5E5CE6",
        "space=64D2FF", "enter=00C7BE", "esc=0A84FF"
    ]),
    RGBPresetDefinition(name: "sunset", title: "Sunset", description: "Warm orange, red, and purple board preset.", fill: "2B1028", assignments: [
        "esc=FF453A", "1=FF3B30", "2=FF453A", "3=FF9F0A", "4=FFCC00",
        "W=FF9F0A", "A=FFCC00", "S=FF453A", "D=BF5AF2",
        "space=FFCC00", "enter=FF9F0A"
    ])
]

private let keymapPresetDefinitions: [KeymapPresetDefinition] = [
    KeymapPresetDefinition(name: "caps-esc", title: "Caps to Esc", description: "Map Caps Lock to Escape.", remaps: ["Caps=esc"]),
    KeymapPresetDefinition(name: "wasd-arrows", title: "WASD Arrows", description: "Map WASD to arrow keys.", remaps: ["W=up", "A=left", "S=down", "D=right"]),
    KeymapPresetDefinition(name: "vim-arrows", title: "Vim Arrows", description: "Map HJKL to left/down/up/right.", remaps: ["H=left", "J=down", "K=up", "L=right"]),
    KeymapPresetDefinition(name: "gaming-layer", title: "Gaming Layer", description: "Caps to Esc and WASD to arrows.", remaps: ["Caps=esc", "W=up", "A=left", "S=down", "D=right"]),
    KeymapPresetDefinition(name: "editing-shortcuts", title: "Editing Shortcuts", description: "Map navigation cluster keys to copy, paste, undo, and redo.", remaps: ["page up=C:control", "page down=V:control", "del=Z:control", "backspace=Y:control"]),
    KeymapPresetDefinition(name: "function-row", title: "Function Row", description: "Map number keys 1-0, minus, and equals to F1-F12.", remaps: ["1=f1", "2=f2", "3=f3", "4=f4", "5=f5", "6=f6", "7=f7", "8=f8", "9=f9", "0=f10", "-=f11", "equal=f12"]),
    KeymapPresetDefinition(name: "navigation-cluster", title: "Navigation Cluster", description: "Map bracket and punctuation keys to home/end/page navigation.", remaps: ["[=home", "]=end", ";=pageup", "'\"=pagedown"])
]

private let lightingModePresetDefinitions: [LightingModePresetDefinition] = [
    LightingModePresetDefinition(name: "empty", title: "Empty", description: "Zeroed selector-03 lighting-mode table.", assignments: []),
    LightingModePresetDefinition(name: "wasd-steps", title: "WASD Steps", description: "Assign small mode bytes to WASD and arrows for controlled physical testing.", assignments: [
        "W=01", "A=02", "S=03", "D=04",
        "up=01", "left=02", "down=03", "right=04"
    ]),
    LightingModePresetDefinition(name: "nav-steps", title: "Navigation Steps", description: "Assign stepped mode bytes to navigation and editing keys.", assignments: [
        "home=01", "end=02", "pageup=03", "pagedown=04", "del=05", "backspace=06"
    ]),
    LightingModePresetDefinition(name: "row-steps", title: "Row Steps", description: "Assign repeated low mode bytes across the main alphanumeric rows.", assignments: [
        "Q=01", "W=02", "E=03", "R=04", "T=05", "Y=06", "U=07", "I=08", "O=09", "P=0A",
        "A=01", "S=02", "D=03", "F=04", "G=05", "H=06", "J=07", "K=08", "L=09",
        "Z=01", "X=02", "C=03", "V=04", "B=05", "N=06", "M=07"
    ])
]

private let lightingEffectDefinitions: [LightingEffectDefinition] = [
    LightingEffectDefinition(name: "static", title: "Static", value: 0x00),
    LightingEffectDefinition(name: "single-on", title: "SingleOn", value: 0x01),
    LightingEffectDefinition(name: "single-off", title: "SingleOff", value: 0x02),
    LightingEffectDefinition(name: "glittering", title: "Glittering", value: 0x03),
    LightingEffectDefinition(name: "falling", title: "Falling", value: 0x04),
    LightingEffectDefinition(name: "colourful", title: "Colourful", value: 0x05),
    LightingEffectDefinition(name: "breath", title: "Breath", value: 0x06),
    LightingEffectDefinition(name: "spectrum", title: "Spectrum", value: 0x07),
    LightingEffectDefinition(name: "outward", title: "Outward", value: 0x08),
    LightingEffectDefinition(name: "scrolling", title: "Scrolling", value: 0x09),
    LightingEffectDefinition(name: "rolling", title: "Rolling", value: 0x0A),
    LightingEffectDefinition(name: "rotating", title: "Rotating", value: 0x0B),
    LightingEffectDefinition(name: "explode", title: "Explode", value: 0x0C),
    LightingEffectDefinition(name: "launch", title: "Launch", value: 0x0D),
    LightingEffectDefinition(name: "ripples", title: "Ripples", value: 0x0E),
    LightingEffectDefinition(name: "flowing", title: "Flowing", value: 0x0F),
    LightingEffectDefinition(name: "pulsating", title: "Pulsating", value: 0x10),
    LightingEffectDefinition(name: "tilt", title: "Tilt", value: 0x11),
    LightingEffectDefinition(name: "shuttle", title: "Shuttle", value: 0x12),
    LightingEffectDefinition(name: "led-off", title: "LED Off", value: 0x13),
    LightingEffectDefinition(name: "inwards", title: "Inwards", value: 0x14),
    LightingEffectDefinition(name: "floweriness", title: "Floweriness", value: 0x15)
]

private let combinedProfilePresetDefinitions: [CombinedProfilePresetDefinition] = [
    CombinedProfilePresetDefinition(name: "gaming", title: "Gaming", description: "WASD lighting with Caps as Esc and WASD remapped to arrows.", rgbPreset: "wasd", keymapPreset: "gaming-layer"),
    CombinedProfilePresetDefinition(name: "navigation", title: "Navigation", description: "Dim board with navigation lighting and HJKL arrow remaps.", rgbPreset: "arrows", keymapPreset: "vim-arrows"),
    CombinedProfilePresetDefinition(name: "coding", title: "Coding", description: "Coding lighting with Caps mapped to Esc.", rgbPreset: "coding", keymapPreset: "caps-esc"),
    CombinedProfilePresetDefinition(name: "editing", title: "Editing", description: "Coding lighting with copy, paste, undo, and redo remaps.", rgbPreset: "coding", keymapPreset: "editing-shortcuts"),
    CombinedProfilePresetDefinition(name: "ocean-rgb", title: "Ocean RGB", description: "Ocean lighting without key remaps.", rgbPreset: "ocean", keymapPreset: nil),
    CombinedProfilePresetDefinition(name: "lights-off", title: "Lights Off", description: "Turn mapped LEDs off without changing keymaps.", rgbPreset: "off", keymapPreset: nil)
]

private func keyLookupToken(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
}

private func keyByName(_ name: String) -> KeyItem? {
    guard let keys = try? loadKeyboardLayout() else { return nil }
    let normalized = name.lowercased()
    if let key = keys.first(where: { $0.name.lowercased() == normalized || $0.desc.lowercased() == normalized }) {
        return key
    }

    let lookupToken = keyLookupToken(name)
    guard let alias = keyNameAliases[lookupToken] else {
        guard let usage = hidUsageAliases[lookupToken] else { return nil }
        return keys.first { $0.code == Int(usage) }
    }
    let normalizedAlias = alias.lowercased()
    return keys.first {
        $0.name.lowercased() == normalizedAlias || $0.desc.lowercased() == normalizedAlias
    }
}

private func keyByArgument(_ argument: String) throws -> KeyItem {
    if let key = keyByName(argument) {
        return key
    }

    let normalized = argument.lowercased().replacingOccurrences(of: "0x", with: "")
    let radix = argument.lowercased().hasPrefix("0x") ? 16 : 10
    if let code = Int(normalized, radix: radix),
       let key = (try? loadKeyboardLayout())?.first(where: { $0.code == code || $0.keyIndex == code }) {
        return key
    }

    throw DriverError.invalidArgument("Unknown key: \(argument)")
}

private func lightTargetByArgument(_ argument: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> (lightIndex: Int, label: String) {
    let normalized = argument.lowercased().replacingOccurrences(of: "0x", with: "")
    if argument.lowercased().hasPrefix("0x"), let parsed = Int(normalized, radix: 16) {
        guard parsed >= 0, parsed <= 0x8F else {
            throw DriverError.invalidArgument("Light index must be between 0x00 and 0x8F.")
        }
        return (parsed, keyMap[parsed]?.name ?? "light 0x\(String(format: "%02X", parsed))")
    }

    if let parsed = Int(argument), parsed >= 0, parsed <= 0x8F, keyMap[parsed] != nil {
        return (parsed, keyMap[parsed]?.name ?? "light \(parsed)")
    }

    if let key = keyByName(argument) {
        return (key.lightIndex, key.name)
    }

    throw DriverError.invalidArgument("Unknown key or light index: \(argument)")
}

private func parseRGBAssignmentSpec(_ spec: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> RGBAssignment {
    let assignment = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard assignment.count == 2, !assignment[0].isEmpty, !assignment[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid RGB spec '\(spec)'. Use key=rrggbb, for example W=FF0000.")
    }
    let color = try parseHexBytes(String(assignment[1]))
    guard color.count == 3 else {
        throw DriverError.invalidArgument("RGB color must be exactly three bytes in '\(spec)'.")
    }
    let target = try lightTargetByArgument(String(assignment[0]), keyMap: keyMap)
    return RGBAssignment(lightIndex: target.lightIndex, label: target.label, color: color)
}

private func parseRGBAssignmentSpecs(_ specs: [String], keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> [RGBAssignment] {
    guard !specs.isEmpty else {
        throw DriverError.invalidArgument("At least one RGB assignment is required.")
    }
    let assignments = try specs.map { try parseRGBAssignmentSpec($0, keyMap: keyMap) }
    var seenLightIndices = Set<Int>()
    for assignment in assignments {
        guard seenLightIndices.insert(assignment.lightIndex).inserted else {
            throw DriverError.invalidArgument("Duplicate RGB target in assignment list: \(assignment.label)")
        }
    }
    return assignments
}

private func rgbPreset(named name: String) throws -> RGBPresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = rgbPresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown RGB preset '\(name)'. Run rgb-preset-list to see available presets.")
    }
    return preset
}

private func keymapPreset(named name: String) throws -> KeymapPresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = keymapPresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown keymap preset '\(name)'. Run keymap-preset-list to see available presets.")
    }
    return preset
}

private func lightingModePreset(named name: String) throws -> LightingModePresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = lightingModePresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown lighting-mode preset '\(name)'. Run lighting-mode-preset-list to see available presets.")
    }
    return preset
}

private func lightingEffect(named name: String) throws -> LightingEffectDefinition {
    let token = keyLookupToken(name)
    guard let effect = lightingEffectDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown lighting effect '\(name)'. Run lighting-effect-list to see available effects.")
    }
    return effect
}

private func combinedProfilePreset(named name: String) throws -> CombinedProfilePresetDefinition {
    let token = keyLookupToken(name)
    guard let preset = combinedProfilePresetDefinitions.first(where: { keyLookupToken($0.name) == token || keyLookupToken($0.title) == token }) else {
        throw DriverError.invalidArgument("Unknown profile preset '\(name)'. Run profile-preset-list to see available presets.")
    }
    return preset
}

private func makeCombinedProfile(from preset: CombinedProfilePresetDefinition) throws -> CombinedProfile {
    let profile = CombinedProfile(
        format: "gmk67-profile",
        version: 1,
        name: preset.title,
        rgbPreset: preset.rgbPreset,
        keymapPreset: preset.keymapPreset
    )
    try validateCombinedProfile(profile)
    return profile
}

private func makeEditableCombinedProfile(from preset: CombinedProfilePresetDefinition) throws -> CombinedProfile {
    let rgb = try rgbPreset(named: preset.rgbPreset)
    let keymapRemaps = try preset.keymapPreset.map { try keymapPreset(named: $0).remaps }
    let profile = CombinedProfile(
        format: "gmk67-profile",
        version: 1,
        name: preset.title,
        rgbPreset: preset.rgbPreset,
        keymapPreset: nil,
        rgbFill: rgb.fill,
        rgbAssignments: rgb.assignments.isEmpty ? nil : rgb.assignments,
        keymapRemaps: (keymapRemaps ?? []).isEmpty ? nil : keymapRemaps
    )
    try validateCombinedProfile(profile)
    return profile
}

private func rgbPresetFrames(_ preset: RGBPresetDefinition) throws -> [[UInt8]] {
    let fillColor = try parseHexBytes(preset.fill)
    guard fillColor.count == 3 else {
        throw DriverError.invalidArgument("Preset \(preset.name) has an invalid fill color.")
    }
    let keyMap = keyMapByLightIndex()
    var frames = sampleRGBFrames()
    try applyRGBFill(fillColor, to: &frames, keyMap: physicalKeysByLightIndex())
    if !preset.assignments.isEmpty {
        let assignments = try parseRGBAssignmentSpecs(preset.assignments, keyMap: keyMap)
        try applyRGBAssignments(assignments, to: &frames)
    }
    return frames
}

private func keymapPresetRemaps(_ preset: KeymapPresetDefinition) throws -> [KeymapRemap] {
    try parseKeymapRemapSpecs(preset.remaps)
}

private func lightingModePresetAssignments(_ preset: LightingModePresetDefinition) throws -> [ByteAssignment] {
    guard !preset.assignments.isEmpty else { return [] }
    return try parseByteAssignmentSpecs(preset.assignments)
}

private func lightingEffectAssignments(_ effect: LightingEffectDefinition) -> [ByteAssignment] {
    physicalKeysByLightIndex()
        .sorted { $0.key < $1.key }
        .map { lightIndex, key in
            ByteAssignment(index: lightIndex, label: key.name, value: effect.value)
        }
}

private func printRGBPresetList() {
    print("RGB presets:")
    for preset in rgbPresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
    }
}

private func printRGBPreset(_ preset: RGBPresetDefinition) {
    print("\(preset.name) - \(preset.title)")
    print("  \(preset.description)")
    print("  fill=\(preset.fill)")
    if !preset.assignments.isEmpty {
        print("  assignments: \(preset.assignments.joined(separator: " "))")
    }
}

private func printRGBPresetJSON(_ preset: RGBPresetDefinition) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(preset)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

private func printKeymapPresetList() {
    print("Keymap presets:")
    for preset in keymapPresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
        print("    \(preset.remaps.joined(separator: " "))")
    }
}

private func printKeymapPreset(_ preset: KeymapPresetDefinition) {
    print("\(preset.name) - \(preset.title)")
    print("  \(preset.description)")
    if !preset.remaps.isEmpty {
        print("  remaps: \(preset.remaps.joined(separator: " "))")
    }
}

private func printKeymapPresetJSON(_ preset: KeymapPresetDefinition) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(preset)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

private func printLightingModePresetList() {
    print("Lighting-mode presets:")
    for preset in lightingModePresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
        if !preset.assignments.isEmpty {
            print("    \(preset.assignments.joined(separator: " "))")
        }
    }
}

private func printLightingEffectList() {
    print("Candidate lighting effects from the Windows UI:")
    for effect in lightingEffectDefinitions {
        print(String(format: "  %@ - %@: selector-03 value 0x%02X", effect.name, effect.title, effect.value))
    }
    print("These are mapped into the modeled 04 23 selector-03 table for controlled testing; live apply remains guarded.")
}

private func printCombinedProfilePresetList() {
    print("Profile presets:")
    for preset in combinedProfilePresetDefinitions {
        print("  \(preset.name) - \(preset.title): \(preset.description)")
        print("    rgb=\(preset.rgbPreset) keymap=\(preset.keymapPreset ?? "-")")
    }
}

private func writeCombinedProfile(_ profile: CombinedProfile, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func readCombinedProfile(_ path: String) throws -> CombinedProfile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let profile = try JSONDecoder().decode(CombinedProfile.self, from: data)
    try validateCombinedProfile(profile)
    return profile
}

private func validateCombinedProfile(_ profile: CombinedProfile) throws {
    guard profile.format == "gmk67-profile", profile.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 profile format/version.")
    }
    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DriverError.invalidArgument("Profile name must not be empty.")
    }
    _ = try rgbPreset(named: profile.rgbPreset)
    if let keymapPresetName = profile.keymapPreset, !keymapPresetName.isEmpty {
        _ = try keymapPreset(named: keymapPresetName)
    }
    if let rgbFill = profile.rgbFill {
        let fill = try parseHexBytes(rgbFill)
        guard fill.count == 3 else {
            throw DriverError.invalidArgument("Profile rgbFill must be exactly three bytes.")
        }
    }
    if let rgbAssignments = profile.rgbAssignments, !rgbAssignments.isEmpty {
        _ = try parseRGBAssignmentSpecs(rgbAssignments)
    }
    _ = try combinedProfileKeymapRemaps(profile)
}

private func printCombinedProfile(_ profile: CombinedProfile) {
    print("Profile: \(profile.name)")
    print("  RGB preset: \(profile.rgbPreset)")
    print("  Keymap preset: \(profile.keymapPreset ?? "-")")
    if let rgbFill = profile.rgbFill {
        print("  RGB fill: \(rgbFill)")
    }
    if let rgbAssignments = profile.rgbAssignments, !rgbAssignments.isEmpty {
        print("  RGB assignments: \(rgbAssignments.joined(separator: " "))")
    }
    if let keymapRemaps = profile.keymapRemaps, !keymapRemaps.isEmpty {
        print("  Keymap remaps: \(keymapRemaps.joined(separator: " "))")
    }
}

private func combinedProfileRGBFrames(_ profile: CombinedProfile) throws -> [[UInt8]] {
    var frames: [[UInt8]]
    if let rgbFill = profile.rgbFill {
        let fillColor = try parseHexBytes(rgbFill)
        frames = sampleRGBFrames()
        try applyRGBFill(fillColor, to: &frames, keyMap: physicalKeysByLightIndex())
    } else {
        frames = try rgbPresetFrames(try rgbPreset(named: profile.rgbPreset))
    }

    if let rgbAssignments = profile.rgbAssignments, !rgbAssignments.isEmpty {
        let assignments = try parseRGBAssignmentSpecs(rgbAssignments)
        try applyRGBAssignments(assignments, to: &frames)
    }
    return frames
}

private func combinedProfileKeymapRemaps(_ profile: CombinedProfile) throws -> [KeymapRemap] {
    var specs: [String] = []
    if let keymapPresetName = profile.keymapPreset, !keymapPresetName.isEmpty {
        specs += try keymapPreset(named: keymapPresetName).remaps
    }
    if let keymapRemaps = profile.keymapRemaps {
        specs += keymapRemaps
    }
    guard !specs.isEmpty else { return [] }
    let remaps = try parseKeymapRemapSpecs(specs)
    _ = try keymapRemapTable(remaps)
    return remaps
}

private func combinedProfileHasKeymap(_ profile: CombinedProfile) -> Bool {
    if let keymapPreset = profile.keymapPreset, !keymapPreset.isEmpty {
        return true
    }
    return !(profile.keymapRemaps ?? []).isEmpty
}

private func parseProfileCreateOptions(_ args: [String]) throws -> (path: String, profile: CombinedProfile) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("profile-create requires a path.")
    }
    var name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var rgbPresetName = "wasd"
    var keymapPresetName: String?
    var rgbFill: String?
    var rgbAssignments: [String] = []
    var keymapRemaps: [String] = []

    for argument in args.dropFirst() {
        if argument.hasPrefix("--name=") {
            name = String(argument.dropFirst("--name=".count))
        } else if argument.hasPrefix("--rgb=") {
            rgbPresetName = String(argument.dropFirst("--rgb=".count))
        } else if argument.hasPrefix("--keymap=") {
            let value = String(argument.dropFirst("--keymap=".count))
            keymapPresetName = value.isEmpty || value == "-" || value.lowercased() == "none" ? nil : value
        } else if argument.hasPrefix("--rgb-fill=") {
            rgbFill = String(argument.dropFirst("--rgb-fill=".count))
        } else if argument.hasPrefix("--remap=") {
            let value = String(argument.dropFirst("--remap=".count))
            guard !value.isEmpty else {
                throw DriverError.invalidArgument("Empty --remap option in profile-create.")
            }
            keymapRemaps.append(value)
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown profile-create option: \(argument)")
        } else {
            rgbAssignments.append(argument)
        }
    }

    let profile = CombinedProfile(
        format: "gmk67-profile",
        version: 1,
        name: name,
        rgbPreset: rgbPresetName,
        keymapPreset: keymapPresetName,
        rgbFill: rgbFill,
        rgbAssignments: rgbAssignments.isEmpty ? nil : rgbAssignments,
        keymapRemaps: keymapRemaps.isEmpty ? nil : keymapRemaps
    )
    try validateCombinedProfile(profile)
    return (path, profile)
}

private func parseProfileLibraryCreateOptions(_ args: [String]) throws -> CombinedProfile {
    let parsed = try parseProfileCreateOptions(["profile"] + args)
    return parsed.profile
}

private func parseKeymapProfileCreateOptions(_ args: [String]) throws -> (path: String, profile: KeymapProfile) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("keymap-profile-create requires a path.")
    }
    var name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var remaps: [String] = []

    for argument in args.dropFirst() {
        if argument.hasPrefix("--name=") {
            name = String(argument.dropFirst("--name=".count))
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown keymap-profile-create option: \(argument)")
        } else {
            remaps.append(argument)
        }
    }

    let profile = KeymapProfile(format: "gmk67-keymap-profile", version: 1, name: name, remaps: remaps)
    try validateKeymapProfile(profile)
    return (path, profile)
}

private func parseKeymapLibraryCreateOptions(_ args: [String]) throws -> KeymapProfile {
    let parsed = try parseKeymapProfileCreateOptions(["keymap-profile"] + args)
    return parsed.profile
}

private func validateKeymapProfile(_ profile: KeymapProfile) throws {
    guard profile.format == "gmk67-keymap-profile", profile.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 keymap profile format/version.")
    }
    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DriverError.invalidArgument("Keymap profile name must not be empty.")
    }
    let remaps = try parseKeymapRemapSpecs(profile.remaps)
    _ = try keymapRemapTable(remaps)
}

private func writeKeymapProfile(_ profile: KeymapProfile, path: String) throws {
    try validateKeymapProfile(profile)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func readKeymapProfile(_ path: String) throws -> KeymapProfile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let profile = try JSONDecoder().decode(KeymapProfile.self, from: data)
    try validateKeymapProfile(profile)
    return profile
}

private func printKeymapProfile(_ profile: KeymapProfile) {
    print("Keymap profile: \(profile.name)")
    print("  remaps: \(profile.remaps.count)")
    for remap in (try? parseKeymapRemapSpecs(profile.remaps)) ?? [] {
        print("    \(keymapRemapSummary(remap))")
    }
}

private func printKeymapProfileJSON(_ profile: KeymapProfile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

private func keymapProfileSequence(_ profile: KeymapProfile) throws -> [[UInt8]] {
    keymapFeatureSequence(table: try keymapRemapTable(try parseKeymapRemapSpecs(profile.remaps)))
}

private func writeKeymapProfileSequence(_ profile: KeymapProfile, path: String) throws {
    try writeFeatureSequenceFile(try keymapProfileSequence(profile), path: path)
}

private func parseMacroCreateOptions(_ args: [String]) throws -> (path: String, macro: MacroProfile) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("macro-create requires a path.")
    }
    var name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var repeatCount = 1
    var eventSpecs: [String] = []

    for argument in args.dropFirst() {
        if argument.hasPrefix("--name=") {
            name = String(argument.dropFirst("--name=".count))
        } else if argument.hasPrefix("--repeat=") {
            let value = String(argument.dropFirst("--repeat=".count))
            guard let parsed = Int(value), parsed >= 1, parsed <= 255 else {
                throw DriverError.invalidArgument("Macro repeat count must be between 1 and 255.")
            }
            repeatCount = parsed
        } else if argument.hasPrefix("--event=") {
            let value = String(argument.dropFirst("--event=".count))
            guard !value.isEmpty else {
                throw DriverError.invalidArgument("Empty --event option in macro-create.")
            }
            eventSpecs.append(value)
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown macro-create option: \(argument)")
        } else {
            eventSpecs.append(argument)
        }
    }

    let macro = MacroProfile(
        format: "gmk67-macro",
        version: 1,
        name: name,
        repeatCount: repeatCount,
        events: try parseMacroEventSpecs(eventSpecs)
    )
    try validateMacroProfile(macro)
    return (path, macro)
}

private func parseMacroLibraryCreateOptions(_ args: [String]) throws -> MacroProfile {
    let parsed = try parseMacroCreateOptions(["macro"] + args)
    return parsed.macro
}

private func parseMacroEventSpecs(_ specs: [String]) throws -> [MacroEvent] {
    guard !specs.isEmpty else {
        throw DriverError.invalidArgument("At least one macro event is required.")
    }
    return try specs.map(parseMacroEventSpec)
}

private func parseMacroEventSpec(_ spec: String) throws -> MacroEvent {
    let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid macro event '\(spec)'. Use key:A, down:A, up:A, delay:50, or text:hello.")
    }
    let type = String(parts[0]).lowercased()
    let value = String(parts[1])

    switch type {
    case "key", "tap", "down", "up":
        let usage = try hidUsageByArgument(value)
        let normalizedType = type == "tap" ? "key" : type
        return MacroEvent(type: normalizedType, key: value, usage: hexByte(usage), text: nil, delayMS: nil)
    case "delay", "wait":
        guard let delay = Int(value), delay >= 0, delay <= 60_000 else {
            throw DriverError.invalidArgument("Macro delay must be between 0 and 60000 ms in '\(spec)'.")
        }
        return MacroEvent(type: "delay", key: nil, usage: nil, text: nil, delayMS: delay)
    case "text":
        guard value.count <= 256 else {
            throw DriverError.invalidArgument("Macro text event is limited to 256 characters.")
        }
        return MacroEvent(type: "text", key: nil, usage: nil, text: value, delayMS: nil)
    default:
        throw DriverError.invalidArgument("Unknown macro event type '\(type)' in '\(spec)'.")
    }
}

private func validateMacroProfile(_ macro: MacroProfile) throws {
    guard macro.format == "gmk67-macro", macro.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 macro format/version.")
    }
    guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DriverError.invalidArgument("Macro name must not be empty.")
    }
    guard macro.repeatCount >= 1, macro.repeatCount <= 255 else {
        throw DriverError.invalidArgument("Macro repeat count must be between 1 and 255.")
    }
    guard !macro.events.isEmpty else {
        throw DriverError.invalidArgument("Macro must contain at least one event.")
    }
    for event in macro.events {
        switch event.type {
        case "key", "down", "up":
            guard let key = event.key, let usage = event.usage, usage.hasPrefix("0x") else {
                throw DriverError.invalidArgument("Macro key event is missing key or usage.")
            }
            _ = try hidUsageByArgument(key)
        case "delay":
            guard let delay = event.delayMS, delay >= 0, delay <= 60_000 else {
                throw DriverError.invalidArgument("Macro delay event must be between 0 and 60000 ms.")
            }
        case "text":
            guard let text = event.text, !text.isEmpty, text.count <= 256 else {
                throw DriverError.invalidArgument("Macro text event must be 1...256 characters.")
            }
        default:
            throw DriverError.invalidArgument("Unknown macro event type '\(event.type)'.")
        }
    }
}

private func writeMacroProfile(_ macro: MacroProfile, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(macro)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func readMacroProfile(_ path: String) throws -> MacroProfile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let macro = try JSONDecoder().decode(MacroProfile.self, from: data)
    try validateMacroProfile(macro)
    return macro
}

private func printMacroProfile(_ macro: MacroProfile) {
    print("Macro: \(macro.name)")
    print("  repeat: \(macro.repeatCount)")
    print("  events: \(macro.events.count)")
    for (index, event) in macro.events.enumerated() {
        switch event.type {
        case "key", "down", "up":
            print("    \(index + 1). \(event.type) \(event.key ?? "-") usage=\(event.usage ?? "-")")
        case "delay":
            print("    \(index + 1). delay \(event.delayMS ?? 0) ms")
        case "text":
            print("    \(index + 1). text \(event.text ?? "")")
        default:
            print("    \(index + 1). \(event.type)")
        }
    }
}

private func printMacroProfileJSON(_ macro: MacroProfile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(macro)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

private func defaultProfileLibraryDirectory() -> URL {
    if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("GMK67", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }
    return URL(fileURLWithPath: ".gmk67-profiles", isDirectory: true)
}

private func profileLibraryDirectory(from args: inout [String]) throws -> URL {
    if let index = args.firstIndex(where: { $0.hasPrefix("--directory=") }) {
        let value = String(args.remove(at: index).dropFirst("--directory=".count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("--directory must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return defaultProfileLibraryDirectory()
}

private func profileLibrarySlotName(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw DriverError.invalidArgument("Profile slot name must not be empty.")
    }

    var result = ""
    var previousWasDash = false
    for scalar in trimmed.unicodeScalars {
        let isAllowed = CharacterSet.alphanumerics.contains(scalar)
        if isAllowed {
            result.unicodeScalars.append(scalar)
            previousWasDash = false
        } else if !previousWasDash {
            result.append("-")
            previousWasDash = true
        }
    }
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    guard !result.isEmpty else {
        throw DriverError.invalidArgument("Profile slot name contains no usable filename characters.")
    }
    return result
}

private func profileLibraryURL(slot: String, directory: URL) throws -> URL {
    directory.appendingPathComponent(try profileLibrarySlotName(slot)).appendingPathExtension("json")
}

private func ensureProfileLibraryDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

private func profileLibraryEntries(directory: URL) throws -> [(slot: String, url: URL, profile: CombinedProfile)] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )

    var entries: [(slot: String, url: URL, profile: CombinedProfile)] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        let profile = try readCombinedProfile(url.path)
        entries.append((url.deletingPathExtension().lastPathComponent, url, profile))
    }
    return entries.sorted { $0.slot.localizedStandardCompare($1.slot) == .orderedAscending }
}

private func printProfileLibraryList(directory: URL) throws {
    let entries = try profileLibraryListItems(directory: directory)
    print("Profile library: \(directory.path)")
    if entries.isEmpty {
        print("  no saved profiles")
        return
    }

    for entry in entries {
        let keymap = entry.keymapPreset ?? "-"
        print("  \(entry.slot) - \(entry.name)")
        print("    rgb=\(entry.rgbPreset) keymap=\(keymap) custom-rgb=\(entry.customRGB) custom-remaps=\(entry.customRemaps)")
    }
}

private func profileLibraryListItems(directory: URL) throws -> [ProfileLibraryListItem] {
    try profileLibraryEntries(directory: directory).map { entry in
        ProfileLibraryListItem(
            slot: entry.slot,
            name: entry.profile.name,
            rgbPreset: entry.profile.rgbPreset,
            keymapPreset: entry.profile.keymapPreset,
            customRGB: (entry.profile.rgbAssignments ?? []).count,
            customRemaps: (entry.profile.keymapRemaps ?? []).count
        )
    }
}

private func printProfileLibraryJSON(directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profileLibraryListItems(directory: directory))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

private func printCombinedProfileJSON(_ profile: CombinedProfile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

private func saveProfileToLibrary(_ profile: CombinedProfile, slot: String?, directory: URL) throws -> URL {
    try ensureProfileLibraryDirectory(directory)
    let url = try profileLibraryURL(slot: slot ?? profile.name, directory: directory)
    try writeCombinedProfile(profile, path: url.path)
    return url
}

private func readProfileFromLibrary(slot: String, directory: URL) throws -> CombinedProfile {
    try readCombinedProfile(try profileLibraryURL(slot: slot, directory: directory).path)
}

private func profileLibraryBundle(from directory: URL) throws -> ProfileLibraryBundle {
    let entries = try profileLibraryEntries(directory: directory).map { entry in
        ProfileLibraryBundleEntry(slot: entry.slot, profile: entry.profile)
    }
    return ProfileLibraryBundle(
        format: "gmk67-profile-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        profiles: entries
    )
}

private func writeProfileLibraryBundle(directory: URL, path: String) throws -> ProfileLibraryBundle {
    let bundle = try profileLibraryBundle(from: directory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

private func readProfileLibraryBundle(_ path: String) throws -> ProfileLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(ProfileLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-profile-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 profile library bundle format/version.")
    }
    var seenSlots = Set<String>()
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        guard seenSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate profile slot in library bundle: \(slot)")
        }
        try validateCombinedProfile(entry.profile)
    }
    return bundle
}

private func importProfileLibraryBundle(_ path: String, directory: URL) throws -> [String] {
    let bundle = try readProfileLibraryBundle(path)
    try ensureProfileLibraryDirectory(directory)
    var importedSlots: [String] = []
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        let url = try profileLibraryURL(slot: slot, directory: directory)
        try writeCombinedProfile(entry.profile, path: url.path)
        importedSlots.append(slot)
    }
    return importedSlots
}

private func defaultKeymapLibraryDirectory() -> URL {
    if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("GMK67", isDirectory: true)
            .appendingPathComponent("Keymaps", isDirectory: true)
    }
    return URL(fileURLWithPath: ".gmk67-keymaps", isDirectory: true)
}

private func keymapLibraryDirectory(from args: inout [String]) throws -> URL {
    if let index = args.firstIndex(where: { $0.hasPrefix("--directory=") }) {
        let value = String(args.remove(at: index).dropFirst("--directory=".count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("--directory must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return defaultKeymapLibraryDirectory()
}

private func keymapLibraryURL(slot: String, directory: URL) throws -> URL {
    directory.appendingPathComponent(try profileLibrarySlotName(slot)).appendingPathExtension("json")
}

private func ensureKeymapLibraryDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

private func saveKeymapToLibrary(_ profile: KeymapProfile, slot: String?, directory: URL) throws -> URL {
    try ensureKeymapLibraryDirectory(directory)
    let url = try keymapLibraryURL(slot: slot ?? profile.name, directory: directory)
    try writeKeymapProfile(profile, path: url.path)
    return url
}

private func readKeymapFromLibrary(slot: String, directory: URL) throws -> KeymapProfile {
    try readKeymapProfile(try keymapLibraryURL(slot: slot, directory: directory).path)
}

private func keymapLibraryEntries(directory: URL) throws -> [(slot: String, url: URL, profile: KeymapProfile)] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    var entries: [(slot: String, url: URL, profile: KeymapProfile)] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        let profile = try readKeymapProfile(url.path)
        entries.append((url.deletingPathExtension().lastPathComponent, url, profile))
    }
    return entries.sorted { $0.slot.localizedStandardCompare($1.slot) == .orderedAscending }
}

private func keymapLibraryListItems(directory: URL) throws -> [KeymapLibraryListItem] {
    try keymapLibraryEntries(directory: directory).map { entry in
        KeymapLibraryListItem(slot: entry.slot, name: entry.profile.name, remapCount: entry.profile.remaps.count)
    }
}

private func printKeymapLibraryList(directory: URL) throws {
    let entries = try keymapLibraryListItems(directory: directory)
    print("Keymap library: \(directory.path)")
    if entries.isEmpty {
        print("  no saved keymaps")
        return
    }
    for entry in entries {
        print("  \(entry.slot) - \(entry.name)")
        print("    remaps=\(entry.remapCount)")
    }
}

private func printKeymapLibraryJSON(directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(keymapLibraryListItems(directory: directory))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

private func keymapLibraryBundle(from directory: URL) throws -> KeymapLibraryBundle {
    let entries = try keymapLibraryEntries(directory: directory).map { entry in
        KeymapLibraryBundleEntry(slot: entry.slot, profile: entry.profile)
    }
    return KeymapLibraryBundle(
        format: "gmk67-keymap-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        profiles: entries
    )
}

private func writeKeymapLibraryBundle(directory: URL, path: String) throws -> KeymapLibraryBundle {
    let bundle = try keymapLibraryBundle(from: directory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

private func readKeymapLibraryBundle(_ path: String) throws -> KeymapLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(KeymapLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-keymap-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 keymap library bundle format/version.")
    }
    var seenSlots = Set<String>()
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        guard seenSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate keymap slot in library bundle: \(slot)")
        }
        try validateKeymapProfile(entry.profile)
    }
    return bundle
}

private func importKeymapLibraryBundle(_ path: String, directory: URL) throws -> [String] {
    let bundle = try readKeymapLibraryBundle(path)
    try ensureKeymapLibraryDirectory(directory)
    var importedSlots: [String] = []
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        let url = try keymapLibraryURL(slot: slot, directory: directory)
        try writeKeymapProfile(entry.profile, path: url.path)
        importedSlots.append(slot)
    }
    return importedSlots
}

private func defaultMacroLibraryDirectory() -> URL {
    if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("GMK67", isDirectory: true)
            .appendingPathComponent("Macros", isDirectory: true)
    }
    return URL(fileURLWithPath: ".gmk67-macros", isDirectory: true)
}

private func macroLibraryDirectory(from args: inout [String]) throws -> URL {
    if let index = args.firstIndex(where: { $0.hasPrefix("--directory=") }) {
        let value = String(args.remove(at: index).dropFirst("--directory=".count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("--directory must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return defaultMacroLibraryDirectory()
}

private func macroLibraryURL(slot: String, directory: URL) throws -> URL {
    directory.appendingPathComponent(try profileLibrarySlotName(slot)).appendingPathExtension("json")
}

private func ensureMacroLibraryDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

private func saveMacroToLibrary(_ macro: MacroProfile, slot: String?, directory: URL) throws -> URL {
    try ensureMacroLibraryDirectory(directory)
    let url = try macroLibraryURL(slot: slot ?? macro.name, directory: directory)
    try writeMacroProfile(macro, path: url.path)
    return url
}

private func readMacroFromLibrary(slot: String, directory: URL) throws -> MacroProfile {
    try readMacroProfile(try macroLibraryURL(slot: slot, directory: directory).path)
}

private func macroLibraryEntries(directory: URL) throws -> [(slot: String, url: URL, macro: MacroProfile)] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    var entries: [(slot: String, url: URL, macro: MacroProfile)] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        let macro = try readMacroProfile(url.path)
        entries.append((url.deletingPathExtension().lastPathComponent, url, macro))
    }
    return entries.sorted { $0.slot.localizedStandardCompare($1.slot) == .orderedAscending }
}

private func macroLibraryListItems(directory: URL) throws -> [MacroLibraryListItem] {
    try macroLibraryEntries(directory: directory).map { entry in
        MacroLibraryListItem(
            slot: entry.slot,
            name: entry.macro.name,
            repeatCount: entry.macro.repeatCount,
            eventCount: entry.macro.events.count
        )
    }
}

private func printMacroLibraryList(directory: URL) throws {
    let entries = try macroLibraryListItems(directory: directory)
    print("Macro library: \(directory.path)")
    if entries.isEmpty {
        print("  no saved macros")
        return
    }
    for entry in entries {
        print("  \(entry.slot) - \(entry.name)")
        print("    repeat=\(entry.repeatCount) events=\(entry.eventCount)")
    }
}

private func printMacroLibraryJSON(directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(macroLibraryListItems(directory: directory))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

private func macroLibraryBundle(from directory: URL) throws -> MacroLibraryBundle {
    let entries = try macroLibraryEntries(directory: directory).map { entry in
        MacroLibraryBundleEntry(slot: entry.slot, macro: entry.macro)
    }
    return MacroLibraryBundle(
        format: "gmk67-macro-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        macros: entries
    )
}

private func writeMacroLibraryBundle(directory: URL, path: String) throws -> MacroLibraryBundle {
    let bundle = try macroLibraryBundle(from: directory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

private func readMacroLibraryBundle(_ path: String) throws -> MacroLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(MacroLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-macro-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 macro library bundle format/version.")
    }
    var seenSlots = Set<String>()
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        guard seenSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate macro slot in library bundle: \(slot)")
        }
        try validateMacroProfile(entry.macro)
    }
    return bundle
}

private func importMacroLibraryBundle(_ path: String, directory: URL) throws -> [String] {
    let bundle = try readMacroLibraryBundle(path)
    try ensureMacroLibraryDirectory(directory)
    var importedSlots: [String] = []
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        let url = try macroLibraryURL(slot: slot, directory: directory)
        try writeMacroProfile(entry.macro, path: url.path)
        importedSlots.append(slot)
    }
    return importedSlots
}

private func appLibraryDirectories(from args: inout [String]) throws -> (profiles: URL, keymaps: URL, macros: URL) {
    var profiles = defaultProfileLibraryDirectory()
    var keymaps = defaultKeymapLibraryDirectory()
    var macros = defaultMacroLibraryDirectory()

    func popDirectoryOption(_ prefix: String) throws -> URL? {
        guard let index = args.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let value = String(args.remove(at: index).dropFirst(prefix.count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("\(prefix.dropLast()) must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    if let value = try popDirectoryOption("--profiles=") {
        profiles = value
    }
    if let value = try popDirectoryOption("--keymaps=") {
        keymaps = value
    }
    if let value = try popDirectoryOption("--macros=") {
        macros = value
    }
    return (profiles, keymaps, macros)
}

private func appLibraryBundle(profileDirectory: URL, keymapDirectory: URL, macroDirectory: URL) throws -> AppLibraryBundle {
    AppLibraryBundle(
        format: "gmk67-app-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        profiles: try profileLibraryEntries(directory: profileDirectory).map { ProfileLibraryBundleEntry(slot: $0.slot, profile: $0.profile) },
        keymaps: try keymapLibraryEntries(directory: keymapDirectory).map { KeymapLibraryBundleEntry(slot: $0.slot, profile: $0.profile) },
        macros: try macroLibraryEntries(directory: macroDirectory).map { MacroLibraryBundleEntry(slot: $0.slot, macro: $0.macro) }
    )
}

private func writeAppLibraryBundle(profileDirectory: URL, keymapDirectory: URL, macroDirectory: URL, path: String) throws -> AppLibraryBundle {
    let bundle = try appLibraryBundle(profileDirectory: profileDirectory, keymapDirectory: keymapDirectory, macroDirectory: macroDirectory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

private func readAppLibraryBundle(_ path: String) throws -> AppLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(AppLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-app-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 app library bundle format/version.")
    }

    var profileSlots = Set<String>()
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        guard profileSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate profile slot in app library bundle: \(slot)")
        }
        try validateCombinedProfile(entry.profile)
    }

    var keymapSlots = Set<String>()
    for entry in bundle.keymaps {
        let slot = try profileLibrarySlotName(entry.slot)
        guard keymapSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate keymap slot in app library bundle: \(slot)")
        }
        try validateKeymapProfile(entry.profile)
    }

    var macroSlots = Set<String>()
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        guard macroSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate macro slot in app library bundle: \(slot)")
        }
        try validateMacroProfile(entry.macro)
    }

    return bundle
}

private func importAppLibraryBundle(_ path: String, profileDirectory: URL, keymapDirectory: URL, macroDirectory: URL) throws -> (profiles: [String], keymaps: [String], macros: [String]) {
    let bundle = try readAppLibraryBundle(path)
    try ensureProfileLibraryDirectory(profileDirectory)
    try ensureKeymapLibraryDirectory(keymapDirectory)
    try ensureMacroLibraryDirectory(macroDirectory)

    var importedProfiles: [String] = []
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        try writeCombinedProfile(entry.profile, path: try profileLibraryURL(slot: slot, directory: profileDirectory).path)
        importedProfiles.append(slot)
    }

    var importedKeymaps: [String] = []
    for entry in bundle.keymaps {
        let slot = try profileLibrarySlotName(entry.slot)
        try writeKeymapProfile(entry.profile, path: try keymapLibraryURL(slot: slot, directory: keymapDirectory).path)
        importedKeymaps.append(slot)
    }

    var importedMacros: [String] = []
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        try writeMacroProfile(entry.macro, path: try macroLibraryURL(slot: slot, directory: macroDirectory).path)
        importedMacros.append(slot)
    }

    return (importedProfiles, importedKeymaps, importedMacros)
}

private func parseProfileApplyOptions(_ args: [String]) throws -> (path: String, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("profile-apply requires a path.")
    }
    var hasUnsafeFlag = false
    var writeIndex = 0
    var readIndex = 0

    for argument in args.dropFirst() {
        if argument == unsafeKeymapFlag {
            hasUnsafeFlag = true
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else if argument.hasPrefix("--read-index=") {
            let value = String(argument.dropFirst("--read-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --read-index value: \(value)")
            }
            readIndex = parsed
        } else {
            throw DriverError.invalidArgument("Unknown profile-apply option: \(argument)")
        }
    }

    return (path, hasUnsafeFlag, writeIndex, readIndex)
}

private func parseProfilePresetApplyOptions(_ args: [String]) throws -> (name: String, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) {
    guard let name = args.first else {
        throw DriverError.invalidArgument("profile-preset-apply requires a preset name.")
    }
    let options = try parseProfileApplyOptions(["profile-preset"] + Array(args.dropFirst()))
    return (name, options.hasUnsafeFlag, options.writeIndex, options.readIndex)
}

private func parseInlineProfileApplyOptions(_ args: [String]) throws -> (profile: CombinedProfile, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) {
    var profileArgs: [String] = []
    var hasUnsafeFlag = false
    var writeIndex = 0
    var readIndex = 0

    for argument in args {
        if argument == unsafeKeymapFlag {
            hasUnsafeFlag = true
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else if argument.hasPrefix("--read-index=") {
            let value = String(argument.dropFirst("--read-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --read-index value: \(value)")
            }
            readIndex = parsed
        } else {
            profileArgs.append(argument)
        }
    }

    let profile = try parseProfileLibraryCreateOptions(profileArgs)
    return (profile, hasUnsafeFlag, writeIndex, readIndex)
}

private func applyCombinedProfileToDevice(_ profile: CombinedProfile, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) throws {
    if combinedProfileHasKeymap(profile) && !hasUnsafeFlag {
        throw DriverError.invalidArgument("Refusing to apply a profile with keymap changes without \(unsafeKeymapFlag). RGB-only profile sections can be applied without the flag.")
    }

    let driver = HIDDriver()
    let devices = driver.devices()
    guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
        throw DriverError.noDevice
    }
    let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
    let readDevice = try driver.device(at: readIndex, configurationOnly: false)

    print("Applying GMK67 profile:")
    printCombinedProfile(profile)
    let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
    let backupPath = try backupRGBFrames(currentFrames)
    print("Saved pre-write RGB table to \(backupPath).")

    let frames = try combinedProfileRGBFrames(profile)
    print("Applying RGB profile \(profile.rgbPreset) with \(profile.rgbAssignments?.count ?? 0) custom assignment(s).")
    try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
    print("RGB write sequence sent. Reading rendered table back...")
    let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
    print("Note: rendered RGB readback may be scaled or mode-composited and may not exactly echo the preset bytes.")
    print("Non-zero RGB records:")
    printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    let remaps = try combinedProfileKeymapRemaps(profile)
    if !remaps.isEmpty {
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying \(remaps.count) keymap remap(s).")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print(String(format: "Writing keymap on scanned interface %d using %d feature reports...", writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: writeDevice, payloads: sequence)
        print("Candidate keymap preset sequence sent.")
    }
}

private func combinedProfileKeymapSequence(_ profile: CombinedProfile) throws -> [[UInt8]]? {
    let remaps = try combinedProfileKeymapRemaps(profile)
    guard !remaps.isEmpty else { return nil }
    return keymapFeatureSequence(table: try keymapRemapTable(remaps))
}

private func printCombinedProfilePreview(_ profile: CombinedProfile) throws {
    printCombinedProfile(profile)

    let frames = try combinedProfileRGBFrames(profile)
    print("Rendered RGB records:")
    printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    let remaps = try combinedProfileKeymapRemaps(profile)
    if remaps.isEmpty {
        print("Keymap remaps: none")
    } else {
        print("Keymap remaps:")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        print("Candidate keymap sequence: \(sequence.count) reports, 9 table chunks, AA 55 marker at table offset 0x23E.")
    }
    print("Preview only: no HID device was opened and no reports were sent.")
}

private func factoryResetRGBFrames() throws -> [[UInt8]] {
    var frames = sampleRGBFrames()
    try applyRGBFill([0x00, 0x00, 0x00], to: &frames, keyMap: physicalKeysByLightIndex())
    return frames
}

private func factoryResetKeymapSequence() -> [[UInt8]] {
    keymapFeatureSequence(table: emptyKeymapTable())
}

private func writeFactoryResetArtifacts(prefix: String) throws -> (rgbPath: String, keymapPath: String) {
    let rgbPath = "\(prefix)-rgb.hex"
    let keymapPath = "\(prefix)-keymap-clear.hex"
    try writeRGBFramesFile(try factoryResetRGBFrames(), path: rgbPath)
    try writeFeatureSequenceFile(factoryResetKeymapSequence(), path: keymapPath)
    return (rgbPath, keymapPath)
}

private func applyFactoryResetToDevice(writeIndex: Int, readIndex: Int) throws {
    let driver = HIDDriver()
    let devices = driver.devices()
    guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
        throw DriverError.noDevice
    }
    let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
    let readDevice = try driver.device(at: readIndex, configurationOnly: false)

    print("Applying modeled GMK67 factory reset.")
    print("This clears known physical RGB records and writes an empty custom-keymap table.")
    let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
    let backupPath = try backupRGBFrames(currentFrames)
    print("Saved pre-reset RGB table to \(backupPath).")

    let resetFrames = try factoryResetRGBFrames()
    try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: resetFrames)
    print("RGB reset sequence sent. Reading rendered table back...")
    let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
    print("Non-zero RGB records after reset:")
    printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    let keymapSequence = factoryResetKeymapSequence()
    print("WARNING: clearing keymaps is not yet backed by a proven device readback/backup path.")
    print(String(format: "Writing empty custom-keymap table on scanned interface %d using %d feature reports...", writeIndex, keymapSequence.count))
    try sendFeatureSequence(driver: driver, device: writeDevice, payloads: keymapSequence)
    print("Candidate empty keymap sequence sent.")
}

private func exportCombinedProfileArtifacts(_ profile: CombinedProfile, prefix: String) throws -> (rgbPath: String, keymapPath: String?) {
    let rgbPath = "\(prefix)-rgb.hex"
    try writeRGBFramesFile(try combinedProfileRGBFrames(profile), path: rgbPath)

    if let sequence = try combinedProfileKeymapSequence(profile) {
        let keymapPath = "\(prefix)-keymap.hex"
        try writeFeatureSequenceFile(sequence, path: keymapPath)
        return (rgbPath, keymapPath)
    }
    return (rgbPath, nil)
}

private func parseRGBMapOptions(_ args: [String]) throws -> (specs: [String], writeIndex: Int, readIndex: Int) {
    var specs: [String] = []
    var writeIndex = 0
    var readIndex = 0

    for argument in args {
        if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else if argument.hasPrefix("--read-index=") {
            let value = String(argument.dropFirst("--read-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --read-index value: \(value)")
            }
            readIndex = parsed
        } else {
            specs.append(argument)
        }
    }

    return (specs, writeIndex, readIndex)
}

private func parseRGBProfileCreateOptions(_ args: [String]) throws -> (specs: [String], fillColor: [UInt8]?) {
    var specs: [String] = []
    var fillColor: [UInt8]?

    for argument in args {
        if argument.hasPrefix("--fill=") {
            let value = String(argument.dropFirst("--fill=".count))
            let color = try parseHexBytes(value)
            guard color.count == 3 else {
                throw DriverError.invalidArgument("--fill must be exactly three bytes, for example --fill=000000.")
            }
            fillColor = color
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown rgb-profile-create option: \(argument)")
        } else {
            specs.append(argument)
        }
    }

    guard fillColor != nil || !specs.isEmpty else {
        throw DriverError.invalidArgument("rgb-profile-create requires --fill=rrggbb, at least one key=rrggbb assignment, or both.")
    }
    return (specs, fillColor)
}

private func parseRGBRestoreLatestOptions(_ args: [String]) throws -> (directory: String, writeIndex: Int, readIndex: Int) {
    var directory = "."
    var writeIndex = 0
    var readIndex = 0

    for argument in args {
        if argument.hasPrefix("--directory=") {
            directory = String(argument.dropFirst("--directory=".count))
            guard !directory.isEmpty else {
                throw DriverError.invalidArgument("--directory must not be empty.")
            }
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else if argument.hasPrefix("--read-index=") {
            let value = String(argument.dropFirst("--read-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --read-index value: \(value)")
            }
            readIndex = parsed
        } else {
            throw DriverError.invalidArgument("Unknown rgb-restore-latest option: \(argument)")
        }
    }

    return (directory, writeIndex, readIndex)
}

private func parseByteNumber(_ argument: String, label: String) throws -> Int {
    let lower = argument.lowercased()
    let normalized = lower.replacingOccurrences(of: "0x", with: "")
    let radix = lower.hasPrefix("0x") ? 16 : 10
    guard let value = Int(normalized, radix: radix), value >= 0, value <= 0xFF else {
        throw DriverError.invalidArgument("\(label) must be a byte value from 0x00 to 0xFF: \(argument)")
    }
    return value
}

private func lightingModeIndexByArgument(_ argument: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> (index: Int, label: String) {
    let lower = argument.lowercased()
    if lower.hasPrefix("0x") {
        let index = try parseByteNumber(argument, label: "Lighting-mode table index")
        return (index, keyMap[index]?.name ?? "index 0x\(String(format: "%02X", index))")
    }

    if let parsed = Int(argument), parsed >= 0, parsed <= 0xFF {
        return (parsed, keyMap[parsed]?.name ?? "index \(parsed)")
    }

    if let key = keyByName(argument) {
        return (key.lightIndex, key.name)
    }

    throw DriverError.invalidArgument("Unknown key or lighting-mode table index: \(argument)")
}

private func parseByteAssignmentSpec(_ spec: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> ByteAssignment {
    let assignment = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard assignment.count == 2, !assignment[0].isEmpty, !assignment[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid byte assignment '\(spec)'. Use index=value, for example 0x27=01.")
    }
    let value = try parseHexBytes(String(assignment[1]))
    guard value.count == 1 else {
        throw DriverError.invalidArgument("Lighting-mode values must be exactly one byte in '\(spec)'.")
    }
    let target = try lightingModeIndexByArgument(String(assignment[0]), keyMap: keyMap)
    return ByteAssignment(index: target.index, label: target.label, value: value[0])
}

private func parseByteAssignmentSpecs(_ specs: [String], keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> [ByteAssignment] {
    let assignments = try specs.map { try parseByteAssignmentSpec($0, keyMap: keyMap) }
    var seenIndices = Set<Int>()
    for assignment in assignments {
        guard seenIndices.insert(assignment.index).inserted else {
            throw DriverError.invalidArgument("Duplicate lighting-mode table index in assignment list: \(assignment.label)")
        }
    }
    return assignments
}

private func applyRGBAssignments(_ assignments: [RGBAssignment], to frames: inout [[UInt8]]) throws {
    for assignment in assignments {
        try setRGBRecord(frames: &frames, lightIndex: assignment.lightIndex, color: assignment.color)
    }
}

private func applyRGBFill(_ color: [UInt8], to frames: inout [[UInt8]], keyMap: [Int: KeyItem]) throws {
    for lightIndex in keyMap.keys {
        try setRGBRecord(frames: &frames, lightIndex: lightIndex, color: color)
    }
}

private func hidUsageByArgument(_ argument: String) throws -> UInt8 {
    if let key = keyByName(argument) {
        guard key.code <= 0xFF else {
            throw DriverError.invalidArgument("HID usage for \(argument) is too large for this keymap encoder.")
        }
        return UInt8(key.code)
    }

    if let usage = hidUsageAliases[keyLookupToken(argument)] {
        return usage
    }

    let normalized = argument.lowercased().replacingOccurrences(of: "0x", with: "")
    let radix = argument.lowercased().hasPrefix("0x") ? 16 : 10
    guard let code = Int(normalized, radix: radix), code >= 0, code <= 0xFF else {
        throw DriverError.invalidArgument("Unknown key or one-byte HID usage: \(argument)")
    }
    return UInt8(code)
}

private func keymapEncodedUsage(_ usage: UInt8) -> UInt8 {
    if usage >= 0xE0 && usage <= 0xE7 {
        return UInt8(1 << (usage - 0xE0))
    }
    return usage
}

private func emptyKeymapTable() -> [UInt8] {
    var table = [UInt8](repeating: 0, count: 0x2B6)
    table[0x23E] = 0xAA
    table[0x23F] = 0x55
    return table
}

private func keymapSimpleRemapTable(source: KeyItem, targetUsage: UInt8, modifierUsage: UInt8?) throws -> [UInt8] {
    try keymapRemapTable([KeymapRemap(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)])
}

private func keymapRemapTable(_ remaps: [KeymapRemap]) throws -> [UInt8] {
    guard !remaps.isEmpty else {
        throw DriverError.invalidArgument("At least one remap is required.")
    }

    var table = emptyKeymapTable()
    var seenSourceIndices = Set<Int>()

    for remap in remaps {
        guard seenSourceIndices.insert(remap.source.keyIndex).inserted else {
            throw DriverError.invalidArgument("Duplicate source key in remap list: \(remap.source.name)")
        }

        try writeKeymapRemap(remap, into: &table)
    }

    return table
}

private func writeKeymapRemap(_ remap: KeymapRemap, into table: inout [UInt8]) throws {
    let offset = remap.source.keyIndex * 4
    guard offset + 3 < 0x23E else {
        throw DriverError.invalidArgument("Source key index \(remap.source.keyIndex) is outside the known keymap table range.")
    }

    let modifier = remap.modifierUsage.map(keymapEncodedUsage) ?? 0
    table[offset] = 0x02
    table[offset + 1] = modifier
    table[offset + 2] = keymapEncodedUsage(remap.targetUsage)
    table[offset + 3] = 0x00
}

private func parseKeymapRemapSpec(_ spec: String) throws -> KeymapRemap {
    let assignment = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard assignment.count == 2, !assignment[0].isEmpty, !assignment[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid remap spec '\(spec)'. Use source=target or source=target:modifier.")
    }

    let targetParts = assignment[1].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard targetParts.count >= 1, !targetParts[0].isEmpty else {
        throw DriverError.invalidArgument("Invalid remap target in '\(spec)'.")
    }
    if targetParts.count == 2, targetParts[1].isEmpty {
        throw DriverError.invalidArgument("Invalid remap modifier in '\(spec)'.")
    }

    return KeymapRemap(
        source: try keyByArgument(String(assignment[0])),
        targetUsage: try hidUsageByArgument(String(targetParts[0])),
        modifierUsage: targetParts.count == 2 ? try hidUsageByArgument(String(targetParts[1])) : nil
    )
}

private func parseKeymapRemapSpecs(_ specs: [String]) throws -> [KeymapRemap] {
    guard !specs.isEmpty else {
        throw DriverError.invalidArgument("At least one remap spec is required.")
    }
    return try specs.map(parseKeymapRemapSpec)
}

private func keymapRemapSummary(_ remap: KeymapRemap) -> String {
    let modifierText = remap.modifierUsage.map {
        String(format: " modifier=0x%02X encoded=0x%02X", $0, keymapEncodedUsage($0))
    } ?? ""
    return String(
        format: "%@ key_index=%d -> target_hid=0x%02X encoded=0x%02X%@ record=%@",
        remap.source.name,
        remap.source.keyIndex,
        remap.targetUsage,
        keymapEncodedUsage(remap.targetUsage),
        modifierText,
        hex(keymapRemapRecord(remap))
    )
}

private func keymapRemapRecord(_ remap: KeymapRemap) -> [UInt8] {
    [
        0x02,
        remap.modifierUsage.map(keymapEncodedUsage) ?? 0,
        keymapEncodedUsage(remap.targetUsage),
        0x00
    ]
}

private func hexByte(_ value: UInt8) -> String {
    String(format: "0x%02X", value)
}

private func keymapUsageName(encoded value: UInt8, keysByCode: [Int: KeyItem]) -> String {
    if let preferred = preferredHIDUsageNames[value] {
        return preferred
    }
    if let key = keysByCode[Int(value)] {
        return key.name
    }
    return hexByte(value)
}

private func keymapRecordJSON(_ payloads: [[UInt8]]) throws -> [KeymapRecordJSON] {
    let table = Array(payloads[2...10].joined())
    let keys = try loadKeyboardLayout()
    let keysByIndex = Dictionary(uniqueKeysWithValues: keys.map { ($0.keyIndex, $0) })
    let keysByCode = Dictionary(grouping: keys, by: { $0.code }).compactMapValues { $0.first }
    let duplicateTokens = duplicateKeyNameTokens(keys)
    var records: [KeymapRecordJSON] = []

    for offset in stride(from: 0, to: 0x23C, by: 4) {
        let record = Array(table[offset..<(offset + 4)])
        guard record.contains(where: { $0 != 0 }) else { continue }

        let keyIndex = offset / 4
        let source = keysByIndex[keyIndex]
        let modifierEncoded = record[1]
        let targetEncoded = record[2]
        let modifierName = modifierEncoded == 0 ? nil : modifierNameByEncodedUsage[modifierEncoded]
        let modifierUsage = modifierEncoded == 0 ? nil : modifierUsageByEncodedUsage[modifierEncoded].map(hexByte)
        let target = keymapUsageName(encoded: targetEncoded, keysByCode: keysByCode)
        let warning = record[0] == 0x02 ? nil : "unexpected-record-type"
        let spec: String?
        if let source, warning == nil {
            let sourceSpec = parseableSpecTarget(for: source, offset: source.keyIndex, duplicateKeyTokens: duplicateTokens)
            if let modifierName {
                spec = "\(sourceSpec)=\(target):\(modifierName)"
            } else {
                spec = "\(sourceSpec)=\(target)"
            }
        } else {
            spec = nil
        }

        records.append(KeymapRecordJSON(
            offset: offset,
            keyIndex: keyIndex,
            source: source?.name,
            target: target,
            targetUsage: hexByte(targetEncoded),
            targetEncoded: hexByte(targetEncoded),
            modifier: modifierName,
            modifierUsage: modifierUsage,
            modifierEncoded: hexByte(modifierEncoded),
            record: hex(record),
            spec: spec,
            warning: warning
        ))
    }

    return records
}

private func printKeymapRecordsJSON(_ payloads: [[UInt8]]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(keymapRecordJSON(payloads))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

private func keymapFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x11
    select[8] = 0x09
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: table.count) + [commit, finish]
}

private func alternateFullTableFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x27
    select[8] = 0x09
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: 0x2AC) + [commit, finish]
}

private func customLightingRGBTable(assignments: [RGBAssignment]) throws -> [UInt8] {
    // 04 23 extended/custom-RGB path from DeviceDriver.exe declares 0x280 bytes.
    // The Windows chunk wrapper sends nine 64-byte chunks; AA 55 lands at 0x23E.
    var table = [UInt8](repeating: 0, count: 0x280)
    for assignment in assignments {
        let offset = assignment.lightIndex * 4
        guard offset + 3 < 0x23E else {
            throw DriverError.invalidArgument("Light index 0x\(String(format: "%02X", assignment.lightIndex)) is outside the custom-lighting RGB table range.")
        }
        table[offset] = UInt8(assignment.lightIndex)
        table[offset + 1] = assignment.color[0]
        table[offset + 2] = assignment.color[1]
        table[offset + 3] = assignment.color[2]
    }
    table[0x23E] = 0xAA
    table[0x23F] = 0x55
    return table
}

private func customLightingRGBFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x23
    select[8] = 0x09
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: table.count) + [commit, finish]
}

private func lightingModeTable(assignments: [ByteAssignment]) throws -> [UInt8] {
    // 04 23 shorter branch declares 0x100 bytes. The wrapper sends three
    // 64-byte chunks, with AA 55 at table offset 0xBE.
    var table = [UInt8](repeating: 0, count: 0x100)
    for assignment in assignments {
        guard assignment.index < 0xBE else {
            throw DriverError.invalidArgument("Lighting-mode table index 0x\(String(format: "%02X", assignment.index)) is outside the modeled range before the AA 55 marker.")
        }
        table[assignment.index] = assignment.value
    }
    table[0xBE] = 0xAA
    table[0xBF] = 0x55
    return table
}

private func lightingModeFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x23
    select[8] = 0x03
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: table.count) + [commit, finish]
}

private func windowsChunkedFeaturePayloads(_ payload: [UInt8], declaredLength: Int) -> [[UInt8]] {
    if declaredLength <= 0x41 {
        let bodyLength = min(payload.count, 64)
        var report = Array(payload.prefix(bodyLength))
        report += [UInt8](repeating: 0, count: 64 - report.count)
        return [report]
    }

    let chunkCount = max((declaredLength >> 6) - 1, 0)
    return (0..<chunkCount).map { index in
        let start = index * 64
        let end = min(start + 64, payload.count)
        var report = start < end ? Array(payload[start..<end]) : []
        report += [UInt8](repeating: 0, count: 64 - report.count)
        return report
    }
}

private func printFeatureSequence(_ payloads: [[UInt8]]) {
    for (index, payload) in payloads.enumerated() {
        print(String(format: "#%03d report=0x00 len=%3d  %@", index + 1, payload.count, hex(payload)))
    }
}

private func writeFeatureSequenceFile(_ payloads: [[UInt8]], path: String) throws {
    let text = payloads.map(hex).joined(separator: "\n") + "\n"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

private func readFeatureSequenceFile(_ path: String) throws -> [[UInt8]] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let payloads = try text
        .split(whereSeparator: \.isNewline)
        .map { try parseHexBytes(String($0)) }
    guard !payloads.isEmpty else {
        throw DriverError.invalidArgument("Feature sequence file is empty: \(path)")
    }
    return payloads
}

@discardableResult
private func validateKeymapFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count == 13 else {
        throw DriverError.invalidArgument("Expected 13 keymap feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every keymap feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x18] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 18.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x11], payloads[1][8] == 0x09 else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 11 and have byte 8 set to 09.")
    }
    guard Array(payloads[11].prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Report #012 must begin with 04 02.")
    }
    guard Array(payloads[12].prefix(2)) == [0x04, 0xF0] else {
        throw DriverError.invalidArgument("Report #013 must begin with 04 F0.")
    }

    let tableReports = payloads[2...10]
    let table = Array(tableReports.joined())
    guard table.count == 576 else {
        throw DriverError.invalidArgument("Expected nine 64-byte table reports, found \(table.count) table bytes.")
    }
    guard table[0x23E] == 0xAA, table[0x23F] == 0x55 else {
        throw DriverError.invalidArgument("Expected AA 55 marker at table offset 0x23E.")
    }

    let keysByIndex = Dictionary(uniqueKeysWithValues: (try loadKeyboardLayout()).map { ($0.keyIndex, $0) })
    if printSummary {
        print("Keymap sequence OK: 13 reports, 9 table chunks, AA 55 marker at table offset 0x23E.")
        print("Non-zero keymap records:")
    }
    var recordCount = 0
    for offset in stride(from: 0, to: 0x23C, by: 4) {
        let record = Array(table[offset..<(offset + 4)])
        guard record.contains(where: { $0 != 0 }) else { continue }
        recordCount += 1
        let keyIndex = offset / 4
        let key = keysByIndex[keyIndex]
        let label = key.map { " key=\($0.name)" } ?? ""
        let warning = record[0] == 0x02 ? "" : " warning=unexpected-record-type"
        if printSummary {
            print(String(
                format: "  offset=0x%03X key_index=%d%@ record=%@ target_encoded=0x%02X modifier_encoded=0x%02X%@",
                offset,
                keyIndex,
                label,
                hex(record),
                record[2],
                record[1],
                warning
            ))
        }
    }
    if printSummary && recordCount == 0 {
        print("  none")
    }
    return payloads
}

@discardableResult
private func validateCustomLightingRGBFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count == 13 else {
        throw DriverError.invalidArgument("Expected 13 custom-lighting RGB feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every custom-lighting RGB feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x18] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 18.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x23], payloads[1][8] == 0x09 else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 23 and have byte 8 set to 09.")
    }
    guard Array(payloads[11].prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Report #012 must begin with 04 02.")
    }
    guard Array(payloads[12].prefix(2)) == [0x04, 0xF0] else {
        throw DriverError.invalidArgument("Report #013 must begin with 04 F0.")
    }

    let table = Array(payloads[2...10].joined())
    guard table.count == 576 else {
        throw DriverError.invalidArgument("Expected nine 64-byte custom-lighting table reports, found \(table.count) table bytes.")
    }
    guard table[0x23E] == 0xAA, table[0x23F] == 0x55 else {
        throw DriverError.invalidArgument("Expected AA 55 marker at custom-lighting table offset 0x23E.")
    }

    if printSummary {
        print("Custom-lighting RGB sequence OK: 13 reports, selector 04 23 byte8=09, 9 table chunks, AA 55 marker at table offset 0x23E.")
        print("Non-zero custom-lighting RGB records:")
        printRGBRecords(Array(payloads[2...10]), keyByLightIndex: keyMapByLightIndex(), recordByteLimit: 0x23E)
    }
    return payloads
}

@discardableResult
private func validateLightingModeFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count == 7 else {
        throw DriverError.invalidArgument("Expected 7 lighting-mode feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every lighting-mode feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x18] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 18.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x23], payloads[1][8] == 0x03 else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 23 and have byte 8 set to 03.")
    }
    guard Array(payloads[5].prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Report #006 must begin with 04 02.")
    }
    guard Array(payloads[6].prefix(2)) == [0x04, 0xF0] else {
        throw DriverError.invalidArgument("Report #007 must begin with 04 F0.")
    }

    let table = Array(payloads[2...4].joined())
    guard table.count == 192 else {
        throw DriverError.invalidArgument("Expected three 64-byte lighting-mode table reports, found \(table.count) table bytes.")
    }
    guard table[0xBE] == 0xAA, table[0xBF] == 0x55 else {
        throw DriverError.invalidArgument("Expected AA 55 marker at lighting-mode table offset 0xBE.")
    }

    if printSummary {
        print("Lighting-mode sequence OK: 7 reports, selector 04 23 byte8=03, 3 table chunks, AA 55 marker at table offset 0xBE.")
        print("Non-zero lighting-mode table bytes:")
        printByteTableRecords(Array(payloads[2...4]), byteLimit: 0xBE, keyByLightIndex: keyMapByLightIndex())
    }
    return payloads
}

@discardableResult
private func validateAlternateFullTableFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count == 13 else {
        throw DriverError.invalidArgument("Expected 13 alternate full-table feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every alternate full-table feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x18] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 18.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x27], payloads[1][8] == 0x09 else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 27 and have byte 8 set to 09.")
    }
    guard Array(payloads[11].prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Report #012 must begin with 04 02.")
    }
    guard Array(payloads[12].prefix(2)) == [0x04, 0xF0] else {
        throw DriverError.invalidArgument("Report #013 must begin with 04 F0.")
    }

    let table = Array(payloads[2...10].joined())
    guard table.count == 576 else {
        throw DriverError.invalidArgument("Expected nine 64-byte alternate full-table reports, found \(table.count) table bytes.")
    }
    guard table[0x23E] == 0xAA, table[0x23F] == 0x55 else {
        throw DriverError.invalidArgument("Expected AA 55 marker at alternate full-table offset 0x23E.")
    }

    let keysByIndex = Dictionary(uniqueKeysWithValues: (try loadKeyboardLayout()).map { ($0.keyIndex, $0) })
    if printSummary {
        print("Alternate full-table sequence OK: 13 reports, selector 04 27 byte8=09, declared length 0x2AC, 9 visible table chunks, AA 55 marker at table offset 0x23E.")
        print("Non-zero alternate full-table records:")
    }
    var recordCount = 0
    for offset in stride(from: 0, to: 0x23C, by: 4) {
        let record = Array(table[offset..<(offset + 4)])
        guard record.contains(where: { $0 != 0 }) else { continue }
        recordCount += 1
        let keyIndex = offset / 4
        let key = keysByIndex[keyIndex]
        let label = key.map { " key=\($0.name)" } ?? ""
        if printSummary {
            print(String(format: "  offset=0x%03X key_index=%d%@ record=%@", offset, keyIndex, label, hex(record)))
        }
    }
    if printSummary && recordCount == 0 {
        print("  none")
    }
    return payloads
}

private func sendFeatureSequence(driver: HIDDriver, device: IOHIDDevice, payloads: [[UInt8]]) throws {
    for payload in payloads {
        guard payload.count == 64 else {
            throw DriverError.invalidArgument("Feature sequence payloads must be exactly 64 bytes.")
        }
        try driver.setFeature(device: device, reportID: 0, payload: payload)
        usleep(30_000)
    }
}

private func sendUnsafeCandidateFeatureSequence(_ payloads: [[UInt8]], writeIndex: Int, kind: String) throws {
    let driver = HIDDriver()
    let devices = driver.devices()
    guard devices.indices.contains(writeIndex) else {
        throw DriverError.noDevice
    }
    let device = try driver.device(at: writeIndex, configurationOnly: false)
    print("WARNING: writing \(kind) is not backed by a proven device readback/backup path.")
    print(String(format: "Writing %@ on scanned interface %d using %d feature reports...", kind, writeIndex, payloads.count))
    try sendFeatureSequence(driver: driver, device: device, payloads: payloads)
    print("Candidate \(kind) sequence sent.")
}

private func parseUnsafeKeymapOptions(_ args: [String]) throws -> (operands: [String], writeIndex: Int) {
    var operands: [String] = []
    var hasUnsafeFlag = false
    var writeIndex = 0

    for argument in args {
        if argument == unsafeKeymapFlag {
            hasUnsafeFlag = true
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else {
            operands.append(argument)
        }
    }

    guard hasUnsafeFlag else {
        throw DriverError.invalidArgument("Refusing to write keymap without \(unsafeKeymapFlag). There is not yet a proven keymap backup/readback path.")
    }
    return (operands, writeIndex)
}

private func parseUnsafeKeymapFileOptions(_ args: [String]) throws -> (path: String, writeIndex: Int) {
    let options = try parseUnsafeKeymapOptions(args)
    guard options.operands.count == 1 else {
        throw DriverError.invalidArgument("Expected exactly one keymap sequence file path.")
    }
    return (options.operands[0], options.writeIndex)
}

private func parseUnsafeCandidateFileOptions(_ args: [String], kind: String) throws -> (path: String, writeIndex: Int) {
    var operands: [String] = []
    var hasUnsafeFlag = false
    var writeIndex = 0

    for argument in args {
        if argument == unsafeKeymapFlag {
            hasUnsafeFlag = true
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else {
            operands.append(argument)
        }
    }

    guard hasUnsafeFlag else {
        throw DriverError.invalidArgument("Refusing to write \(kind) without \(unsafeKeymapFlag). There is not yet a proven readback/backup path for this protocol family.")
    }
    guard operands.count == 1 else {
        throw DriverError.invalidArgument("Expected exactly one \(kind) feature sequence file path.")
    }
    return (operands[0], writeIndex)
}

private func parseUnsafeCandidateNameOptions(_ args: [String], kind: String) throws -> (name: String, writeIndex: Int) {
    var operands: [String] = []
    var hasUnsafeFlag = false
    var writeIndex = 0

    for argument in args {
        if argument == unsafeKeymapFlag {
            hasUnsafeFlag = true
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else {
            operands.append(argument)
        }
    }

    guard hasUnsafeFlag else {
        throw DriverError.invalidArgument("Refusing to write \(kind) without \(unsafeKeymapFlag). There is not yet a proven readback/backup path for this protocol family.")
    }
    guard operands.count == 1 else {
        throw DriverError.invalidArgument("Expected exactly one \(kind) preset name.")
    }
    return (operands[0], writeIndex)
}

private func parseUnsafeFactoryResetOptions(_ args: [String]) throws -> (writeIndex: Int, readIndex: Int) {
    var hasUnsafeFlag = false
    var writeIndex = 0
    var readIndex = 0

    for argument in args {
        if argument == unsafeKeymapFlag {
            hasUnsafeFlag = true
        } else if argument.hasPrefix("--write-index=") {
            let value = String(argument.dropFirst("--write-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --write-index value: \(value)")
            }
            writeIndex = parsed
        } else if argument.hasPrefix("--read-index=") {
            let value = String(argument.dropFirst("--read-index=".count))
            guard let parsed = Int(value), parsed >= 0 else {
                throw DriverError.invalidArgument("Invalid --read-index value: \(value)")
            }
            readIndex = parsed
        } else {
            throw DriverError.invalidArgument("Unknown factory-reset option: \(argument)")
        }
    }

    guard hasUnsafeFlag else {
        throw DriverError.invalidArgument("Refusing modeled factory reset without \(unsafeKeymapFlag). It includes an unbacked custom-keymap clear.")
    }
    return (writeIndex, readIndex)
}

private func assertSelfTest(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw DriverError.invalidArgument("Self-test failed: \(message)")
    }
}

private func expectInvalidArgument(_ message: String, _ body: () throws -> Void) throws {
    do {
        try body()
    } catch DriverError.invalidArgument {
        return
    }
    throw DriverError.invalidArgument("Self-test failed: expected invalid argument for \(message)")
}

private func sampleRGBFrames() -> [[UInt8]] {
    (0..<9).map { frameIndex in
        var frame: [UInt8] = []
        for recordIndex in 0..<16 {
            frame += [UInt8(frameIndex * 16 + recordIndex), 0, 0, 0]
        }
        return frame
    }
}

private func runSelfTest(verbose: Bool = true) throws {
    if verbose {
        print("Running offline self-test...")
    }

    let compactHex = try parseHexBytes("FF0000")
    let spacedHex = try parseHexBytes("FF 00 00")
    try assertSelfTest(compactHex == [0xFF, 0x00, 0x00], "compact RGB hex parsing")
    try assertSelfTest(spacedHex == [0xFF, 0x00, 0x00], "spaced RGB hex parsing")

    let keyMap = keyMapByLightIndex()
    let rgbAssignments = try parseRGBAssignmentSpecs(
        ["W=FF0000", "A=00FF00", "S=0000FF", "D=00FFFF"],
        keyMap: keyMap
    )
    try assertSelfTest(rgbAssignments.map(\.lightIndex) == [0x27, 0x38, 0x39, 0x3A], "RGB assignment key lookup")
    try expectInvalidArgument("duplicate RGB target") {
        _ = try parseRGBAssignmentSpecs(["W=FF0000", "W=00FF00"], keyMap: keyMap)
    }

    var frames = sampleRGBFrames()
    try applyRGBAssignments(rgbAssignments, to: &frames)
    try assertSelfTest(Array(frames[2][28..<32]) == [0x27, 0xFF, 0x00, 0x00], "W RGB record")
    try assertSelfTest(Array(frames[3][32..<44]) == [
        0x38, 0x00, 0xFF, 0x00,
        0x39, 0x00, 0x00, 0xFF,
        0x3A, 0x00, 0xFF, 0xFF
    ], "A/S/D RGB records")

    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gmk67-self-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    let rgbPath = tempDirectory.appendingPathComponent("rgb.hex").path
    try writeRGBFramesFile(frames, path: rgbPath)
    let loadedRGBFrames = try readRGBFramesFile(rgbPath)
    try assertSelfTest(loadedRGBFrames.count == 9, "RGB file frame count")
    try assertSelfTest(Array(loadedRGBFrames[2][28..<32]) == [0x27, 0xFF, 0x00, 0x00], "RGB file round trip")

    let olderBackup = tempDirectory.appendingPathComponent("\(rgbBackupPrefix)20200101-000000\(rgbBackupSuffix)").path
    let newerBackup = tempDirectory.appendingPathComponent("\(rgbBackupPrefix)20200101-000001\(rgbBackupSuffix)").path
    let invalidBackup = tempDirectory.appendingPathComponent("\(rgbBackupPrefix)20200101-000002\(rgbBackupSuffix)").path
    try writeRGBFramesFile(sampleRGBFrames(), path: olderBackup)
    try writeRGBFramesFile(frames, path: newerBackup)
    try "not an rgb table\n".write(toFile: invalidBackup, atomically: true, encoding: .utf8)
    let backups = rgbBackupFiles(directoryPath: tempDirectory.path)
    try assertSelfTest(backups.map { $0.url.lastPathComponent } == [
        "\(rgbBackupPrefix)20200101-000001\(rgbBackupSuffix)",
        "\(rgbBackupPrefix)20200101-000000\(rgbBackupSuffix)"
    ], "RGB backup listing")
    let latestBackup = try latestRGBBackup(directoryPath: tempDirectory.path)
    try assertSelfTest(
        latestBackup.url.lastPathComponent == "\(rgbBackupPrefix)20200101-000001\(rgbBackupSuffix)",
        "latest RGB backup selection"
    )
    let restoreLatestOptions = try parseRGBRestoreLatestOptions([
        "--directory=\(tempDirectory.path)",
        "--write-index=2",
        "--read-index=3"
    ])
    try assertSelfTest(
        restoreLatestOptions.directory == tempDirectory.path &&
            restoreLatestOptions.writeIndex == 2 &&
            restoreLatestOptions.readIndex == 3,
        "restore latest option parsing"
    )

    let profileOptions = try parseRGBProfileCreateOptions(["--fill=000000", "W=FF0000"])
    try assertSelfTest(profileOptions.fillColor == [0x00, 0x00, 0x00], "profile fill parsing")
    var profileFrames = sampleRGBFrames()
    try applyRGBFill(profileOptions.fillColor ?? [0, 0, 0], to: &profileFrames, keyMap: physicalKeysByLightIndex())
    let profileAssignments = try parseRGBAssignmentSpecs(profileOptions.specs, keyMap: keyMap)
    try applyRGBAssignments(profileAssignments, to: &profileFrames)
    try assertSelfTest(Array(profileFrames[2][28..<32]) == [0x27, 0xFF, 0x00, 0x00], "profile W override")
    try assertSelfTest(Array(profileFrames[3][32..<36]) == [0x38, 0x00, 0x00, 0x00], "profile fill record")
    let fillOnlyProfile = try parseRGBProfileCreateOptions(["--fill=010203"])
    try assertSelfTest(fillOnlyProfile.specs.isEmpty && fillOnlyProfile.fillColor == [0x01, 0x02, 0x03], "fill-only profile parsing")
    try expectInvalidArgument("empty profile") {
        _ = try parseRGBProfileCreateOptions([])
    }

    let wasdPreset = try rgbPreset(named: "wasd")
    let wasdPresetData = try JSONEncoder().encode(wasdPreset)
    let decodedWASDPreset = try JSONDecoder().decode(RGBPresetDefinition.self, from: wasdPresetData)
    try assertSelfTest(decodedWASDPreset.fill == "101018" && decodedWASDPreset.assignments.contains("W=FF3B30"), "RGB preset JSON round trip")
    let wasdPresetFrames = try rgbPresetFrames(wasdPreset)
    try assertSelfTest(Array(wasdPresetFrames[2][28..<32]) == [0x27, 0xFF, 0x3B, 0x30], "WASD RGB preset W color")
    try assertSelfTest(Array(wasdPresetFrames[6][12..<16]) == [0x63, 0xFF, 0xCC, 0x00], "WASD RGB preset left arrow color")
    let offPresetFrames = try rgbPresetFrames(try rgbPreset(named: "off"))
    try assertSelfTest(rgbFramesToRecords(offPresetFrames).values.allSatisfy { $0.red == 0 && $0.green == 0 && $0.blue == 0 }, "off RGB preset")
    try expectInvalidArgument("unknown RGB preset") {
        _ = try rgbPreset(named: "unknown")
    }

    let wasdKeymapPreset = try keymapPreset(named: "wasd-arrows")
    let wasdKeymapPresetData = try JSONEncoder().encode(wasdKeymapPreset)
    let decodedWASDKeymapPreset = try JSONDecoder().decode(KeymapPresetDefinition.self, from: wasdKeymapPresetData)
    try assertSelfTest(decodedWASDKeymapPreset.remaps == ["W=up", "A=left", "S=down", "D=right"], "keymap preset JSON round trip")
    try assertSelfTest(wasdKeymapPreset.remaps == ["W=up", "A=left", "S=down", "D=right"], "keymap preset lookup")
    let capsPresetRemaps = try keymapPresetRemaps(try keymapPreset(named: "caps-esc"))
    try assertSelfTest(capsPresetRemaps.count == 1 && capsPresetRemaps[0].source.name == "Caps", "keymap preset remap parsing")
    let editingPresetRemaps = try keymapPresetRemaps(try keymapPreset(named: "editing-shortcuts"))
    try assertSelfTest(editingPresetRemaps.count == 4 && editingPresetRemaps[0].targetUsage == 0x06 && editingPresetRemaps[0].modifierUsage == 0xE0, "editing shortcut preset parsing")
    let editingPresetTable = try keymapRemapTable(editingPresetRemaps)
    let pageUpKey = try keyByArgument("page up")
    let pageUpOffset = pageUpKey.keyIndex * 4
    try assertSelfTest(Array(editingPresetTable[pageUpOffset..<(pageUpOffset + 4)]) == [0x02, 0x01, 0x06, 0x00], "editing shortcut modifier encoding")
    let editingPresetRecords = try keymapRecordJSON(keymapFeatureSequence(table: editingPresetTable))
    try assertSelfTest(editingPresetRecords.contains { $0.spec == "pageup=C:control" }, "keymap JSON spec decoding")
    let functionRowRemaps = try keymapPresetRemaps(try keymapPreset(named: "function-row"))
    try assertSelfTest(functionRowRemaps.count == 12 && functionRowRemaps[0].targetUsage == 0x3A && functionRowRemaps[11].targetUsage == 0x45, "function-row preset parsing")
    try expectInvalidArgument("unknown keymap preset") {
        _ = try keymapPreset(named: "unknown")
    }
    let keymapProfileOptions = try parseKeymapProfileCreateOptions([
        "wasd.gmk67-keymap.json",
        "--name=WASD Arrows",
        "W=up",
        "A=left",
        "S=down",
        "D=right"
    ])
    try assertSelfTest(keymapProfileOptions.profile.name == "WASD Arrows" && keymapProfileOptions.profile.remaps.count == 4, "keymap profile create option parsing")
    let keymapProfilePath = tempDirectory.appendingPathComponent("wasd.gmk67-keymap.json").path
    try writeKeymapProfile(keymapProfileOptions.profile, path: keymapProfilePath)
    let loadedKeymapProfile = try readKeymapProfile(keymapProfilePath)
    try assertSelfTest(loadedKeymapProfile.remaps == ["W=up", "A=left", "S=down", "D=right"], "keymap profile round trip")
    let keymapProfileSequencePath = tempDirectory.appendingPathComponent("wasd-keymap.hex").path
    try writeKeymapProfileSequence(loadedKeymapProfile, path: keymapProfileSequencePath)
    let loadedKeymapProfileSequence = try validateKeymapFeatureSequenceFile(keymapProfileSequencePath, printSummary: false)
    try assertSelfTest(loadedKeymapProfileSequence.count == 13, "keymap profile export sequence")
    let keymapLibraryDirectory = tempDirectory.appendingPathComponent("keymaps", isDirectory: true)
    _ = try saveKeymapToLibrary(loadedKeymapProfile, slot: "wasd", directory: keymapLibraryDirectory)
    let keymapLibraryItems = try keymapLibraryListItems(directory: keymapLibraryDirectory)
    try assertSelfTest(keymapLibraryItems.count == 1 && keymapLibraryItems[0].remapCount == 4, "keymap library listing")
    let loadedLibraryKeymap = try readKeymapFromLibrary(slot: "wasd", directory: keymapLibraryDirectory)
    try assertSelfTest(loadedLibraryKeymap.name == "WASD Arrows", "keymap library read")
    let keymapLibraryBundlePath = tempDirectory.appendingPathComponent("keymaps-bundle.json").path
    let keymapLibraryBundle = try writeKeymapLibraryBundle(directory: keymapLibraryDirectory, path: keymapLibraryBundlePath)
    try assertSelfTest(keymapLibraryBundle.profiles.map(\.slot) == ["wasd"], "keymap library bundle export")
    let importedKeymapLibraryDirectory = tempDirectory.appendingPathComponent("imported-keymaps", isDirectory: true)
    let importedKeymapSlots = try importKeymapLibraryBundle(keymapLibraryBundlePath, directory: importedKeymapLibraryDirectory)
    try assertSelfTest(importedKeymapSlots == ["wasd"], "keymap library bundle import slots")
    let importedKeymapItems = try keymapLibraryListItems(directory: importedKeymapLibraryDirectory)
    try assertSelfTest(importedKeymapItems.count == 1 && importedKeymapItems[0].slot == "wasd", "keymap library bundle import list")
    try expectInvalidArgument("keymap library duplicate slot guard") {
        let duplicateBundle = KeymapLibraryBundle(
            format: "gmk67-keymap-library",
            version: 1,
            exportedAt: "test",
            profiles: [
                KeymapLibraryBundleEntry(slot: "dup", profile: loadedKeymapProfile),
                KeymapLibraryBundleEntry(slot: "dup", profile: loadedLibraryKeymap)
            ]
        )
        let encoder = JSONEncoder()
        let duplicatePath = tempDirectory.appendingPathComponent("duplicate-keymap-bundle.json")
        try encoder.encode(duplicateBundle).write(to: duplicatePath)
        _ = try readKeymapLibraryBundle(duplicatePath.path)
    }
    let macroOptions = try parseMacroCreateOptions([
        "combo.gmk67-macro.json",
        "--name=Combo",
        "--repeat=2",
        "down:control",
        "key:C",
        "up:control",
        "delay:50",
        "text:ok"
    ])
    try assertSelfTest(macroOptions.macro.name == "Combo" && macroOptions.macro.repeatCount == 2, "macro create option parsing")
    try assertSelfTest(macroOptions.macro.events.count == 5 && macroOptions.macro.events[1].usage == "0x06", "macro event parsing")
    let spacedTextMacro = try parseMacroCreateOptions(["text.json", "--event=text:hello world"])
    try assertSelfTest(spacedTextMacro.macro.events.first?.text == "hello world", "macro text with spaces")
    let macroPath = tempDirectory.appendingPathComponent("combo.gmk67-macro.json").path
    try writeMacroProfile(macroOptions.macro, path: macroPath)
    let loadedMacro = try readMacroProfile(macroPath)
    try assertSelfTest(loadedMacro.events.last?.text == "ok", "macro profile round trip")
    let macroLibraryDirectory = tempDirectory.appendingPathComponent("macros", isDirectory: true)
    _ = try saveMacroToLibrary(loadedMacro, slot: "combo", directory: macroLibraryDirectory)
    let macroLibraryItems = try macroLibraryListItems(directory: macroLibraryDirectory)
    try assertSelfTest(macroLibraryItems.count == 1 && macroLibraryItems[0].eventCount == 5, "macro library listing")
    let loadedLibraryMacro = try readMacroFromLibrary(slot: "combo", directory: macroLibraryDirectory)
    try assertSelfTest(loadedLibraryMacro.repeatCount == 2, "macro library read")
    let macroLibraryBundlePath = tempDirectory.appendingPathComponent("macros-bundle.json").path
    let macroLibraryBundle = try writeMacroLibraryBundle(directory: macroLibraryDirectory, path: macroLibraryBundlePath)
    try assertSelfTest(macroLibraryBundle.macros.map(\.slot) == ["combo"], "macro library bundle export")
    let importedMacroLibraryDirectory = tempDirectory.appendingPathComponent("imported-macros", isDirectory: true)
    let importedMacroSlots = try importMacroLibraryBundle(macroLibraryBundlePath, directory: importedMacroLibraryDirectory)
    try assertSelfTest(importedMacroSlots == ["combo"], "macro library bundle import slots")
    let importedMacroItems = try macroLibraryListItems(directory: importedMacroLibraryDirectory)
    try assertSelfTest(importedMacroItems.count == 1 && importedMacroItems[0].slot == "combo", "macro library bundle import list")
    try expectInvalidArgument("macro library duplicate slot guard") {
        let duplicateBundle = MacroLibraryBundle(
            format: "gmk67-macro-library",
            version: 1,
            exportedAt: "test",
            macros: [
                MacroLibraryBundleEntry(slot: "dup", macro: loadedMacro),
                MacroLibraryBundleEntry(slot: "dup", macro: loadedLibraryMacro)
            ]
        )
        let encoder = JSONEncoder()
        let duplicatePath = tempDirectory.appendingPathComponent("duplicate-macro-bundle.json")
        try encoder.encode(duplicateBundle).write(to: duplicatePath)
        _ = try readMacroLibraryBundle(duplicatePath.path)
    }
    try expectInvalidArgument("macro bad delay") {
        _ = try parseMacroCreateOptions(["bad.json", "delay:70000"])
    }
    try expectInvalidArgument("macro empty") {
        _ = try parseMacroCreateOptions(["empty.json"])
    }

    let combinedProfileOptions = try parseProfileCreateOptions([
        "combined.gmk67-profile.json",
        "--name=Gaming",
        "--rgb=wasd",
        "--keymap=none",
        "--rgb-fill=000000",
        "--remap=W=up",
        "W=FF0000"
    ])
    let combinedProfile = combinedProfileOptions.profile
    let combinedProfilePath = tempDirectory.appendingPathComponent("combined.gmk67-profile.json").path
    try writeCombinedProfile(combinedProfile, path: combinedProfilePath)
    let loadedCombinedProfile = try readCombinedProfile(combinedProfilePath)
    try assertSelfTest(
        loadedCombinedProfile.name == "Gaming" &&
            loadedCombinedProfile.rgbPreset == "wasd" &&
            loadedCombinedProfile.keymapPreset == nil &&
            loadedCombinedProfile.rgbFill == "000000" &&
            loadedCombinedProfile.rgbAssignments == ["W=FF0000"] &&
            loadedCombinedProfile.keymapRemaps == ["W=up"],
        "combined profile round trip"
    )
    let combinedProfileFrames = try combinedProfileRGBFrames(loadedCombinedProfile)
    try assertSelfTest(Array(combinedProfileFrames[2][28..<32]) == [0x27, 0xFF, 0x00, 0x00], "combined custom profile RGB assignment")
    let combinedProfileRemaps = try combinedProfileKeymapRemaps(loadedCombinedProfile)
    try assertSelfTest(combinedProfileRemaps.count == 1 && combinedProfileRemaps[0].source.name == "W", "combined custom profile remap")
    let profileArtifactPrefix = tempDirectory.appendingPathComponent("combined-artifacts").path
    let exportedProfileArtifacts = try exportCombinedProfileArtifacts(loadedCombinedProfile, prefix: profileArtifactPrefix)
    let exportedRGBFrames = try readRGBFramesFile(exportedProfileArtifacts.rgbPath)
    try assertSelfTest(Array(exportedRGBFrames[2][28..<32]) == [0x27, 0xFF, 0x00, 0x00], "combined profile RGB artifact export")
    guard let exportedKeymapPath = exportedProfileArtifacts.keymapPath else {
        throw DriverError.invalidArgument("Self-test failed: expected combined profile keymap artifact")
    }
    let exportedKeymapSequence = try validateKeymapFeatureSequenceFile(exportedKeymapPath, printSummary: false)
    try assertSelfTest(exportedKeymapSequence.count == 13, "combined profile keymap artifact export")
    let inlineArtifactPrefix = tempDirectory.appendingPathComponent("inline-artifacts").path
    let inlineExportedArtifacts = try exportCombinedProfileArtifacts(combinedProfileOptions.profile, prefix: inlineArtifactPrefix)
    try assertSelfTest(
        FileManager.default.fileExists(atPath: inlineExportedArtifacts.rgbPath) &&
            inlineExportedArtifacts.keymapPath.map { FileManager.default.fileExists(atPath: $0) } == true,
        "inline combined profile artifact export"
    )
    let applyProfileOptions = try parseProfileApplyOptions([combinedProfilePath, unsafeKeymapFlag, "--write-index=2", "--read-index=3"])
    try assertSelfTest(applyProfileOptions.path == combinedProfilePath && applyProfileOptions.hasUnsafeFlag && applyProfileOptions.writeIndex == 2 && applyProfileOptions.readIndex == 3, "combined profile apply options")
    try expectInvalidArgument("combined profile invalid preset") {
        try validateCombinedProfile(CombinedProfile(format: "gmk67-profile", version: 1, name: "bad", rgbPreset: "unknown", keymapPreset: nil))
    }
    let gamingProfilePreset = try combinedProfilePreset(named: "gaming")
    let gamingProfile = try makeCombinedProfile(from: gamingProfilePreset)
    try assertSelfTest(gamingProfile.name == "Gaming" && gamingProfile.rgbPreset == "wasd" && gamingProfile.keymapPreset == "gaming-layer", "combined profile preset lookup")
    let editableGamingProfile = try makeEditableCombinedProfile(from: gamingProfilePreset)
    try assertSelfTest(
        editableGamingProfile.rgbFill == "101018" &&
            editableGamingProfile.rgbAssignments?.contains("W=FF3B30") == true &&
            editableGamingProfile.keymapPreset == nil &&
            editableGamingProfile.keymapRemaps?.contains("Caps=esc") == true,
        "combined profile preset editor expansion"
    )
    let presetApplyOptions = try parseProfilePresetApplyOptions(["gaming", unsafeKeymapFlag, "--write-index=1", "--read-index=2"])
    try assertSelfTest(presetApplyOptions.name == "gaming" && presetApplyOptions.hasUnsafeFlag && presetApplyOptions.writeIndex == 1 && presetApplyOptions.readIndex == 2, "combined profile preset apply options")
    try expectInvalidArgument("unknown combined profile preset") {
        _ = try combinedProfilePreset(named: "unknown")
    }
    let profileLibraryDirectory = tempDirectory.appendingPathComponent("profiles", isDirectory: true)
    _ = try saveProfileToLibrary(loadedCombinedProfile, slot: "gaming", directory: profileLibraryDirectory)
    _ = try saveProfileToLibrary(gamingProfile, slot: "preset gaming", directory: profileLibraryDirectory)
    let libraryBundlePath = tempDirectory.appendingPathComponent("profiles-bundle.json").path
    let libraryBundle = try writeProfileLibraryBundle(directory: profileLibraryDirectory, path: libraryBundlePath)
    try assertSelfTest(libraryBundle.profiles.map(\.slot) == ["gaming", "preset-gaming"], "profile library bundle export")
    let importedProfileLibraryDirectory = tempDirectory.appendingPathComponent("imported-profiles", isDirectory: true)
    let importedProfileSlots = try importProfileLibraryBundle(libraryBundlePath, directory: importedProfileLibraryDirectory)
    try assertSelfTest(importedProfileSlots == ["gaming", "preset-gaming"], "profile library bundle import slots")
    let importedProfileItems = try profileLibraryListItems(directory: importedProfileLibraryDirectory)
    try assertSelfTest(importedProfileItems.count == 2 && importedProfileItems[0].slot == "gaming", "profile library bundle import list")
    try expectInvalidArgument("profile library duplicate slot guard") {
        let duplicateBundle = ProfileLibraryBundle(
            format: "gmk67-profile-library",
            version: 1,
            exportedAt: "test",
            profiles: [
                ProfileLibraryBundleEntry(slot: "dup", profile: loadedCombinedProfile),
                ProfileLibraryBundleEntry(slot: "dup", profile: gamingProfile)
            ]
        )
        let encoder = JSONEncoder()
        let duplicatePath = tempDirectory.appendingPathComponent("duplicate-profile-bundle.json")
        try encoder.encode(duplicateBundle).write(to: duplicatePath)
        _ = try readProfileLibraryBundle(duplicatePath.path)
    }
    let appLibraryBundlePath = tempDirectory.appendingPathComponent("app-library-bundle.json").path
    let appLibraryBundle = try writeAppLibraryBundle(
        profileDirectory: profileLibraryDirectory,
        keymapDirectory: keymapLibraryDirectory,
        macroDirectory: macroLibraryDirectory,
        path: appLibraryBundlePath
    )
    try assertSelfTest(
        appLibraryBundle.profiles.count == 2 &&
            appLibraryBundle.keymaps.map(\.slot) == ["wasd"] &&
            appLibraryBundle.macros.map(\.slot) == ["combo"],
        "app library bundle export"
    )
    let importedAppProfiles = tempDirectory.appendingPathComponent("imported-app-profiles", isDirectory: true)
    let importedAppKeymaps = tempDirectory.appendingPathComponent("imported-app-keymaps", isDirectory: true)
    let importedAppMacros = tempDirectory.appendingPathComponent("imported-app-macros", isDirectory: true)
    let importedApp = try importAppLibraryBundle(
        appLibraryBundlePath,
        profileDirectory: importedAppProfiles,
        keymapDirectory: importedAppKeymaps,
        macroDirectory: importedAppMacros
    )
    try assertSelfTest(importedApp.profiles == ["gaming", "preset-gaming"], "app library bundle import profile slots")
    try assertSelfTest(importedApp.keymaps == ["wasd"] && importedApp.macros == ["combo"], "app library bundle import keymap/macro slots")
    try expectInvalidArgument("app library duplicate keymap slot guard") {
        let duplicateBundle = AppLibraryBundle(
            format: "gmk67-app-library",
            version: 1,
            exportedAt: "test",
            profiles: [],
            keymaps: [
                KeymapLibraryBundleEntry(slot: "dup", profile: loadedKeymapProfile),
                KeymapLibraryBundleEntry(slot: "dup", profile: loadedLibraryKeymap)
            ],
            macros: []
        )
        let encoder = JSONEncoder()
        let duplicatePath = tempDirectory.appendingPathComponent("duplicate-app-library-bundle.json")
        try encoder.encode(duplicateBundle).write(to: duplicatePath)
        _ = try readAppLibraryBundle(duplicatePath.path)
    }
    let resetArtifactPrefix = tempDirectory.appendingPathComponent("factory-reset").path
    let resetArtifacts = try writeFactoryResetArtifacts(prefix: resetArtifactPrefix)
    let resetRGBFrames = try readRGBFramesFile(resetArtifacts.rgbPath)
    try assertSelfTest(rgbFramesToRecords(resetRGBFrames).values.allSatisfy { $0.red == 0 && $0.green == 0 && $0.blue == 0 }, "factory reset RGB artifact")
    let resetKeymapSequence = try validateKeymapFeatureSequenceFile(resetArtifacts.keymapPath, printSummary: false)
    try assertSelfTest(resetKeymapSequence == factoryResetKeymapSequence(), "factory reset keymap artifact")
    let resetOptions = try parseUnsafeFactoryResetOptions([unsafeKeymapFlag, "--write-index=2", "--read-index=3"])
    try assertSelfTest(resetOptions.writeIndex == 2 && resetOptions.readIndex == 3, "factory reset options")
    try expectInvalidArgument("factory reset unsafe guard") {
        _ = try parseUnsafeFactoryResetOptions([])
    }

    let remaps = try parseKeymapRemapSpecs(["W=up", "A=left", "S=down", "D=right"])
    let keymapTable = try keymapRemapTable(remaps)
    try assertSelfTest(Array(keymapTable[0x09C..<0x0A0]) == [0x02, 0x00, 0x52, 0x00], "W keymap record")
    try assertSelfTest(Array(keymapTable[0x0E0..<0x0EC]) == [
        0x02, 0x00, 0x50, 0x00,
        0x02, 0x00, 0x51, 0x00,
        0x02, 0x00, 0x4F, 0x00
    ], "A/S/D keymap records")
    try expectInvalidArgument("duplicate keymap source") {
        _ = try keymapRemapTable(try parseKeymapRemapSpecs(["A=B", "A=C"]))
    }

    let keymapSequence = keymapFeatureSequence(table: keymapTable)
    try assertSelfTest(keymapSequence.count == 13, "keymap sequence report count")
    try assertSelfTest(Array(keymapSequence[0].prefix(2)) == [0x04, 0x18], "keymap begin report")
    try assertSelfTest(Array(keymapSequence[1].prefix(2)) == [0x04, 0x11] && keymapSequence[1][8] == 0x09, "keymap selector report")
    try assertSelfTest(Array(keymapSequence[10][62..<64]) == [0xAA, 0x55], "keymap marker")
    try assertSelfTest(Array(keymapSequence[11].prefix(2)) == [0x04, 0x02], "keymap commit report")
    try assertSelfTest(Array(keymapSequence[12].prefix(2)) == [0x04, 0xF0], "keymap finish report")

    let keymapPath = tempDirectory.appendingPathComponent("keymap.hex").path
    try writeFeatureSequenceFile(keymapSequence, path: keymapPath)
    let validatedKeymapSequence = try validateKeymapFeatureSequenceFile(keymapPath, printSummary: verbose)
    try assertSelfTest(validatedKeymapSequence == keymapSequence, "keymap validation returns original sequence")
    let fileOptions = try parseUnsafeKeymapFileOptions([keymapPath, unsafeKeymapFlag, "--write-index=2"])
    try assertSelfTest(fileOptions.path == keymapPath && fileOptions.writeIndex == 2, "keymap file apply option parsing")
    try expectInvalidArgument("keymap file apply unsafe guard") {
        _ = try parseUnsafeKeymapFileOptions([keymapPath])
    }
    try expectInvalidArgument("candidate file apply unsafe guard") {
        _ = try parseUnsafeCandidateFileOptions([keymapPath], kind: "candidate test")
    }
    let candidateFileOptions = try parseUnsafeCandidateFileOptions([keymapPath, unsafeKeymapFlag, "--write-index=3"], kind: "candidate test")
    try assertSelfTest(candidateFileOptions.path == keymapPath && candidateFileOptions.writeIndex == 3, "candidate file apply option parsing")
    try expectInvalidArgument("keymap file rejected as RGB table") {
        _ = try readRGBFramesFile(keymapPath)
    }

    let lightingTable = try customLightingRGBTable(assignments: profileAssignments)
    try assertSelfTest(lightingTable.count == 0x280, "custom lighting RGB table length")
    try assertSelfTest(Array(lightingTable[0x09C..<0x0A0]) == [0x27, 0xFF, 0x00, 0x00], "custom lighting W RGB record")
    try assertSelfTest(Array(lightingTable[0x23E..<0x240]) == [0xAA, 0x55], "custom lighting marker")
    let lightingSequence = customLightingRGBFeatureSequence(table: lightingTable)
    try assertSelfTest(lightingSequence.count == 13, "custom lighting sequence report count")
    try assertSelfTest(Array(lightingSequence[0].prefix(2)) == [0x04, 0x18], "custom lighting begin report")
    try assertSelfTest(Array(lightingSequence[1].prefix(2)) == [0x04, 0x23] && lightingSequence[1][8] == 0x09, "custom lighting selector report")
    try assertSelfTest(Array(lightingSequence[10][62..<64]) == [0xAA, 0x55], "custom lighting sequence marker")
    try assertSelfTest(Array(lightingSequence[11].prefix(2)) == [0x04, 0x02], "custom lighting commit report")
    try assertSelfTest(Array(lightingSequence[12].prefix(2)) == [0x04, 0xF0], "custom lighting finish report")
    let lightingPath = tempDirectory.appendingPathComponent("custom-lighting.hex").path
    try writeFeatureSequenceFile(lightingSequence, path: lightingPath)
    let validatedLightingSequence = try validateCustomLightingRGBFeatureSequenceFile(lightingPath, printSummary: verbose)
    try assertSelfTest(validatedLightingSequence == lightingSequence, "custom lighting validation returns original sequence")
    let customLightingJSONRecords = rgbRecordJSON(Array(validatedLightingSequence[2...10]), keyByLightIndex: keyMapByLightIndex(), recordByteLimit: 0x23E)
    try assertSelfTest(customLightingJSONRecords.first?.rgb == "FF0000", "custom lighting JSON records")

    let lightingModeAssignments = try parseByteAssignmentSpecs(["W=01", "A=02", "0x39=03"])
    try assertSelfTest(lightingModeAssignments.map(\.index) == [0x27, 0x38, 0x39], "lighting mode assignment parsing")
    let lightingModeTableBytes = try lightingModeTable(assignments: lightingModeAssignments)
    try assertSelfTest(lightingModeTableBytes.count == 0x100, "lighting mode table length")
    try assertSelfTest(lightingModeTableBytes[0x27] == 0x01, "lighting mode W byte")
    try assertSelfTest(Array(lightingModeTableBytes[0xBE..<0xC0]) == [0xAA, 0x55], "lighting mode marker")
    let lightingModeSequence = lightingModeFeatureSequence(table: lightingModeTableBytes)
    try assertSelfTest(lightingModeSequence.count == 7, "lighting mode sequence report count")
    try assertSelfTest(Array(lightingModeSequence[0].prefix(2)) == [0x04, 0x18], "lighting mode begin report")
    try assertSelfTest(Array(lightingModeSequence[1].prefix(2)) == [0x04, 0x23] && lightingModeSequence[1][8] == 0x03, "lighting mode selector report")
    try assertSelfTest(Array(lightingModeSequence[4][62..<64]) == [0xAA, 0x55], "lighting mode sequence marker")
    try assertSelfTest(Array(lightingModeSequence[5].prefix(2)) == [0x04, 0x02], "lighting mode commit report")
    try assertSelfTest(Array(lightingModeSequence[6].prefix(2)) == [0x04, 0xF0], "lighting mode finish report")
    let lightingModePath = tempDirectory.appendingPathComponent("lighting-mode.hex").path
    try writeFeatureSequenceFile(lightingModeSequence, path: lightingModePath)
    let validatedLightingModeSequence = try validateLightingModeFeatureSequenceFile(lightingModePath, printSummary: verbose)
    try assertSelfTest(validatedLightingModeSequence == lightingModeSequence, "lighting mode validation returns original sequence")
    let lightingModeJSONRecords = byteRecordJSON(Array(validatedLightingModeSequence[2...4]), byteLimit: 0xBE, keyByLightIndex: keyMapByLightIndex())
    try assertSelfTest(lightingModeJSONRecords.contains { $0.spec == "W=01" }, "lighting mode JSON records")
    let lightingModePreset = try lightingModePreset(named: "wasd-steps")
    let lightingModePresetAssignments = try lightingModePresetAssignments(lightingModePreset)
    try assertSelfTest(lightingModePresetAssignments.count == 8 && lightingModePresetAssignments[0].index == 0x27, "lighting mode preset parsing")
    let lightingModePresetSequence = lightingModeFeatureSequence(table: try lightingModeTable(assignments: lightingModePresetAssignments))
    try assertSelfTest(lightingModePresetSequence.count == 7 && lightingModePresetSequence[1][8] == 0x03, "lighting mode preset sequence")
    let lightingModePresetApplyOptions = try parseUnsafeCandidateNameOptions(["wasd-steps", unsafeKeymapFlag, "--write-index=4"], kind: "lighting-mode preset")
    try assertSelfTest(lightingModePresetApplyOptions.name == "wasd-steps" && lightingModePresetApplyOptions.writeIndex == 4, "lighting mode preset apply options")
    try expectInvalidArgument("lighting mode preset unsafe guard") {
        _ = try parseUnsafeCandidateNameOptions(["wasd-steps"], kind: "lighting-mode preset")
    }
    let breathEffect = try lightingEffect(named: "breath")
    try assertSelfTest(breathEffect.value == 0x06, "lighting effect lookup")
    let breathEffectAssignments = lightingEffectAssignments(breathEffect)
    try assertSelfTest(
        breathEffectAssignments.count == physicalKeysByLightIndex().count &&
            breathEffectAssignments.first { $0.label == "W" }?.value == 0x06,
        "lighting effect assignments"
    )
    let breathEffectTable = try lightingModeTable(assignments: breathEffectAssignments)
    try assertSelfTest(breathEffectTable[0x27] == 0x06 && breathEffectTable[0x38] == 0x06, "lighting effect table")
    let breathEffectPath = tempDirectory.appendingPathComponent("breath-effect.hex").path
    try writeFeatureSequenceFile(lightingModeFeatureSequence(table: breathEffectTable), path: breathEffectPath)
    let validatedBreathEffect = try validateLightingModeFeatureSequenceFile(breathEffectPath, printSummary: false)
    try assertSelfTest(validatedBreathEffect.count == 7, "lighting effect artifact validation")
    let breathEffectJSON = byteRecordJSON(Array(validatedBreathEffect[2...4]), byteLimit: 0xBE, keyByLightIndex: keyMapByLightIndex())
    let breathEffectSpecs = Set(breathEffectJSON.compactMap(\.spec))
    try assertSelfTest(
        breathEffectSpecs.contains("equal=06") &&
            breathEffectSpecs.contains("pageup=06") &&
            breathEffectSpecs.contains("left=06") &&
            breathEffectSpecs.contains("0x49=06"),
        "lighting effect parseable JSON specs"
    )
    try expectInvalidArgument("lighting effect unsafe guard") {
        _ = try parseUnsafeCandidateNameOptions(["breath"], kind: "lighting effect")
    }

    let alternateFullTableSequence = alternateFullTableFeatureSequence(table: keymapTable)
    try assertSelfTest(alternateFullTableSequence.count == 13, "alternate full-table sequence report count")
    try assertSelfTest(Array(alternateFullTableSequence[0].prefix(2)) == [0x04, 0x18], "alternate full-table begin report")
    try assertSelfTest(Array(alternateFullTableSequence[1].prefix(2)) == [0x04, 0x27] && alternateFullTableSequence[1][8] == 0x09, "alternate full-table selector report")
    try assertSelfTest(Array(alternateFullTableSequence[10][62..<64]) == [0xAA, 0x55], "alternate full-table sequence marker")
    try assertSelfTest(Array(alternateFullTableSequence[11].prefix(2)) == [0x04, 0x02], "alternate full-table commit report")
    try assertSelfTest(Array(alternateFullTableSequence[12].prefix(2)) == [0x04, 0xF0], "alternate full-table finish report")
    let alternateFullTablePath = tempDirectory.appendingPathComponent("alternate-full-table.hex").path
    try writeFeatureSequenceFile(alternateFullTableSequence, path: alternateFullTablePath)
    let validatedAlternateFullTableSequence = try validateAlternateFullTableFeatureSequenceFile(alternateFullTablePath, printSummary: verbose)
    try assertSelfTest(validatedAlternateFullTableSequence == alternateFullTableSequence, "alternate full-table validation returns original sequence")
    let alternateFullTableJSONRecords = try keymapRecordJSON(validatedAlternateFullTableSequence)
    try assertSelfTest(alternateFullTableJSONRecords.contains { $0.spec == "W=up" }, "alternate full-table JSON records")

    if verbose {
        print("Offline self-test passed.")
    }
}

private func runDoctor(openCheck: Bool) throws {
    print("GMK67 driver doctor")

    let keys = try loadKeyboardLayout()
    let physicalKeyCount = physicalKeysByLightIndex().count
    print("Layout: OK (\(keys.count) layout keys, \(physicalKeyCount) mapped physical RGB keys)")

    try runSelfTest(verbose: false)
    print("Offline protocol checks: OK")

    let driver = HIDDriver()
    let devices = driver.devices()
    if devices.isEmpty {
        print(String(format: "USB scan: no devices found for VID:PID %04X:%04X", GMK67.vendorID, GMK67.productID))
        print("Connect the keyboard over USB in wired mode, then retry.")
        return
    }

    print(String(format: "USB scan: found %d matching interface(s) for VID:PID %04X:%04X", devices.count, GMK67.vendorID, GMK67.productID))
    printDevices(devices)

    let likelyScanIndices = devices.enumerated()
        .filter { $0.element.isLikelyConfigurationInterface }
        .map(\.offset)
    if likelyScanIndices.isEmpty {
        print("Likely configuration interfaces: none")
        return
    }

    print("Likely configuration scan indices: \(likelyScanIndices.map(String.init).joined(separator: ", "))")
    if let preferredIndex = likelyScanIndices.first {
        print("Default read/write scan index: \(preferredIndex)")

        guard openCheck else {
            print("Open check: skipped (pass --open-check to test macOS HID permission without sending reports)")
            return
        }

        do {
            _ = try driver.device(at: preferredIndex, configurationOnly: false)
            print("Open check: OK on scan index \(preferredIndex)")
        } catch {
            print("Open check: \(error)")
        }
    }
}

private func readinessReport(openCheck: Bool) -> String {
    var lines: [String] = []
    func add(_ line: String = "") {
        lines.append(line)
    }

    add("GMK67 driver readiness")
    add("No HID reports are sent by this command.")
    add("")

    var hardFailures: [String] = []
    var warnings: [String] = []

    do {
        let keys = try loadKeyboardLayout()
        let physicalKeyCount = physicalKeysByLightIndex().count
        add("Resources: OK")
        add("  layout keys: \(keys.count)")
        add("  mapped physical RGB keys: \(physicalKeyCount)")
    } catch {
        add("Resources: FAIL")
        add("  \(error)")
        hardFailures.append("vendor layout resources are unavailable")
    }

    do {
        try runSelfTest(verbose: false)
        add("Offline encoders: OK")
        add("  RGB tables, profiles, keymap sequences, and candidate lighting artifacts validate locally.")
    } catch {
        add("Offline encoders: FAIL")
        add("  \(error)")
        hardFailures.append("offline protocol encoders failed self-test")
    }

    let driver = HIDDriver()
    let devices = driver.devices()
    if devices.isEmpty {
        add("USB device: NOT FOUND")
        add(String(format: "  target VID:PID %04X:%04X", GMK67.vendorID, GMK67.productID))
        warnings.append("keyboard is not currently visible over wired USB")
    } else {
        add("USB device: OK")
        add(String(format: "  found %d matching HID interface(s)", devices.count))
        for (index, info) in devices.enumerated() {
            let marker = info.isLikelyConfigurationInterface ? "config" : "hid"
            add(String(
                format: "  [%d] %@ feature=%d input=%d output=%d primary=%04X:%04X usage=%04X:%04X",
                index,
                marker,
                info.maxFeatureReportSize,
                info.maxInputReportSize,
                info.maxOutputReportSize,
                info.primaryUsagePage,
                info.primaryUsage,
                info.usagePage,
                info.usage
            ))
        }

        let likelyIndices = devices.enumerated()
            .filter { $0.element.isLikelyConfigurationInterface }
            .map(\.offset)
        if likelyIndices.isEmpty {
            add("Configuration interface: NOT IDENTIFIED")
            warnings.append("no likely 64-byte/vendor configuration interface was detected")
        } else {
            add("Configuration interface: OK")
            add("  likely scan index: \(likelyIndices.map(String.init).joined(separator: ", "))")
        }

        if openCheck {
            if let index = likelyIndices.first {
                do {
                    _ = try driver.device(at: index, configurationOnly: false)
                    add("macOS HID open permission: OK")
                    add("  opened scan index \(index)")
                } catch {
                    add("macOS HID open permission: FAIL")
                    add("  \(error)")
                    warnings.append("macOS may need Input Monitoring permission for the terminal/app")
                }
            } else {
                add("macOS HID open permission: SKIPPED")
                add("  no likely configuration interface to open")
            }
        } else {
            add("macOS HID open permission: SKIPPED")
            add("  pass --open-check to test opening the interface without sending reports")
        }
    }

    add("")
    add("Capability status:")
    add("  RGB readback/write: implemented with automatic RGB backups.")
    add("  RGB profiles/presets/custom maps: implemented.")
    add("  Combined profile preview/export: implemented offline.")
    add("  Key remap encoding/presets/custom profiles: implemented, live writes guarded by \(unsafeKeymapFlag).")
    add("  Candidate lighting/custom-table operations: export/validate implemented, live writes guarded.")
    add("  Keymap readback/backup: not proven yet.")

    add("")
    if hardFailures.isEmpty && warnings.isEmpty {
        if openCheck {
            add("Overall: READY")
            add("  The driver resources, offline encoders, USB device, and permission check are all OK.")
        } else {
            add("Overall: READY (OPEN CHECK SKIPPED)")
            add("  The driver resources, offline encoders, and USB device discovery are OK.")
            add("  Run readiness --open-check before live RGB/keymap writes to confirm macOS HID permission.")
        }
    } else if hardFailures.isEmpty {
        add("Overall: PARTIAL")
        for warning in warnings {
            add("  warning: \(warning)")
        }
    } else {
        add("Overall: NOT READY")
        for failure in hardFailures {
            add("  failure: \(failure)")
        }
        for warning in warnings {
            add("  warning: \(warning)")
        }
    }

    return lines.joined(separator: "\n") + "\n"
}

private func printProtocolCandidates() {
    print(protocolCandidatesText())
}

private func protocolCandidatesText() -> String {
    """
    GMK67 protocol candidates from DeviceDriver.exe

    Proven:
      RGB readback
        request: 04 F5, byte8 = 03 or 09
        read:    input report 00, 64-byte chunks
      RGB table write
        begin:   04 20, byte8 = 08 on tested USB board
        table:   first eight 64-byte RGB frames
        commit:  04 02

    Candidate, guarded or read-only only:
      Keymap/custom-key table
        begin:   04 18
        select:  04 11, byte8 = 09
        table:   nine 64-byte reports; AA 55 marker at table offset 0x23E
        commit:  04 02
        finish:  04 F0
        status:  implemented behind --unsafe-no-backup; no safe readback/backup yet

      Short lighting/profile operation
        begin:   04 18
        select:  04 13, byte8 = 01
        payload: one 64-byte report; observed AA 55 marker inside payload
        commit:  04 02
        finish:  04 F0
        status:  not implemented as a live command

      Custom lighting mode table
        begin:   04 18
        select:  04 23, byte8 = 03 or 09 depending on board mode
        table:   selector 03 declares 0x100 bytes; AA 55 marker at table offset 0xBE
        commit:  04 02
        finish:  04 F0
        status:  selector 03 export/validate and Windows-named effect artifacts implemented; live writes guarded

      Alternate full-table operation
        begin:   04 18
        select:  04 27, byte8 = 09
        table:   declared length 0x2AC; nine visible chunks; AA 55 at 0x23E
        commit:  04 02
        finish:  04 F0
        status:  export/validate implemented offline; no live command

    Use raw feature-set commands only for deliberate probes. The unproven candidates
    may overwrite profiles or lighting state and should stay offline until a readback
    or restore path is known.
    """
}

private func validationPlanText() -> String {
    """
    GMK67 physical validation plan

    Purpose:
      Run these steps from a terminal/app that has macOS Input Monitoring permission.
      The plan itself is read-only and does not open HID or send reports.

    1. Confirm access
      .build/debug/gmk67 readiness --open-check

      Expected evidence:
        macOS HID open permission: OK
        Overall: READY

    2. Capture baseline RGB
      .build/debug/gmk67 rgb-save baseline-rgb.hex
      .build/debug/gmk67 rgb-dump 0 0 9

      Expected evidence:
        A valid 9-frame RGB file is saved.
        rgb-dump prints current per-key records.

    3. Prove RGB write/restore path
      .build/debug/gmk67 rgb-set-key W FF0000
      .build/debug/gmk67 rgb-set-key W 00FF00
      .build/debug/gmk67 rgb-restore baseline-rgb.hex

      Expected evidence:
        W changes color for each write.
        Restore returns the board to the baseline RGB state.
        Automatic .gmk67-rgb-backup-*.hex files are created.

    4. Prove custom keymap candidate only with explicit consent
      .build/debug/gmk67 keymap-map-dry-run Caps=esc
      .build/debug/gmk67 keymap-map-export caps-esc.hex Caps=esc
      .build/debug/gmk67 keymap-sequence-validate caps-esc.hex
      .build/debug/gmk67 keymap-file-apply caps-esc.hex --unsafe-no-backup
      .build/debug/gmk67 keymap-clear --unsafe-no-backup

      Expected evidence:
        Caps sends Escape after apply.
        Caps returns to its original behavior after keymap-clear.
        If either condition fails, do not continue keymap testing.

    5. Test candidate lighting tables only after RGB/keymap rollback is proven
      .build/debug/gmk67 lighting-mode-preset-export wasd-steps.hex wasd-steps
      .build/debug/gmk67 lighting-mode-validate wasd-steps.hex
      .build/debug/gmk67 lighting-mode-preset-apply wasd-steps --unsafe-no-backup
      .build/debug/gmk67 rgb-restore baseline-rgb.hex

      Expected evidence:
        The board visibly changes mode/step behavior, or the command has no effect.
        Restore returns static RGB baseline. If restore does not recover lighting,
        stop candidate lighting tests and power-cycle the keyboard.

    6. Preserve evidence
      .build/debug/gmk67 diagnostics diagnostics-after-test.txt
      .build/debug/gmk67 support-bundle gmk67-support-after-test

      Keep baseline-rgb.hex, generated .hex artifacts, terminal output, and notes
      about what changed physically on the keyboard.

    Safety rules:
      Do not run guarded keymap/lighting/factory-reset commands until baseline RGB
      restore has been tested.
      Do not test multiple candidate families at once.
      Keep --unsafe-no-backup commands limited to the exact artifacts shown above
      unless you intentionally choose a broader physical test.
    """
}

private func diagnosticsReport() -> String {
    var lines: [String] = []
    func add(_ line: String = "") {
        lines.append(line)
    }

    add("GMK67 diagnostics report")
    add("Generated: \(ISO8601DateFormatter().string(from: Date()))")
    add(String(format: "Target VID:PID: %04X:%04X", GMK67.vendorID, GMK67.productID))
    add("")

    do {
        let keys = try loadKeyboardLayout()
        let physicalKeyCount = physicalKeysByLightIndex().count
        add("Layout: OK")
        add("  layout keys: \(keys.count)")
        add("  physical RGB keys: \(physicalKeyCount)")
    } catch {
        add("Layout: \(error)")
    }
    add("")

    do {
        try runSelfTest(verbose: false)
        add("Offline protocol checks: OK")
    } catch {
        add("Offline protocol checks: \(error)")
    }
    add("")

    let driver = HIDDriver()
    let devices = driver.devices()
    add(String(format: "USB scan: %d matching interface(s)", devices.count))
    if devices.isEmpty {
        add("  No matching interfaces found. Use wired USB mode.")
    } else {
        for (index, device) in devices.enumerated() {
            add(String(format: "  [%d] %@", index, device.product.isEmpty ? "(unnamed)" : device.product))
            add(String(format: "      VID:PID    %04X:%04X", device.vendorID, device.productID))
            add(String(format: "      Usage      %04X:%04X", device.usagePage, device.usage))
            add(String(format: "      Primary    %04X:%04X", device.primaryUsagePage, device.primaryUsage))
            add("      Pairs      \(formatUsagePairs(device.usagePairs))")
            add("      Maker      \(device.manufacturer.isEmpty ? "-" : device.manufacturer)")
            add("      Serial     \(device.serial.isEmpty ? "-" : device.serial)")
            add("      Reports    feature \(device.maxFeatureReportSize), input \(device.maxInputReportSize), output \(device.maxOutputReportSize) bytes max")
            add("      Config     \(device.isLikelyConfigurationInterface ? "yes" : "no")")
        }

        let likely = devices.enumerated()
            .filter { $0.element.isLikelyConfigurationInterface }
            .map(\.offset)
        add("  Likely configuration scan indices: \(likely.isEmpty ? "none" : likely.map(String.init).joined(separator: ", "))")
        if let first = likely.first {
            add("  Default read/write scan index: \(first)")
        }
    }
    add("")

    add(protocolCandidatesText())
    add("")
    add("Safety:")
    add("  This report is read-only. It does not open a keyboard interface and does not send reports.")
    add("  Commands that mutate RGB create automatic backups. Keymap writes remain guarded by \(unsafeKeymapFlag).")

    return lines.joined(separator: "\n") + "\n"
}

private func layoutReportText() throws -> String {
    let keys = try loadKeyboardLayout()
    var lines = keys.map { key in
        String(
            format: "%3d  light=%3d  hid=0x%02X  %@",
            key.keyIndex,
            key.lightIndex,
            key.code,
            key.name
        )
    }
    lines.append("")
    lines.append("\(keys.count) keys loaded")
    return lines.joined(separator: "\n") + "\n"
}

private func supportBundleSummaryText(directory: String) -> String {
    """
    GMK67 support bundle
    Generated: \(ISO8601DateFormatter().string(from: Date()))
    Directory: \(directory)

    Files:
      readiness.txt
        Concise app/driver readiness report. Does not open HID.
      diagnostics.txt
        Read-only resource, USB discovery, protocol, and safety report.
      protocol-candidates.txt
        Proven RGB commands and candidate guarded command families.
      validation-plan.txt
        Step-by-step physical validation checklist for live testing.
      layout.txt
        Vendor key index, RGB light index, HID usage, and key labels.

    No HID reports were sent while creating this bundle.
    """
}

private func defaultSupportBundlePath() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "gmk67-support-\(formatter.string(from: Date()))"
}

private func writeSupportBundle(directoryPath: String) throws {
    let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let files: [(String, String)] = [
        ("readiness.txt", readinessReport(openCheck: false)),
        ("diagnostics.txt", diagnosticsReport()),
        ("protocol-candidates.txt", protocolCandidatesText()),
        ("validation-plan.txt", validationPlanText()),
        ("layout.txt", try layoutReportText()),
        ("summary.txt", supportBundleSummaryText(directory: directoryURL.path))
    ]

    for (name, contents) in files {
        let url = directoryURL.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private func inputMonitoringPermissionReport(request: Bool) -> String {
    var lines: [String] = []
    func add(_ line: String = "") {
        lines.append(line)
    }

    add("GMK67 macOS Input Monitoring permission")
    add("No HID reports are sent by this command.")
    add("")

    let preflight = CGPreflightListenEventAccess()
    add("Current status: \(preflight ? "GRANTED" : "NOT GRANTED")")

    if request && !preflight {
        add("Requesting Input Monitoring access...")
        let granted = CGRequestListenEventAccess()
        add("Request result: \(granted ? "GRANTED" : "NOT GRANTED")")
    } else if request {
        add("Request skipped: permission is already granted.")
    }

    add("")
    add("If permission is not granted:")
    add("  1. Open System Settings > Privacy & Security > Input Monitoring.")
    add("  2. Enable the terminal/Codex host app or GMK67.app, depending on what macOS lists.")
    add("  3. Quit and reopen the app or terminal, then unplug/replug the keyboard.")
    add("")
    add("Settings URL:")
    add("  x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")

    return lines.joined(separator: "\n") + "\n"
}

private func physicalKeysByLightIndex() -> [Int: KeyItem] {
    keyMapByLightIndex().filter { index, _ in
        (0...0x8F).contains(index)
    }
}

private func keyMapByLightIndex() -> [Int: KeyItem] {
    guard let keys = try? loadKeyboardLayout() else { return [:] }
    return Dictionary(uniqueKeysWithValues: keys.map { ($0.lightIndex, $0) })
}

private func ioReturnName(_ code: IOReturn) -> String {
    switch code {
    case kIOReturnSuccess: return "success"
    case kIOReturnNotOpen: return "not open"
    case kIOReturnNotPermitted: return "not permitted"
    case kIOReturnNoDevice: return "no device"
    case kIOReturnExclusiveAccess: return "exclusive access"
    default: return String(format: "0x%08X", code)
    }
}

private func printUsage() {
    print("""
    gmk67 - macOS user-space driver tools for the Zuoya/BOYI GMK67

    Commands:
      list
          List the GMK67 vendor-defined HID configuration interface.

      scan
          List all HID interfaces with the GMK67 VID/PID.

      dump-layout
          Print the vendor key map from Resources/vendor/KeyboardLayout.xml.

      self-test
          Run offline parser, RGB table, and keymap sequence checks without HID.

      doctor [--open-check]
          Run read-only resource, protocol, and USB HID diagnostics.

      readiness [--open-check]
          Print a concise driver/app readiness report without sending HID reports.

      protocol-candidates
          Print proven and candidate vendor protocol command families without HID.

      validation-plan
          Print a read-only physical validation checklist without HID.

      diagnostics [path]
          Print or save a read-only diagnostics report without sending HID reports.

      support-bundle [directory]
          Write readiness, diagnostics, protocol, and layout reports into a support directory without sending HID reports.

      permission-status
          Check macOS Input Monitoring permission without opening HID.

      permission-request
          Request macOS Input Monitoring permission without sending HID reports.

      factory-reset-dry-run
          Preview the modeled reset artifacts without opening HID.

      factory-reset-export <output-prefix>
          Export modeled reset artifacts as <prefix>-rgb.hex and <prefix>-keymap-clear.hex.

      factory-reset \(unsafeKeymapFlag) [--write-index=N] [--read-index=N]
          Clear known physical RGB records and write an empty custom-keymap table.

      profile-create <path> [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Create a combined GMK67 profile JSON file without opening HID.

      profile-validate <path>
          Validate a combined GMK67 profile JSON file without opening HID.

      profile-preview <path>
          Render a combined profile's RGB and keymap changes without opening HID.

      profile-show <path> [--json]
          Show a combined profile, optionally as raw JSON for app editors.

      profile-preview-spec [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Preview an inline combined profile without creating a file or opening HID.

      profile-export-spec <output-prefix> [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Export inline profile artifacts without creating a profile JSON file.

      profile-apply-spec [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...] [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply an inline combined profile without creating a file. Keymap sections require \(unsafeKeymapFlag).

      profile-export <path> <output-prefix>
          Export composed profile artifacts as <prefix>-rgb.hex and optional <prefix>-keymap.hex.

      profile-apply <path> [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply a combined profile. Keymap sections require \(unsafeKeymapFlag).

      profile-preset-list
          List built-in whole-keyboard profile presets.

      profile-preset-show <preset-name> [--json|--editor-json]
          Show a built-in whole-keyboard profile preset without opening HID.
          --editor-json expands preset internals into editable RGB/remap fields.

      profile-preset-create <path> <preset-name>
          Create a combined GMK67 profile JSON file from a built-in preset.

      profile-preset-apply <preset-name> [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply a built-in whole-keyboard profile preset.

      profile-library-create [--directory=path] [--slot=name] [--name=Name] [--rgb=preset] [--keymap=preset|none] [--rgb-fill=rrggbb] [--remap=source=target[:modifier] ...] [key=rrggbb ...]
          Create or replace a named profile in the app-local profile library.

      profile-library-save <path> [--slot=name] [--directory=path]
          Validate and copy an existing profile JSON into the app-local profile library.

      profile-library-list [--directory=path] [--json]
          List saved app-local profiles.

      profile-library-preview <slot> [--directory=path]
          Preview a saved app-local profile without opening HID.

      profile-library-show <slot> [--directory=path] [--json]
          Show a saved app-local profile, optionally as raw JSON.

      profile-library-export <slot> <output-prefix> [--directory=path]
          Export saved app-local profile artifacts.

      profile-library-apply <slot> [--directory=path] [\(unsafeKeymapFlag)] [--write-index=N] [--read-index=N]
          Apply a saved app-local profile. Keymap sections require \(unsafeKeymapFlag).

      profile-library-delete <slot> [--directory=path]
          Delete a saved app-local profile.

      profile-library-bundle-export <path> [--directory=path]
          Export all saved app-local profiles to one portable JSON bundle.

      profile-library-bundle-import <path> [--directory=path]
          Validate and import a portable JSON profile library bundle.

      app-library-bundle-export <path> [--profiles=path] [--keymaps=path] [--macros=path]
          Export all app-local profile, keymap, and macro libraries to one JSON bundle.

      app-library-bundle-import <path> [--profiles=path] [--keymaps=path] [--macros=path]
          Validate and import a whole-app library bundle.

      macro-create <path> [--name=Name] [--repeat=N] <event ...>
          Create an app-local macro JSON file. Events: key:A, down:A, up:A, delay:50, text:hello.

      macro-validate <path>
          Validate a macro JSON file without opening HID.

      macro-show <path> [--json]
          Show a macro profile, optionally as raw JSON for app editors.

      macro-library-create [--directory=path] [--slot=name] [--name=Name] [--repeat=N] <event ...>
          Create or replace a named macro in the app-local macro library.

      macro-library-save <path> [--slot=name] [--directory=path]
          Validate and copy an existing macro JSON into the app-local macro library.

      macro-library-list [--directory=path] [--json]
          List saved app-local macros.

      macro-library-show <slot> [--directory=path] [--json]
          Show a saved app-local macro.

      macro-library-delete <slot> [--directory=path]
          Delete a saved app-local macro.

      macro-library-bundle-export <path> [--directory=path]
          Export all saved app-local macros to one portable JSON bundle.

      macro-library-bundle-import <path> [--directory=path]
          Validate and import a portable JSON macro library bundle.

      feature-get <report-id-hex> <length-decimal>
          Read a raw feature report from the configuration interface.

      feature-get-at <config-index> <report-id-hex> <length-decimal>
          Read a raw feature report from a listed configuration interface.

      feature-scan [config-index] [start-report-id-hex] [end-report-id-hex] [length-decimal]
          Read-only scan for feature report IDs that return successfully.

      input-listen [config-index] [length-decimal] [seconds]
          Listen for interrupt input reports from a listed configuration interface.

      key-test [config-index] [length-decimal] [seconds]
          Listen for boot keyboard input reports and decode modifiers/keys.

      input-get-at <index> <report-id-hex> <length-decimal>
          Read a raw input report from any VID/PID interface shown by scan.

      feature-set <report-id-hex> <payload-hex>
          Write a raw feature report payload to the configuration interface.

      feature-set64 <report-id-hex> <payload-hex>
          Write a feature report payload padded with zeros to exactly 64 bytes.

      rgb-read-probe [write-index] [listen-index] [chunks] [seconds]
          Send the vendor RGB readback request and print returned input reports.

      rgb-read-get-probe [write-index] [read-index] [read-report-id-hex] [length] [chunks]
          Send the vendor RGB readback request, then call IOHIDDeviceGetReport(input).

      rgb-dump [write-index] [read-index] [chunks] [--json]
          Send the RGB readback request, read all chunks, and print non-zero records.

      rgb-set-key <key-name-or-light-index-hex> <rrggbb-hex> [write-index] [read-index]
          Save a backup, set one key in the RGB table, then read back the rendered table.

      rgb-map <key=rrggbb> [...] [--write-index=N] [--read-index=N]
          Save a backup, set multiple keys in one RGB table write, then read back.

      rgb-file-map <input.hex> <output.hex> <key=rrggbb> [...]
          Edit a saved RGB table file without opening HID.

      rgb-profile-create <path> [--fill=rrggbb] [key=rrggbb ...]
          Create a fresh RGB table profile file without opening HID.

      rgb-preset-list
          List built-in RGB lighting presets.

      rgb-preset-show <preset-name> [--json]
          Show a built-in RGB lighting preset without opening HID.

      rgb-preset-create <path> <preset-name>
          Create a fresh RGB table file from a built-in preset without opening HID.

      rgb-preset-apply <preset-name> [write-index] [read-index]
          Save a backup, apply a built-in RGB preset, then read back rendered RGB.

      rgb-file-dump <path> [--json]
          Parse a saved RGB table file and print non-zero records without opening HID.

      rgb-set-all <rrggbb-hex> [write-index] [read-index]
          Save a backup, then set all physical keys from the vendor layout to one RGB color.

      rgb-clear [write-index] [read-index]
          Save a backup, then set all physical keys from the vendor layout to black/off.

      rgb-save <path> [write-index] [read-index]
          Save the current 9-frame RGB table to a hex text file.

      rgb-restore <path> [write-index] [read-index]
          Restore a saved RGB table file and read back the result.

      rgb-restore-dry-run <path>
          Validate and summarize an RGB table restore file without opening HID.

      rgb-backups [directory]
          List valid automatic RGB backup files without opening HID.

      rgb-restore-latest [--directory=path] [--write-index=N] [--read-index=N]
          Restore the newest valid automatic RGB backup file and read back the result.

      keymap-dry-run <source-key> <target-key-or-hid-hex> [modifier-key-or-hid-hex]
          Build and print the candidate simple-remap feature sequence without sending it.

      keymap-clear-dry-run
          Build and print the candidate empty custom-keymap sequence without sending it.

      keymap-export <path> <source-key> <target-key-or-hid-hex> [modifier-key-or-hid-hex]
          Write the candidate simple-remap feature sequence to a hex text file.

      keymap-clear-export <path>
          Write the candidate empty custom-keymap sequence to a hex text file.

      keymap-map-dry-run <source=target[:modifier]> [...]
          Build and print a custom-keymap table with multiple simple remaps.

      keymap-map-export <path> <source=target[:modifier]> [...]
          Write a multi-remap feature sequence to a hex text file.

      keymap-preset-list
          List built-in keymap remap presets.

      keymap-preset-show <preset-name> [--json]
          Show a built-in keymap remap preset without opening HID.

      keymap-preset-export <path> <preset-name>
          Write a built-in keymap preset sequence to a hex text file.

      keymap-preset-apply <preset-name> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a full custom-keymap table from a built-in preset.

      keymap-sequence-validate <path> [--json]
          Validate an exported keymap feature sequence and print non-zero records.

      keymap-file-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported keymap feature sequence file.

      keymap-profile-create <path> [--name=Name] <source=target[:modifier]> [...]
          Create an app-local keymap JSON profile without opening HID.

      keymap-profile-validate <path>
          Validate a keymap JSON profile without opening HID.

      keymap-profile-show <path> [--json]
          Show a keymap JSON profile, optionally as raw JSON for app editors.

      keymap-profile-export <profile.json> <output.hex>
          Export a keymap JSON profile to a validated feature sequence file.

      keymap-profile-apply <profile.json> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write a keymap JSON profile.

      keymap-library-create [--directory=path] [--slot=name] [--name=Name] <source=target[:modifier]> [...]
          Create or replace a named keymap profile in the app-local keymap library.

      keymap-library-save <profile.json> [--slot=name] [--directory=path]
          Validate and copy an existing keymap JSON profile into the app-local keymap library.

      keymap-library-list [--directory=path] [--json]
          List saved app-local keymap profiles.

      keymap-library-show <slot> [--directory=path] [--json]
          Show a saved app-local keymap profile.

      keymap-library-export <slot> <output.hex> [--directory=path]
          Export a saved app-local keymap profile to a feature sequence file.

      keymap-library-apply <slot> [--directory=path] \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write a saved app-local keymap profile.

      keymap-library-delete <slot> [--directory=path]
          Delete a saved app-local keymap profile.

      keymap-library-bundle-export <path> [--directory=path]
          Export all saved app-local keymap profiles to one portable JSON bundle.

      keymap-library-bundle-import <path> [--directory=path]
          Validate and import a portable JSON keymap library bundle.

      keymap-map-apply <source=target[:modifier]> [...] \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a full custom-keymap table containing multiple simple remaps.

      keymap-apply <source-key> <target-key-or-hid-hex> [modifier-key-or-hid-hex] \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a full custom-keymap table containing only this simple remap.

      keymap-clear \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write an empty custom-keymap table, likely clearing custom remaps.

      lighting-custom-rgb-export <path> [key=rrggbb ...]
          Write the candidate 04 23 custom-lighting RGB sequence to a file without HID.

      lighting-custom-rgb-validate <path> [--json]
          Validate an exported candidate custom-lighting RGB sequence without HID.

      lighting-custom-rgb-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported custom-lighting RGB sequence file.

      lighting-mode-export <path> [index=hexbyte ...]
          Write the candidate 04 23 selector-03 lighting-mode table sequence without HID.

      lighting-mode-preset-list
          List built-in candidate lighting-mode table presets.

      lighting-mode-preset-export <path> <preset-name>
          Write a built-in candidate lighting-mode table preset without HID.

      lighting-mode-preset-apply <preset-name> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a built-in candidate lighting-mode preset sequence.

      lighting-effect-list
          List Windows-named candidate lighting effects mapped to selector-03 values.

      lighting-effect-export <path> <effect-name>
          Write a Windows-named candidate lighting effect table without HID.

      lighting-effect-apply <effect-name> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: write a Windows-named candidate lighting effect sequence.

      lighting-mode-validate <path> [--json]
          Validate an exported candidate lighting-mode table sequence without HID.

      lighting-mode-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported lighting-mode sequence file.

      alternate-table-export <path> <source=target[:modifier]> [...]
          Write the candidate 04 27 alternate full-table sequence without HID.

      alternate-table-validate <path> [--json]
          Validate an exported candidate 04 27 alternate full-table sequence without HID.

      alternate-table-apply <path> \(unsafeKeymapFlag) [--write-index=N]
          UNSAFE: validate and write an exported 04 27 alternate full-table sequence.

    Device target:
      VID 0x05AC, PID 0x024F, usage page 0xFFFF, usage 0x0001
    """)
}

private func run(_ args: [String]) throws {
    guard let command = args.dropFirst().first else {
        printUsage()
        return
    }

    switch command {
    case "list":
        let driver = HIDDriver()
        let devices = driver.configurationDevices()
        if devices.isEmpty {
            throw DriverError.noDevice
        }
        printDevices(devices)

    case "scan":
        let driver = HIDDriver()
        let devices = driver.devices()
        if devices.isEmpty {
            throw DriverError.noDevice
        }
        printDevices(devices)

    case "dump-layout":
        print(try layoutReportText(), terminator: "")

    case "self-test":
        guard args.count == 2 else {
            printUsage()
            return
        }
        try runSelfTest()

    case "doctor":
        guard args.count == 2 || (args.count == 3 && args[2] == "--open-check") else {
            printUsage()
            return
        }
        try runDoctor(openCheck: args.contains("--open-check"))

    case "readiness":
        guard args.count == 2 || (args.count == 3 && args[2] == "--open-check") else {
            printUsage()
            return
        }
        print(readinessReport(openCheck: args.contains("--open-check")), terminator: "")

    case "protocol-candidates":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printProtocolCandidates()

    case "validation-plan":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(validationPlanText())

    case "diagnostics":
        guard args.count == 2 || args.count == 3 else {
            printUsage()
            return
        }
        let report = diagnosticsReport()
        if args.count == 3 {
            try report.write(toFile: args[2], atomically: true, encoding: .utf8)
            print("Saved diagnostics report to \(args[2]). No HID reports were sent.")
        } else {
            print(report, terminator: "")
        }

    case "support-bundle":
        guard args.count == 2 || args.count == 3 else {
            printUsage()
            return
        }
        let path = args.count == 3 ? args[2] : defaultSupportBundlePath()
        try writeSupportBundle(directoryPath: path)
        print("Saved support bundle to \(path). No HID reports were sent.")

    case "permission-status":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(inputMonitoringPermissionReport(request: false), terminator: "")

    case "permission-request":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(inputMonitoringPermissionReport(request: true), terminator: "")

    case "factory-reset-dry-run":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print("Modeled GMK67 factory reset preview:")
        print("  RGB: clear all known physical key LED records to 00 00 00.")
        print("  Keymap: write the empty custom-keymap table.")
        print("Rendered RGB records:")
        printRGBRecords(try factoryResetRGBFrames(), keyByLightIndex: keyMapByLightIndex())
        print("Candidate keymap clear sequence: \(factoryResetKeymapSequence().count) reports, 9 table chunks, AA 55 marker at table offset 0x23E.")
        print("Dry run only: no HID device was opened and no reports were sent.")

    case "factory-reset-export":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let outputs = try writeFactoryResetArtifacts(prefix: args[2])
        print("Saved modeled factory-reset RGB artifact to \(outputs.rgbPath).")
        print("Saved modeled factory-reset keymap-clear artifact to \(outputs.keymapPath).")
        print("No HID device was opened.")

    case "factory-reset":
        let options = try parseUnsafeFactoryResetOptions(Array(args.dropFirst(2)))
        try applyFactoryResetToDevice(writeIndex: options.writeIndex, readIndex: options.readIndex)

    case "profile-create":
        let options = try parseProfileCreateOptions(Array(args.dropFirst(2)))
        try writeCombinedProfile(options.profile, path: options.path)
        print("Saved GMK67 profile to \(options.path). No HID device was opened.")
        printCombinedProfile(options.profile)

    case "profile-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        print("GMK67 profile OK. No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-preview":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        try printCombinedProfilePreview(profile)

    case "profile-show":
        guard args.count == 3 || (args.count == 4 && args[3] == "--json") else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        if args.contains("--json") {
            try printCombinedProfileJSON(profile)
        } else {
            printCombinedProfile(profile)
        }

    case "profile-preview-spec":
        let profile = try parseProfileLibraryCreateOptions(Array(args.dropFirst(2)))
        try printCombinedProfilePreview(profile)

    case "profile-export-spec":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let prefix = args[2]
        let profile = try parseProfileLibraryCreateOptions(Array(args.dropFirst(3)))
        let outputs = try exportCombinedProfileArtifacts(profile, prefix: prefix)
        print("Saved composed RGB artifact to \(outputs.rgbPath). No HID device was opened.")
        if let keymapPath = outputs.keymapPath {
            print("Saved composed keymap artifact to \(keymapPath).")
        } else {
            print("Inline profile has no keymap changes; no keymap artifact was written.")
        }

    case "profile-apply-spec":
        let options = try parseInlineProfileApplyOptions(Array(args.dropFirst(2)))
        try applyCombinedProfileToDevice(
            options.profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        let outputs = try exportCombinedProfileArtifacts(profile, prefix: args[3])
        print("Saved composed RGB artifact to \(outputs.rgbPath). No HID device was opened.")
        if let keymapPath = outputs.keymapPath {
            print("Saved composed keymap artifact to \(keymapPath).")
        } else {
            print("Profile has no keymap changes; no keymap artifact was written.")
        }

    case "profile-apply":
        let options = try parseProfileApplyOptions(Array(args.dropFirst(2)))
        let profile = try readCombinedProfile(options.path)
        try applyCombinedProfileToDevice(
            profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printCombinedProfilePresetList()

    case "profile-preset-show":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let preset = try combinedProfilePreset(named: args[2])
        if args.count == 4 {
            switch args[3] {
            case "--json":
                try printCombinedProfileJSON(try makeCombinedProfile(from: preset))
            case "--editor-json":
                try printCombinedProfileJSON(try makeEditableCombinedProfile(from: preset))
            default:
                printUsage()
                return
            }
        } else {
            printCombinedProfile(try makeCombinedProfile(from: preset))
        }

    case "profile-preset-create":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let preset = try combinedProfilePreset(named: args[3])
        let profile = try makeCombinedProfile(from: preset)
        try writeCombinedProfile(profile, path: args[2])
        print("Saved GMK67 profile preset \(preset.name) to \(args[2]). No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-preset-apply":
        let options = try parseProfilePresetApplyOptions(Array(args.dropFirst(2)))
        let preset = try combinedProfilePreset(named: options.name)
        let profile = try makeCombinedProfile(from: preset)
        try applyCombinedProfileToDevice(
            profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-library-create":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        var slot: String?
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--slot=") }) {
            slot = String(arguments.remove(at: index).dropFirst("--slot=".count))
        }
        let profile = try parseProfileLibraryCreateOptions(arguments)
        let url = try saveProfileToLibrary(profile, slot: slot, directory: directory)
        print("Saved profile library entry to \(url.path). No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-library-save":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard !arguments.isEmpty else {
            printUsage()
            return
        }
        let path = arguments.removeFirst()
        var slot: String?
        for argument in arguments {
            if argument.hasPrefix("--slot=") {
                slot = String(argument.dropFirst("--slot=".count))
            } else {
                throw DriverError.invalidArgument("Unknown profile-library-save option: \(argument)")
            }
        }
        let profile = try readCombinedProfile(path)
        let url = try saveProfileToLibrary(profile, slot: slot, directory: directory)
        print("Saved profile library entry to \(url.path). No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-library-list":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.isEmpty else {
            throw DriverError.invalidArgument("Unknown profile-library-list option: \(arguments.joined(separator: " "))")
        }
        if wantsJSON {
            try printProfileLibraryJSON(directory: directory)
        } else {
            try printProfileLibraryList(directory: directory)
        }

    case "profile-library-preview":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let profile = try readProfileFromLibrary(slot: arguments[0], directory: directory)
        try printCombinedProfilePreview(profile)

    case "profile-library-show":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let profile = try readProfileFromLibrary(slot: arguments[0], directory: directory)
        if wantsJSON {
            try printCombinedProfileJSON(profile)
        } else {
            printCombinedProfile(profile)
        }

    case "profile-library-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 2 else {
            printUsage()
            return
        }
        let profile = try readProfileFromLibrary(slot: arguments[0], directory: directory)
        let outputs = try exportCombinedProfileArtifacts(profile, prefix: arguments[1])
        print("Saved composed RGB artifact to \(outputs.rgbPath). No HID device was opened.")
        if let keymapPath = outputs.keymapPath {
            print("Saved composed keymap artifact to \(keymapPath).")
        } else {
            print("Profile has no keymap section; no keymap artifact was written.")
        }

    case "profile-library-apply":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard let slot = arguments.first else {
            printUsage()
            return
        }
        let options = try parseProfileApplyOptions(["library-profile"] + Array(arguments.dropFirst()))
        let profile = try readProfileFromLibrary(slot: slot, directory: directory)
        try applyCombinedProfileToDevice(
            profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-library-delete":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let url = try profileLibraryURL(slot: arguments[0], directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DriverError.invalidArgument("Profile library entry not found: \(arguments[0])")
        }
        try FileManager.default.removeItem(at: url)
        print("Deleted profile library entry \(arguments[0]) from \(directory.path).")

    case "profile-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeProfileLibraryBundle(directory: directory, path: arguments[0])
        print("Saved \(bundle.profiles.count) profile library entr\(bundle.profiles.count == 1 ? "y" : "ies") to \(arguments[0]).")
        print("No HID device was opened.")

    case "profile-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let importedSlots = try importProfileLibraryBundle(arguments[0], directory: directory)
        print("Imported \(importedSlots.count) profile library entr\(importedSlots.count == 1 ? "y" : "ies") into \(directory.path).")
        if !importedSlots.isEmpty {
            print("Slots: \(importedSlots.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "app-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directories = try appLibraryDirectories(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeAppLibraryBundle(
            profileDirectory: directories.profiles,
            keymapDirectory: directories.keymaps,
            macroDirectory: directories.macros,
            path: arguments[0]
        )
        print("Saved app library bundle to \(arguments[0]).")
        print("  profiles: \(bundle.profiles.count)")
        print("  keymaps: \(bundle.keymaps.count)")
        print("  macros: \(bundle.macros.count)")
        print("No HID device was opened.")

    case "app-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directories = try appLibraryDirectories(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let imported = try importAppLibraryBundle(
            arguments[0],
            profileDirectory: directories.profiles,
            keymapDirectory: directories.keymaps,
            macroDirectory: directories.macros
        )
        print("Imported app library bundle into:")
        print("  profiles: \(directories.profiles.path) (\(imported.profiles.count))")
        print("  keymaps: \(directories.keymaps.path) (\(imported.keymaps.count))")
        print("  macros: \(directories.macros.path) (\(imported.macros.count))")
        if !imported.profiles.isEmpty {
            print("Profile slots: \(imported.profiles.joined(separator: ", "))")
        }
        if !imported.keymaps.isEmpty {
            print("Keymap slots: \(imported.keymaps.joined(separator: ", "))")
        }
        if !imported.macros.isEmpty {
            print("Macro slots: \(imported.macros.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "macro-create":
        let options = try parseMacroCreateOptions(Array(args.dropFirst(2)))
        try writeMacroProfile(options.macro, path: options.path)
        print("Saved GMK67 macro to \(options.path). No HID device was opened.")
        printMacroProfile(options.macro)

    case "macro-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let macro = try readMacroProfile(args[2])
        print("GMK67 macro OK. No HID device was opened.")
        printMacroProfile(macro)

    case "macro-show":
        guard args.count == 3 || (args.count == 4 && args[3] == "--json") else {
            printUsage()
            return
        }
        let macro = try readMacroProfile(args[2])
        if args.contains("--json") {
            try printMacroProfileJSON(macro)
        } else {
            printMacroProfile(macro)
        }

    case "macro-library-create":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        var slot: String?
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--slot=") }) {
            slot = String(arguments.remove(at: index).dropFirst("--slot=".count))
        }
        let macro = try parseMacroLibraryCreateOptions(arguments)
        let url = try saveMacroToLibrary(macro, slot: slot, directory: directory)
        print("Saved macro library entry to \(url.path). No HID device was opened.")
        printMacroProfile(macro)

    case "macro-library-save":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard !arguments.isEmpty else {
            printUsage()
            return
        }
        let path = arguments.removeFirst()
        var slot: String?
        for argument in arguments {
            if argument.hasPrefix("--slot=") {
                slot = String(argument.dropFirst("--slot=".count))
            } else {
                throw DriverError.invalidArgument("Unknown macro-library-save option: \(argument)")
            }
        }
        let macro = try readMacroProfile(path)
        let url = try saveMacroToLibrary(macro, slot: slot, directory: directory)
        print("Saved macro library entry to \(url.path). No HID device was opened.")
        printMacroProfile(macro)

    case "macro-library-list":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.isEmpty else {
            throw DriverError.invalidArgument("Unknown macro-library-list option: \(arguments.joined(separator: " "))")
        }
        if wantsJSON {
            try printMacroLibraryJSON(directory: directory)
        } else {
            try printMacroLibraryList(directory: directory)
        }

    case "macro-library-show":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let macro = try readMacroFromLibrary(slot: arguments[0], directory: directory)
        if wantsJSON {
            try printMacroProfileJSON(macro)
        } else {
            printMacroProfile(macro)
        }

    case "macro-library-delete":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let url = try macroLibraryURL(slot: arguments[0], directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DriverError.invalidArgument("Macro library entry not found: \(arguments[0])")
        }
        try FileManager.default.removeItem(at: url)
        print("Deleted macro library entry \(arguments[0]) from \(directory.path).")

    case "macro-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeMacroLibraryBundle(directory: directory, path: arguments[0])
        print("Saved \(bundle.macros.count) macro library entr\(bundle.macros.count == 1 ? "y" : "ies") to \(arguments[0]).")
        print("No HID device was opened.")

    case "macro-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let importedSlots = try importMacroLibraryBundle(arguments[0], directory: directory)
        print("Imported \(importedSlots.count) macro library entr\(importedSlots.count == 1 ? "y" : "ies") into \(directory.path).")
        if !importedSlots.isEmpty {
            print("Slots: \(importedSlots.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "keymap-dry-run":
        guard args.count == 4 || args.count == 5 else {
            printUsage()
            return
        }
        let source = try keyByArgument(args[2])
        let targetUsage = try hidUsageByArgument(args[3])
        let modifierUsage = args.count == 5 ? try hidUsageByArgument(args[4]) : nil
        let table = try keymapSimpleRemapTable(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        let sequence = keymapFeatureSequence(table: table)
        let tableReportCount = sequence.count - 4

        let modifierText = modifierUsage.map { String(format: " modifier=0x%02X encoded=0x%02X", $0, keymapEncodedUsage($0)) } ?? ""
        let remap = KeymapRemap(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        print(String(
            format: "Candidate simple remap: source=%@ key_index=%d target_hid=0x%02X encoded=0x%02X%@",
            source.name,
            source.keyIndex,
            targetUsage,
            keymapEncodedUsage(targetUsage),
            modifierText
        ))
        print(String(
            format: "Changed table record offset=0x%03X bytes=%@",
            source.keyIndex * 4,
            hex(keymapRemapRecord(remap))
        ))
        print("Dry run only: no HID device was opened and no reports were sent.")
        print(String(
            format: "Modeled Windows chunking: declared table length=0x%03X, table reports=%d, AA 55 marker at offset=0x23E.",
            table.count,
            tableReportCount
        ))
        print("This sequence represents a full custom-keymap table containing only the displayed remap.")
        print("Candidate feature sequence:")
        printFeatureSequence(sequence)

    case "keymap-clear-dry-run":
        guard args.count == 2 else {
            printUsage()
            return
        }
        let table = emptyKeymapTable()
        let sequence = keymapFeatureSequence(table: table)
        print("Candidate empty custom keymap table.")
        print("Dry run only: no HID device was opened and no reports were sent.")
        print(String(
            format: "Modeled Windows chunking: declared table length=0x%03X, table reports=%d, AA 55 marker at offset=0x23E.",
            table.count,
            sequence.count - 4
        ))
        print("Candidate feature sequence:")
        printFeatureSequence(sequence)

    case "keymap-export":
        guard args.count == 5 || args.count == 6 else {
            printUsage()
            return
        }
        let path = args[2]
        let source = try keyByArgument(args[3])
        let targetUsage = try hidUsageByArgument(args[4])
        let modifierUsage = args.count == 6 ? try hidUsageByArgument(args[5]) : nil
        let table = try keymapSimpleRemapTable(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        let sequence = keymapFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print(String(
            format: "Saved %d keymap feature reports to %@ for %@ -> HID 0x%02X. No HID device was opened.",
            sequence.count,
            path,
            source.name,
            targetUsage
        ))

    case "keymap-clear-export":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let sequence = keymapFeatureSequence(table: emptyKeymapTable())
        try writeFeatureSequenceFile(sequence, path: args[2])
        print("Saved \(sequence.count) empty-keymap feature reports to \(args[2]). No HID device was opened.")

    case "keymap-map-dry-run":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let remaps = try parseKeymapRemapSpecs(Array(args.dropFirst(2)))
        let table = try keymapRemapTable(remaps)
        let sequence = keymapFeatureSequence(table: table)
        print("Candidate multi-remap custom keymap table:")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print("Dry run only: no HID device was opened and no reports were sent.")
        print(String(
            format: "Modeled Windows chunking: declared table length=0x%03X, table reports=%d, AA 55 marker at offset=0x23E.",
            table.count,
            sequence.count - 4
        ))
        print("Candidate feature sequence:")
        printFeatureSequence(sequence)

    case "keymap-map-export":
        guard args.count >= 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let remaps = try parseKeymapRemapSpecs(Array(args.dropFirst(3)))
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) keymap feature reports with \(remaps.count) remap(s) to \(path). No HID device was opened.")

    case "keymap-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printKeymapPresetList()

    case "keymap-preset-show":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let preset = try keymapPreset(named: args[2])
        if args.count == 4 {
            guard args[3] == "--json" else {
                printUsage()
                return
            }
            try printKeymapPresetJSON(preset)
        } else {
            printKeymapPreset(preset)
        }

    case "keymap-preset-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let preset = try keymapPreset(named: args[3])
        let remaps = try keymapPresetRemaps(preset)
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) keymap feature reports for preset \(preset.name) to \(path). No HID device was opened.")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }

    case "keymap-preset-apply":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        guard options.operands.count == 1 else {
            printUsage()
            return
        }
        let preset = try keymapPreset(named: options.operands[0])
        let remaps = try keymapPresetRemaps(preset)
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying keymap preset \(preset.name): \(preset.description)")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate keymap preset sequence sent.")

    case "keymap-sequence-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateKeymapFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printKeymapRecordsJSON(sequence)
        }

    case "keymap-file-apply":
        let options = try parseUnsafeKeymapFileOptions(Array(args.dropFirst(2)))
        let sequence = try validateKeymapFeatureSequenceFile(options.path)
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Writing validated keymap sequence file \(options.path).")
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Validated keymap sequence file sent.")

    case "keymap-profile-create":
        let options = try parseKeymapProfileCreateOptions(Array(args.dropFirst(2)))
        try writeKeymapProfile(options.profile, path: options.path)
        print("Saved GMK67 keymap profile to \(options.path). No HID device was opened.")
        printKeymapProfile(options.profile)

    case "keymap-profile-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let profile = try readKeymapProfile(args[2])
        print("GMK67 keymap profile OK. No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-profile-show":
        guard args.count == 3 || (args.count == 4 && args[3] == "--json") else {
            printUsage()
            return
        }
        let profile = try readKeymapProfile(args[2])
        if args.contains("--json") {
            try printKeymapProfileJSON(profile)
        } else {
            printKeymapProfile(profile)
        }

    case "keymap-profile-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let profile = try readKeymapProfile(args[2])
        try writeKeymapProfileSequence(profile, path: args[3])
        print("Saved \(try keymapProfileSequence(profile).count) keymap feature reports to \(args[3]). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-profile-apply":
        let options = try parseUnsafeKeymapFileOptions(Array(args.dropFirst(2)))
        let profile = try readKeymapProfile(options.path)
        let sequence = try keymapProfileSequence(profile)
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying keymap profile \(profile.name).")
        printKeymapProfile(profile)
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Keymap profile sequence sent.")

    case "keymap-library-create":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        var slot: String?
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--slot=") }) {
            slot = String(arguments.remove(at: index).dropFirst("--slot=".count))
        }
        let profile = try parseKeymapLibraryCreateOptions(arguments)
        let url = try saveKeymapToLibrary(profile, slot: slot, directory: directory)
        print("Saved keymap library entry to \(url.path). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-library-save":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard !arguments.isEmpty else {
            printUsage()
            return
        }
        let path = arguments.removeFirst()
        var slot: String?
        for argument in arguments {
            if argument.hasPrefix("--slot=") {
                slot = String(argument.dropFirst("--slot=".count))
            } else {
                throw DriverError.invalidArgument("Unknown keymap-library-save option: \(argument)")
            }
        }
        let profile = try readKeymapProfile(path)
        let url = try saveKeymapToLibrary(profile, slot: slot, directory: directory)
        print("Saved keymap library entry to \(url.path). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-library-list":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.isEmpty else {
            throw DriverError.invalidArgument("Unknown keymap-library-list option: \(arguments.joined(separator: " "))")
        }
        if wantsJSON {
            try printKeymapLibraryJSON(directory: directory)
        } else {
            try printKeymapLibraryList(directory: directory)
        }

    case "keymap-library-show":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let profile = try readKeymapFromLibrary(slot: arguments[0], directory: directory)
        if wantsJSON {
            try printKeymapProfileJSON(profile)
        } else {
            printKeymapProfile(profile)
        }

    case "keymap-library-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 2 else {
            printUsage()
            return
        }
        let profile = try readKeymapFromLibrary(slot: arguments[0], directory: directory)
        try writeKeymapProfileSequence(profile, path: arguments[1])
        print("Saved \(try keymapProfileSequence(profile).count) keymap feature reports to \(arguments[1]). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-library-apply":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        let options = try parseUnsafeKeymapOptions(arguments)
        guard options.operands.count == 1 else {
            printUsage()
            return
        }
        let profile = try readKeymapFromLibrary(slot: options.operands[0], directory: directory)
        let sequence = try keymapProfileSequence(profile)
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying saved keymap profile \(options.operands[0]): \(profile.name).")
        printKeymapProfile(profile)
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Saved keymap profile sequence sent.")

    case "keymap-library-delete":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let url = try keymapLibraryURL(slot: arguments[0], directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DriverError.invalidArgument("Keymap library entry not found: \(arguments[0])")
        }
        try FileManager.default.removeItem(at: url)
        print("Deleted keymap library entry \(arguments[0]) from \(directory.path).")

    case "keymap-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeKeymapLibraryBundle(directory: directory, path: arguments[0])
        print("Saved \(bundle.profiles.count) keymap library entr\(bundle.profiles.count == 1 ? "y" : "ies") to \(arguments[0]).")
        print("No HID device was opened.")

    case "keymap-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let importedSlots = try importKeymapLibraryBundle(arguments[0], directory: directory)
        print("Imported \(importedSlots.count) keymap library entr\(importedSlots.count == 1 ? "y" : "ies") into \(directory.path).")
        if !importedSlots.isEmpty {
            print("Slots: \(importedSlots.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "keymap-map-apply":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        let remaps = try parseKeymapRemapSpecs(options.operands)
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("This writes a full custom-keymap table containing \(remaps.count) simple remap(s).")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate multi-remap keymap sequence sent.")

    case "keymap-apply":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        guard options.operands.count == 2 || options.operands.count == 3 else {
            printUsage()
            return
        }
        let source = try keyByArgument(options.operands[0])
        let targetUsage = try hidUsageByArgument(options.operands[1])
        let modifierUsage = options.operands.count == 3 ? try hidUsageByArgument(options.operands[2]) : nil
        let table = try keymapSimpleRemapTable(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        let sequence = keymapFeatureSequence(table: table)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("This writes a full custom-keymap table containing only the requested remap.")
        print(String(
            format: "Writing %@ -> HID 0x%02X on scanned interface %d using %d feature reports...",
            source.name,
            targetUsage,
            options.writeIndex,
            sequence.count
        ))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate keymap write sequence sent.")

    case "keymap-clear":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        guard options.operands.isEmpty else {
            printUsage()
            return
        }
        let sequence = keymapFeatureSequence(table: emptyKeymapTable())
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Writing an empty custom-keymap table; this is expected to clear custom remaps.")
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate empty keymap sequence sent.")

    case "lighting-custom-rgb-export":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let path = args[2]
        let keyMap = keyMapByLightIndex()
        let assignments = args.count > 3 ? try parseRGBAssignmentSpecs(Array(args.dropFirst(3)), keyMap: keyMap) : []
        let table = try customLightingRGBTable(assignments: assignments)
        let sequence = customLightingRGBFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate custom-lighting RGB feature reports to \(path). No HID device was opened.")
        print("This is an offline artifact for the 04 23 extended/custom-RGB path. Live apply is guarded by \(unsafeKeymapFlag).")
        for assignment in assignments {
            print(String(
                format: "  %@ (0x%02X) = %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }

    case "lighting-custom-rgb-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateCustomLightingRGBFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printRGBRecordsJSON(Array(sequence[2...10]), keyByLightIndex: keyMapByLightIndex(), recordByteLimit: 0x23E)
        }

    case "lighting-custom-rgb-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "custom-lighting RGB")
        let sequence = try validateCustomLightingRGBFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "custom-lighting RGB")

    case "lighting-mode-export":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let path = args[2]
        let keyMap = keyMapByLightIndex()
        let assignments = args.count > 3 ? try parseByteAssignmentSpecs(Array(args.dropFirst(3)), keyMap: keyMap) : []
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate lighting-mode feature reports to \(path). No HID device was opened.")
        print("This is an offline artifact for the 04 23 selector-03 table path. Live apply is guarded by \(unsafeKeymapFlag).")
        for assignment in assignments {
            print(String(format: "  %@ (0x%02X) = %02X", assignment.label, assignment.index, assignment.value))
        }

    case "lighting-mode-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printLightingModePresetList()

    case "lighting-mode-preset-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let preset = try lightingModePreset(named: args[3])
        let assignments = try lightingModePresetAssignments(preset)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate lighting-mode preset \(preset.name) to \(path). No HID device was opened.")
        print("\(preset.title): \(preset.description)")
        for assignment in assignments {
            print(String(format: "  %@ (0x%02X) = %02X", assignment.label, assignment.index, assignment.value))
        }

    case "lighting-mode-preset-apply":
        let options = try parseUnsafeCandidateNameOptions(Array(args.dropFirst(2)), kind: "lighting-mode preset")
        let preset = try lightingModePreset(named: options.name)
        let assignments = try lightingModePresetAssignments(preset)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        print("Applying candidate lighting-mode preset \(preset.name): \(preset.description)")
        for assignment in assignments {
            print(String(format: "  %@ (0x%02X) = %02X", assignment.label, assignment.index, assignment.value))
        }
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "lighting-mode preset")

    case "lighting-effect-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printLightingEffectList()

    case "lighting-effect-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let effect = try lightingEffect(named: args[3])
        let assignments = lightingEffectAssignments(effect)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate lighting effect \(effect.name) to \(path). No HID device was opened.")
        print(String(format: "%@ maps all %d known physical keys to selector-03 value 0x%02X.", effect.title, assignments.count, effect.value))
        print("This is an offline artifact for the 04 23 selector-03 table path. Live apply is guarded by \(unsafeKeymapFlag).")

    case "lighting-effect-apply":
        let options = try parseUnsafeCandidateNameOptions(Array(args.dropFirst(2)), kind: "lighting effect")
        let effect = try lightingEffect(named: options.name)
        let assignments = lightingEffectAssignments(effect)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        print(String(format: "Applying candidate lighting effect %@: all %d known physical keys -> selector-03 value 0x%02X.", effect.name, assignments.count, effect.value))
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "lighting effect")

    case "lighting-mode-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateLightingModeFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printByteRecordsJSON(Array(sequence[2...4]), byteLimit: 0xBE, keyByLightIndex: keyMapByLightIndex())
        }

    case "lighting-mode-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "lighting-mode")
        let sequence = try validateLightingModeFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "lighting-mode")

    case "alternate-table-export":
        guard args.count >= 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let remaps = try parseKeymapRemapSpecs(Array(args.dropFirst(3)))
        let table = try keymapRemapTable(remaps)
        let sequence = alternateFullTableFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate 04 27 alternate full-table feature reports to \(path). No HID device was opened.")
        print("This is an offline artifact for the alternate full-table path. Live apply is guarded by \(unsafeKeymapFlag).")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }

    case "alternate-table-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateAlternateFullTableFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printKeymapRecordsJSON(sequence)
        }

    case "alternate-table-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "alternate full-table")
        let sequence = try validateAlternateFullTableFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "alternate full-table")

    case "feature-get":
        guard args.count == 4, let reportID = Int(args[2], radix: 16), let length = Int(args[3]) else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let bytes = try driver.getFeature(reportID: reportID, length: length)
        print(hex(bytes))

    case "feature-get-at":
        guard
            args.count == 5,
            let index = Int(args[2]),
            let reportID = Int(args[3], radix: 16),
            let length = Int(args[4])
        else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let device = try driver.device(at: index, configurationOnly: true)
        let bytes = try driver.getFeature(device: device, reportID: reportID, length: length)
        print(hex(bytes))

    case "feature-scan":
        let index = args.count > 2 ? Int(args[2]) : 0
        let start = args.count > 3 ? Int(args[3], radix: 16) : 0
        let end = args.count > 4 ? Int(args[4], radix: 16) : 0xFF
        let length = args.count > 5 ? Int(args[5]) : 64
        guard
            args.count <= 6,
            let index,
            let start,
            let end,
            let length,
            start <= end,
            length > 0
        else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let device = try driver.device(at: index, configurationOnly: true)
        for reportID in start...end {
            do {
                let bytes = try driver.getFeature(device: device, reportID: reportID, length: length)
                let meaningful = bytes.contains { $0 != 0 }
                print(String(
                    format: "0x%02X  ok  len=%3d  %@%@",
                    reportID,
                    bytes.count,
                    meaningful ? "" : "(all zero) ",
                    hex(bytes)
                ))
            } catch DriverError.getReportFailed {
                continue
            }
        }

    case "input-listen":
        let index = args.count > 2 ? Int(args[2]) : 0
        let length = args.count > 3 ? Int(args[3]) : nil
        let seconds = args.count > 4 ? Double(args[4]) : 10.0
        guard args.count <= 5, let index, let seconds, seconds > 0 else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let infos = driver.configurationDevices()
        guard infos.indices.contains(index) else { throw DriverError.noDevice }
        let reportLength = length ?? max(infos[index].maxInputReportSize, 1)
        guard reportLength > 0 else { throw DriverError.invalidArgument("Input report length must be positive.") }
        let device = try driver.device(at: index, configurationOnly: true)
        print(String(format: "Listening on configuration interface %d for %.1f seconds...", index, seconds))
        try driver.listenInput(device: device, length: reportLength, seconds: seconds)

    case "key-test":
        let index = args.count > 2 ? Int(args[2]) : 0
        let length = args.count > 3 ? Int(args[3]) : nil
        let seconds = args.count > 4 ? Double(args[4]) : 10.0
        guard args.count <= 5, let index, let seconds, seconds > 0 else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let infos = driver.configurationDevices()
        guard infos.indices.contains(index) else { throw DriverError.noDevice }
        let reportLength = length ?? max(infos[index].maxInputReportSize, 8)
        guard reportLength >= 8 else {
            throw DriverError.invalidArgument("Key test report length must be at least 8 bytes.")
        }
        let device = try driver.device(at: index, configurationOnly: true)
        print(String(format: "Key test on configuration interface %d for %.1f seconds...", index, seconds))
        print("Press keys on the GMK67. Reports are decoded as boot keyboard modifiers/usages.")
        try driver.listenKeyboardInput(device: device, length: reportLength, seconds: seconds)

    case "input-get-at":
        guard
            args.count == 5,
            let index = Int(args[2]),
            let reportID = Int(args[3], radix: 16),
            let length = Int(args[4])
        else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let device = try driver.device(at: index, configurationOnly: false)
        let bytes = try driver.getInput(device: device, reportID: reportID, length: length)
        print(hex(bytes))

    case "feature-set":
        guard args.count == 4, let reportID = Int(args[2], radix: 16) else {
            printUsage()
            return
        }
        let payload = try parseHexBytes(args[3])
        let driver = HIDDriver()
        try driver.setFeature(reportID: reportID, payload: payload)
        print("Wrote \(payload.count) bytes to feature report 0x\(String(format: "%02X", reportID)).")

    case "feature-set64":
        guard args.count == 4, let reportID = Int(args[2], radix: 16) else {
            printUsage()
            return
        }
        var payload = try parseHexBytes(args[3])
        guard payload.count <= 64 else {
            throw DriverError.invalidArgument("feature-set64 payload must be 64 bytes or fewer before padding.")
        }
        payload += [UInt8](repeating: 0, count: 64 - payload.count)
        let driver = HIDDriver()
        try driver.setFeature(reportID: reportID, payload: payload)
        print("Wrote 64 bytes to feature report 0x\(String(format: "%02X", reportID)).")

    case "rgb-read-probe":
        let writeIndex = args.count > 2 ? Int(args[2]) : 0
        let listenIndex = args.count > 3 ? Int(args[3]) : 1
        let chunks = args.count > 4 ? Int(args[4]) : 3
        let seconds = args.count > 5 ? Double(args[5]) : 2.0
        guard
            args.count <= 6,
            let writeIndex,
            let listenIndex,
            let chunks,
            let seconds,
            chunks > 0,
            chunks <= 9,
            seconds > 0
        else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let infos = driver.configurationDevices()
        guard infos.indices.contains(writeIndex), infos.indices.contains(listenIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: true)
        let listenDevice = try driver.device(at: listenIndex, configurationOnly: true)
        let listenLength = max(infos[listenIndex].maxInputReportSize, 1)
        var payload = [UInt8](repeating: 0, count: 64)
        payload[0] = 0x04
        payload[1] = 0xF5
        payload[8] = UInt8(chunks)
        print(String(
            format: "Listening on interface %d for %.1f seconds, then probing via feature interface %d...",
            listenIndex,
            seconds,
            writeIndex
        ))
        try driver.listenAfterWrite(
            listenDevice: listenDevice,
            listenLength: listenLength,
            seconds: seconds,
            writeDevice: writeDevice,
            payload: payload
        )

    case "rgb-read-get-probe":
        let writeIndex = args.count > 2 ? Int(args[2]) : 0
        let readIndex = args.count > 3 ? Int(args[3]) : 0
        let readReportID = args.count > 4 ? Int(args[4], radix: 16) : 0
        let length = args.count > 5 ? Int(args[5]) : 64
        let chunks = args.count > 6 ? Int(args[6]) : 3
        guard
            args.count <= 7,
            let writeIndex,
            let readIndex,
            let readReportID,
            let length,
            let chunks,
            length > 0,
            chunks > 0,
            chunks <= 9
        else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        var payload = [UInt8](repeating: 0, count: 64)
        payload[0] = 0x04
        payload[1] = 0xF5
        payload[8] = UInt8(chunks)
        try driver.setFeature(device: writeDevice, reportID: 0, payload: payload)
        print("Sent feature report 0x00 on scanned interface \(writeIndex): \(hex(payload))")
        for attempt in 1...chunks {
            usleep(50_000)
            do {
                let bytes = try driver.getInput(device: readDevice, reportID: readReportID, length: length)
                print(String(format: "#%03d report=0x%02X len=%3d  %@", attempt, readReportID, bytes.count, hex(bytes)))
            } catch {
                print("#\(String(format: "%03d", attempt)) error: \(error)")
            }
        }

    case "rgb-dump":
        var dumpArgs = Array(args.dropFirst(2))
        var wantsJSON = false
        if let jsonIndex = dumpArgs.firstIndex(of: "--json") {
            dumpArgs.remove(at: jsonIndex)
            wantsJSON = true
        }
        let writeIndex = dumpArgs.count > 0 ? Int(dumpArgs[0]) : 0
        let readIndex = dumpArgs.count > 1 ? Int(dumpArgs[1]) : 0
        let chunks = dumpArgs.count > 2 ? Int(dumpArgs[2]) : 9
        guard
            dumpArgs.count <= 3,
            let writeIndex,
            let readIndex,
            let chunks,
            chunks > 0,
            chunks <= 9
        else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        var payload = [UInt8](repeating: 0, count: 64)
        payload[0] = 0x04
        payload[1] = 0xF5
        payload[8] = UInt8(chunks)
        try driver.setFeature(device: writeDevice, reportID: 0, payload: payload)

        var frames: [[UInt8]] = []
        for chunk in 1...chunks {
            usleep(50_000)
            let bytes = try driver.getInput(device: readDevice, reportID: 0, length: 64)
            frames.append(bytes)
            if !wantsJSON {
                if chunk == 1 {
                    print("Sent RGB readback request for \(chunks) chunks.")
                }
                print(String(format: "#%03d len=%3d  %@", chunk, bytes.count, hex(bytes)))
            }
        }
        if wantsJSON {
            try printRGBRecordsJSON(frames, keyByLightIndex: keyMapByLightIndex())
        } else {
            print("Non-zero RGB records:")
            printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())
        }

    case "rgb-set-key":
        guard args.count >= 4, args.count <= 6 else {
            printUsage()
            return
        }
        let keyArgument = args[2]
        let colorBytes = try parseHexBytes(args[3])
        guard colorBytes.count == 3 else {
            throw DriverError.invalidArgument("Color must be exactly three bytes, for example FF0000 or FF 00 00.")
        }
        let writeIndex = args.count > 4 ? Int(args[4]) : 0
        let readIndex = args.count > 5 ? Int(args[5]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let keyMap = keyMapByLightIndex()
        let target = try lightTargetByArgument(keyArgument, keyMap: keyMap)
        let lightIndex = target.lightIndex

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)

        var frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(frames)
        print("Saved pre-write RGB table to \(backupPath).")

        try setRGBRecord(frames: &frames, lightIndex: lightIndex, color: colorBytes)

        let keyLabel = target.label
        print(String(format: "Setting %@ (0x%02X) to %02X %02X %02X", keyLabel, lightIndex, colorBytes[0], colorBytes[1], colorBytes[2]))
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")

        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let records = rgbFramesToRecords(verifyFrames)
        if let record = records[lightIndex] {
            print(String(
                format: "Rendered readback 0x%02X %@ rgb=%02X %02X %02X",
                lightIndex,
                keyLabel,
                record.red,
                record.green,
                record.blue
            ))
        }
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the bytes sent.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMap)

    case "rgb-map":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let options = try parseRGBMapOptions(Array(args.dropFirst(2)))
        let keyMap = keyMapByLightIndex()
        let assignments = try parseRGBAssignmentSpecs(options.specs, keyMap: keyMap)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex), devices.indices.contains(options.readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: options.writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: options.readIndex, configurationOnly: false)

        var frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(frames)
        print("Saved pre-write RGB table to \(backupPath).")

        try applyRGBAssignments(assignments, to: &frames)
        for assignment in assignments {
            print(String(
                format: "Setting %@ (0x%02X) to %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")

        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the bytes sent.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMap)

    case "rgb-file-map":
        guard args.count >= 5 else {
            printUsage()
            return
        }
        let inputPath = args[2]
        let outputPath = args[3]
        let keyMap = keyMapByLightIndex()
        let assignments = try parseRGBAssignmentSpecs(Array(args.dropFirst(4)), keyMap: keyMap)
        var frames = try readRGBFramesFile(inputPath)
        try applyRGBAssignments(assignments, to: &frames)
        try writeRGBFramesFile(frames, path: outputPath)
        print("Saved edited RGB table to \(outputPath). No HID device was opened.")
        for assignment in assignments {
            print(String(
                format: "  %@ (0x%02X) = %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }

    case "rgb-profile-create":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let outputPath = args[2]
        let keyMap = keyMapByLightIndex()
        let options = try parseRGBProfileCreateOptions(Array(args.dropFirst(3)))
        let assignments = options.specs.isEmpty ? [] : try parseRGBAssignmentSpecs(options.specs, keyMap: keyMap)
        var frames = sampleRGBFrames()
        if let fillColor = options.fillColor {
            try applyRGBFill(fillColor, to: &frames, keyMap: physicalKeysByLightIndex())
            print(String(
                format: "Filled known physical keys with %02X %02X %02X.",
                fillColor[0],
                fillColor[1],
                fillColor[2]
            ))
        }
        try applyRGBAssignments(assignments, to: &frames)
        try writeRGBFramesFile(frames, path: outputPath)
        print("Saved RGB profile to \(outputPath). No HID device was opened.")
        for assignment in assignments {
            print(String(
                format: "  %@ (0x%02X) = %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }

    case "rgb-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printRGBPresetList()

    case "rgb-preset-show":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let preset = try rgbPreset(named: args[2])
        if args.count == 4 {
            guard args[3] == "--json" else {
                printUsage()
                return
            }
            try printRGBPresetJSON(preset)
        } else {
            printRGBPreset(preset)
        }

    case "rgb-preset-create":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let outputPath = args[2]
        let preset = try rgbPreset(named: args[3])
        let frames = try rgbPresetFrames(preset)
        try writeRGBFramesFile(frames, path: outputPath)
        print("Saved RGB preset \(preset.name) to \(outputPath). No HID device was opened.")
        print("\(preset.title): \(preset.description)")
        print("Non-zero RGB records:")
        printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-preset-apply":
        guard args.count >= 3, args.count <= 5 else {
            printUsage()
            return
        }
        let preset = try rgbPreset(named: args[2])
        let writeIndex = args.count > 3 ? Int(args[3]) : 0
        let readIndex = args.count > 4 ? Int(args[4]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)

        let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(currentFrames)
        print("Saved pre-write RGB table to \(backupPath).")

        let frames = try rgbPresetFrames(preset)
        print("Applying RGB preset \(preset.name): \(preset.description)")
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")

        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the preset bytes.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-file-dump":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let frames = try readRGBFramesFile(args[2])
        if wantsJSON {
            try printRGBRecordsJSON(frames, keyByLightIndex: keyMapByLightIndex())
        } else {
            print("Loaded \(frames.count) RGB frames from \(args[2]).")
            print("Non-zero RGB records:")
            printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())
        }

    case "rgb-set-all", "rgb-clear":
        let colorBytes: [UInt8]
        let writeIndexArgument: Int
        if command == "rgb-clear" {
            colorBytes = [0, 0, 0]
            writeIndexArgument = 2
        } else {
            guard args.count >= 3 else {
                printUsage()
                return
            }
            let parsedColor = try parseHexBytes(args[2])
            guard parsedColor.count == 3 else {
                throw DriverError.invalidArgument("Color must be exactly three bytes, for example FF0000 or FF 00 00.")
            }
            colorBytes = parsedColor
            writeIndexArgument = 3
        }
        let writeIndex = args.count > writeIndexArgument ? Int(args[writeIndexArgument]) : 0
        let readIndex = args.count > writeIndexArgument + 1 ? Int(args[writeIndexArgument + 1]) : 0
        guard args.count <= writeIndexArgument + 2, let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let keyMap = physicalKeysByLightIndex()
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        var frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(frames)
        print("Saved pre-write RGB table to \(backupPath).")
        for lightIndex in keyMap.keys {
            try setRGBRecord(frames: &frames, lightIndex: lightIndex, color: colorBytes)
        }

        print(String(
            format: "Setting %d physical keys to %02X %02X %02X",
            keyMap.count,
            colorBytes[0],
            colorBytes[1],
            colorBytes[2]
        ))
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")
        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the bytes sent.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-save":
        guard args.count >= 3, args.count <= 5 else {
            printUsage()
            return
        }
        let path = args[2]
        let writeIndex = args.count > 3 ? Int(args[3]) : 0
        let readIndex = args.count > 4 ? Int(args[4]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        let frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        try writeRGBFramesFile(frames, path: path)
        print("Saved \(frames.count) RGB frames to \(path).")
        print("Non-zero RGB records:")
        printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-restore":
        guard args.count >= 3, args.count <= 5 else {
            printUsage()
            return
        }
        let path = args[2]
        let writeIndex = args.count > 3 ? Int(args[3]) : 0
        let readIndex = args.count > 4 ? Int(args[4]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }
        let frames = try readRGBFramesFile(path)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(currentFrames)
        print("Saved pre-restore RGB table to \(backupPath).")

        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Restored RGB table from \(path). Reading rendered table back...")
        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the file bytes.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-restore-dry-run":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let frames = try readRGBFramesFile(args[2])
        print("RGB restore dry run: \(args[2]) is valid with \(frames.count) 64-byte frame(s).")
        print("Dry run only: no HID device was opened and no reports were sent.")
        print("Non-zero RGB records:")
        printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-backups":
        guard args.count == 2 || args.count == 3 else {
            printUsage()
            return
        }
        let directory = args.count == 3 ? args[2] : "."
        let backups = rgbBackupFiles(directoryPath: directory)
        if backups.isEmpty {
            print("No valid RGB backup files found in \(directory).")
        } else {
            print("Valid RGB backups in \(directory):")
            for backup in backups {
                print("  \(backup.url.path)  frames=\(backup.frameCount)")
            }
        }
        print("No HID device was opened.")

    case "rgb-restore-latest":
        let options = try parseRGBRestoreLatestOptions(Array(args.dropFirst(2)))
        let backup = try latestRGBBackup(directoryPath: options.directory)
        let frames = try readRGBFramesFile(backup.url.path)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex), devices.indices.contains(options.readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: options.writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: options.readIndex, configurationOnly: false)
        let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(currentFrames)
        print("Saved pre-restore RGB table to \(backupPath).")

        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Restored latest RGB backup from \(backup.url.path). Reading rendered table back...")
        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the backup file bytes.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "help", "--help", "-h":
        printUsage()

    default:
        printUsage()
    }
}

private func printDevices(_ devices: [HIDDeviceInfo]) {
    for (index, device) in devices.enumerated() {
        print("[\(index)] \(device.product.isEmpty ? GMK67.productName : device.product)")
        print(String(format: "    VID:PID    %04X:%04X", device.vendorID, device.productID))
        print(String(format: "    Usage      %04X:%04X", device.usagePage, device.usage))
        print(String(format: "    Primary    %04X:%04X", device.primaryUsagePage, device.primaryUsage))
        print("    Pairs      \(formatUsagePairs(device.usagePairs))")
        print("    Maker      \(device.manufacturer.isEmpty ? "-" : device.manufacturer)")
        print("    Serial     \(device.serial.isEmpty ? "-" : device.serial)")
        print("    Reports    feature \(device.maxFeatureReportSize), input \(device.maxInputReportSize), output \(device.maxOutputReportSize) bytes max")
        print("    Config     \(device.isLikelyConfigurationInterface ? "yes" : "no")")
    }
}

private func formatUsagePairs(_ pairs: [(page: Int, usage: Int)]) -> String {
    guard !pairs.isEmpty else { return "-" }
    return pairs
        .map { String(format: "%04X:%04X", $0.page, $0.usage) }
        .joined(separator: ", ")
}

do {
    try run(CommandLine.arguments)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
