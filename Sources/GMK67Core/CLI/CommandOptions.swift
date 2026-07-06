import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func parseProfileApplyOptions(_ args: [String]) throws -> (path: String, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) {
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

func parseProfilePresetApplyOptions(_ args: [String]) throws -> (name: String, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) {
    guard let name = args.first else {
        throw DriverError.invalidArgument("profile-preset-apply requires a preset name.")
    }
    let options = try parseProfileApplyOptions(["profile-preset"] + Array(args.dropFirst()))
    return (name, options.hasUnsafeFlag, options.writeIndex, options.readIndex)
}

func parseInlineProfileApplyOptions(_ args: [String]) throws -> (profile: CombinedProfile, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) {
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

func applyCombinedProfileToDevice(_ profile: CombinedProfile, hasUnsafeFlag: Bool, writeIndex: Int, readIndex: Int) throws {
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

func combinedProfileKeymapSequence(_ profile: CombinedProfile) throws -> [[UInt8]]? {
    let remaps = try combinedProfileKeymapRemaps(profile)
    guard !remaps.isEmpty else { return nil }
    return keymapFeatureSequence(table: try keymapRemapTable(remaps))
}

func printCombinedProfilePreview(_ profile: CombinedProfile) throws {
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

func factoryResetRGBFrames() throws -> [[UInt8]] {
    var frames = sampleRGBFrames()
    try applyRGBFill([0x00, 0x00, 0x00], to: &frames, keyMap: physicalKeysByLightIndex())
    return frames
}

func factoryResetKeymapSequence() -> [[UInt8]] {
    keymapFeatureSequence(table: emptyKeymapTable())
}

func writeFactoryResetArtifacts(prefix: String) throws -> (rgbPath: String, keymapPath: String) {
    let rgbPath = "\(prefix)-rgb.hex"
    let keymapPath = "\(prefix)-keymap-clear.hex"
    try writeRGBFramesFile(try factoryResetRGBFrames(), path: rgbPath)
    try writeFeatureSequenceFile(factoryResetKeymapSequence(), path: keymapPath)
    return (rgbPath, keymapPath)
}

func applyFactoryResetToDevice(writeIndex: Int, readIndex: Int) throws {
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

func exportCombinedProfileArtifacts(_ profile: CombinedProfile, prefix: String) throws -> (rgbPath: String, keymapPath: String?) {
    let rgbPath = "\(prefix)-rgb.hex"
    try writeRGBFramesFile(try combinedProfileRGBFrames(profile), path: rgbPath)

    if let sequence = try combinedProfileKeymapSequence(profile) {
        let keymapPath = "\(prefix)-keymap.hex"
        try writeFeatureSequenceFile(sequence, path: keymapPath)
        return (rgbPath, keymapPath)
    }
    return (rgbPath, nil)
}

func parseRGBMapOptions(_ args: [String]) throws -> (specs: [String], writeIndex: Int, readIndex: Int) {
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

func parseRGBProfileCreateOptions(_ args: [String]) throws -> (specs: [String], fillColor: [UInt8]?) {
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

func parseRGBRestoreLatestOptions(_ args: [String]) throws -> (directory: String, writeIndex: Int, readIndex: Int) {
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

func parseByteNumber(_ argument: String, label: String) throws -> Int {
    let lower = argument.lowercased()
    let normalized = lower.replacingOccurrences(of: "0x", with: "")
    let radix = lower.hasPrefix("0x") ? 16 : 10
    guard let value = Int(normalized, radix: radix), value >= 0, value <= 0xFF else {
        throw DriverError.invalidArgument("\(label) must be a byte value from 0x00 to 0xFF: \(argument)")
    }
    return value
}

func lightingModeIndexByArgument(_ argument: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> (index: Int, label: String) {
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

func parseByteAssignmentSpec(_ spec: String, keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> ByteAssignment {
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

func parseByteAssignmentSpecs(_ specs: [String], keyMap: [Int: KeyItem] = keyMapByLightIndex()) throws -> [ByteAssignment] {
    let assignments = try specs.map { try parseByteAssignmentSpec($0, keyMap: keyMap) }
    var seenIndices = Set<Int>()
    for assignment in assignments {
        guard seenIndices.insert(assignment.index).inserted else {
            throw DriverError.invalidArgument("Duplicate lighting-mode table index in assignment list: \(assignment.label)")
        }
    }
    return assignments
}

func parseOneByteLiteral(_ argument: String, field: String) throws -> UInt8 {
    let lowercased = argument.lowercased()
    if lowercased.hasPrefix("0x") {
        let value = String(lowercased.dropFirst(2))
        guard let parsed = UInt8(value, radix: 16) else {
            throw DriverError.invalidArgument("Invalid \(field) byte value: \(argument)")
        }
        return parsed
    }
    if let parsed = UInt8(argument, radix: 10) {
        return parsed
    }
    let bytes = try parseHexBytes(argument)
    guard bytes.count == 1 else {
        throw DriverError.invalidArgument("\(field) must be exactly one byte: \(argument)")
    }
    return bytes[0]
}

func parseRawByteAssignmentSpec(_ spec: String, maxOffset: Int, kind: String) throws -> ByteAssignment {
    let assignment = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard assignment.count == 2, !assignment[0].isEmpty, !assignment[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid \(kind) byte assignment '\(spec)'. Use offset=value, for example 0x01=01.")
    }
    let offset = Int(try parseOneByteLiteral(String(assignment[0]), field: "\(kind) offset"))
    guard offset <= maxOffset else {
        throw DriverError.invalidArgument("\(kind) offset 0x\(String(format: "%02X", offset)) is outside the writable range 0x00...0x\(String(format: "%02X", maxOffset)).")
    }
    let value = try parseOneByteLiteral(String(assignment[1]), field: "\(kind) value")
    return ByteAssignment(index: offset, label: String(format: "0x%02X", offset), value: value)
}

func parseRawByteAssignmentSpecs(_ specs: [String], maxOffset: Int, kind: String) throws -> [ByteAssignment] {
    let assignments = try specs.map { try parseRawByteAssignmentSpec($0, maxOffset: maxOffset, kind: kind) }
    var seenOffsets = Set<Int>()
    for assignment in assignments {
        guard seenOffsets.insert(assignment.index).inserted else {
            throw DriverError.invalidArgument("Duplicate \(kind) byte offset in assignment list: \(assignment.label)")
        }
    }
    return assignments
}

let keyboardSettingsKnownFields: [(name: String, offset: Int, windowsKey: String)] = [
    ("gamemode", 0x01, "gamemode"),
    ("disable-alttab", 0x02, "disable_alttab"),
    ("disable-altf4", 0x03, "disable_altf4"),
    ("disable-win", 0x04, "disable_win"),
    ("fn-switchfunction", 0x05, "fn_switchfunction"),
    ("sleep-light", 0x06, "sleep_light")
]

let keyboardSettingsFieldAliases: [String: String] = [
    "gamemode": "gamemode",
    "game-mode": "gamemode",
    "game": "gamemode",
    "disable-alttab": "disable-alttab",
    "disable-alt-tab": "disable-alttab",
    "alt-tab-lock": "disable-alttab",
    "disable-altf4": "disable-altf4",
    "disable-alt-f4": "disable-altf4",
    "alt-f4-lock": "disable-altf4",
    "disable-win": "disable-win",
    "disable-windows": "disable-win",
    "win-lock": "disable-win",
    "windows-key-lock": "disable-win",
    "fn-switchfunction": "fn-switchfunction",
    "fn-switch-function": "fn-switchfunction",
    "fn-switch": "fn-switchfunction",
    "sleep-light": "sleep-light",
    "light-sleep": "sleep-light",
    "sleep": "sleep-light"
]

func normalizeKeyboardSettingsFieldName(_ name: String) -> String {
    name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "_", with: "-")
}

func keyboardSettingsField(for rawName: String) -> (name: String, offset: Int, windowsKey: String)? {
    let normalized = normalizeKeyboardSettingsFieldName(rawName)
    let canonical = keyboardSettingsFieldAliases[normalized] ?? normalized
    return keyboardSettingsKnownFields.first { $0.name == canonical }
}

func parseKeyboardSettingsFieldValue(_ value: String, field: String) throws -> UInt8 {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "yes", "on", "enabled", "enable":
        return 1
    case "false", "no", "off", "disabled", "disable":
        return 0
    default:
        return try parseOneByteLiteral(value, field: field)
    }
}

func parseKeyboardSettingsAssignmentSpec(_ spec: String) throws -> ByteAssignment {
    let assignment = spec.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    guard assignment.count == 2, !assignment[0].isEmpty, !assignment[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid keyboard-settings assignment '\(spec)'. Use field=value or offset=value, for example gamemode=on or 0x01=01.")
    }

    let target = String(assignment[0])
    let valueText = String(assignment[1])
    if let field = keyboardSettingsField(for: target) {
        let value = try parseKeyboardSettingsFieldValue(valueText, field: "keyboard-settings \(field.name)")
        return ByteAssignment(index: field.offset, label: "\(field.name) (\(field.windowsKey), offset 0x\(String(format: "%02X", field.offset)))", value: value)
    }

    return try parseRawByteAssignmentSpec(spec, maxOffset: 0x3D, kind: "keyboard-settings")
}

func parseKeyboardSettingsAssignmentSpecs(_ specs: [String]) throws -> [ByteAssignment] {
    let assignments = try specs.map(parseKeyboardSettingsAssignmentSpec)
    var seenOffsets = Set<Int>()
    for assignment in assignments {
        guard seenOffsets.insert(assignment.index).inserted else {
            throw DriverError.invalidArgument("Duplicate keyboard-settings byte offset in assignment list: \(assignment.label)")
        }
    }
    return assignments
}

func applyRGBAssignments(_ assignments: [RGBAssignment], to frames: inout [[UInt8]]) throws {
    for assignment in assignments {
        try setRGBRecord(frames: &frames, lightIndex: assignment.lightIndex, color: assignment.color)
    }
}

func applyRGBFill(_ color: [UInt8], to frames: inout [[UInt8]], keyMap: [Int: KeyItem]) throws {
    for lightIndex in keyMap.keys {
        try setRGBRecord(frames: &frames, lightIndex: lightIndex, color: color)
    }
}

func hidUsageByArgument(_ argument: String) throws -> UInt8 {
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

func keymapEncodedUsage(_ usage: UInt8) -> UInt8 {
    if usage >= 0xE0 && usage <= 0xE7 {
        return UInt8(1 << (usage - 0xE0))
    }
    return usage
}

func emptyKeymapTable() -> [UInt8] {
    var table = [UInt8](repeating: 0, count: 0x2B6)
    table[0x23E] = 0xAA
    table[0x23F] = 0x55
    return table
}

func keymapSimpleRemapTable(source: KeyItem, targetUsage: UInt8, modifierUsage: UInt8?) throws -> [UInt8] {
    try keymapRemapTable([KeymapRemap(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)])
}

func keymapRemapTable(_ remaps: [KeymapRemap]) throws -> [UInt8] {
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

func writeKeymapRemap(_ remap: KeymapRemap, into table: inout [UInt8]) throws {
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

func parseKeymapRemapSpec(_ spec: String) throws -> KeymapRemap {
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

func parseKeymapRemapSpecs(_ specs: [String]) throws -> [KeymapRemap] {
    guard !specs.isEmpty else {
        throw DriverError.invalidArgument("At least one remap spec is required.")
    }
    return try specs.map(parseKeymapRemapSpec)
}

func keymapRemapSummary(_ remap: KeymapRemap) -> String {
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

func keymapRemapRecord(_ remap: KeymapRemap) -> [UInt8] {
    [
        0x02,
        remap.modifierUsage.map(keymapEncodedUsage) ?? 0,
        keymapEncodedUsage(remap.targetUsage),
        0x00
    ]
}

func hexByte(_ value: UInt8) -> String {
    String(format: "0x%02X", value)
}

func keymapUsageName(encoded value: UInt8, keysByCode: [Int: KeyItem]) -> String {
    if let preferred = preferredHIDUsageNames[value] {
        return preferred
    }
    if let key = keysByCode[Int(value)] {
        return key.name
    }
    return hexByte(value)
}

func keymapRecordJSON(_ payloads: [[UInt8]]) throws -> [KeymapRecordJSON] {
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

func printKeymapRecordsJSON(_ payloads: [[UInt8]]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(keymapRecordJSON(payloads))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

func keymapFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x11
    select[8] = 0x09
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: table.count) + [commit, finish]
}

func alternateFullTableFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x27
    select[8] = 0x09
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: 0x2AC) + [commit, finish]
}

func customLightingRGBTable(assignments: [RGBAssignment]) throws -> [UInt8] {
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

func customLightingRGBFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x23
    select[8] = 0x09
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: table.count) + [commit, finish]
}

func lightingModeTable(assignments: [ByteAssignment]) throws -> [UInt8] {
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

func lightingModeFeatureSequence(table: [UInt8]) -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x23
    select[8] = 0x03
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + windowsChunkedFeaturePayloads(table, declaredLength: table.count) + [commit, finish]
}

let defaultMacroFirmwareChunkCount = 8
let maxMacroFirmwareChunkCount = 0x38

func macroFirmwareTemplateFeatureSequence(chunkCount: Int = defaultMacroFirmwareChunkCount) throws -> [[UInt8]] {
    guard chunkCount >= 1, chunkCount <= maxMacroFirmwareChunkCount else {
        throw DriverError.invalidArgument("Macro firmware chunk count must be between 1 and \(maxMacroFirmwareChunkCount).")
    }

    let begin = [0x04, 0x19] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x15
    select[8] = UInt8(chunkCount)

    var table = [UInt8](repeating: 0, count: chunkCount * 64)
    table[table.count - 2] = 0xAA
    table[table.count - 1] = 0x55

    let chunks = stride(from: 0, to: table.count, by: 64).map { offset in
        Array(table[offset..<(offset + 64)])
    }
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    return [begin, select] + chunks + [commit]
}

func shortOperationTemplatePayload(variant: String) throws -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: 64)
    switch variant {
    case "empty":
        break
    case "static-80":
        payload[0] = 0x80
        payload[9] = 0x0F
        payload[10] = 0x0F
    default:
        throw DriverError.invalidArgument("Unknown short-op template variant: \(variant). Use empty or static-80.")
    }
    payload[14] = 0xAA
    payload[15] = 0x55
    return payload
}

func shortOperationTemplateFeatureSequence(variant: String = "empty") throws -> [[UInt8]] {
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x13
    select[8] = 0x01
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    let finish = [0x04, 0xF0] + [UInt8](repeating: 0, count: 62)
    return [begin, select, try shortOperationTemplatePayload(variant: variant), commit, finish]
}

func keyboardSettingsPayload(assignments: [ByteAssignment]) throws -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: 64)
    for assignment in assignments {
        guard assignment.index <= 0x3D else {
            throw DriverError.invalidArgument("Keyboard-settings payload offset 0x\(String(format: "%02X", assignment.index)) overlaps the AA 55 marker.")
        }
        payload[assignment.index] = assignment.value
    }
    payload[0x3E] = 0xAA
    payload[0x3F] = 0x55
    return payload
}

func keyboardSettingsFeatureSequence(profile: UInt8 = 0, payload: [UInt8]) throws -> [[UInt8]] {
    guard payload.count == 64 else {
        throw DriverError.invalidArgument("Keyboard-settings payload must be exactly 64 bytes.")
    }
    let begin = [0x04, 0x18] + [UInt8](repeating: 0, count: 62)
    var select = [UInt8](repeating: 0, count: 64)
    select[0] = 0x04
    select[1] = 0x17
    select[2] = profile
    select[8] = 0x01
    let commit = [0x04, 0x02] + [UInt8](repeating: 0, count: 62)
    return [begin, select, payload, commit]
}

func windowsChunkedFeaturePayloads(_ payload: [UInt8], declaredLength: Int) -> [[UInt8]] {
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

func printFeatureSequence(_ payloads: [[UInt8]]) {
    for (index, payload) in payloads.enumerated() {
        print(String(format: "#%03d report=0x00 len=%3d  %@", index + 1, payload.count, hex(payload)))
    }
}

func writeFeatureSequenceFile(_ payloads: [[UInt8]], path: String) throws {
    let text = payloads.map(hex).joined(separator: "\n") + "\n"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func readFeatureSequenceFile(_ path: String) throws -> [[UInt8]] {
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
func validateKeyboardSettingsFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count == 4 else {
        throw DriverError.invalidArgument("Expected 4 keyboard-settings feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every keyboard-settings feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x18] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 18.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x17], payloads[1][8] == 0x01 else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 17 and have byte 8 set to 01.")
    }
    guard payloads[2][0x3E] == 0xAA, payloads[2][0x3F] == 0x55 else {
        throw DriverError.invalidArgument("Report #003 must contain AA 55 at payload offsets 0x3E...0x3F.")
    }
    guard Array(payloads[3].prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Report #004 must begin with 04 02.")
    }

    if printSummary {
        print("Keyboard-settings sequence OK: 4 reports, selector 04 17 byte8=01, profile byte=\(String(format: "%02X", payloads[1][2])), AA 55 marker at payload offsets 0x3E...0x3F.")
        print("Known keyboard-settings fields:")
        for field in keyboardSettingsKnownFields {
            print(String(format: "  %@ (%@, offset 0x%02X) = 0x%02X", field.name, field.windowsKey, field.offset, payloads[2][field.offset]))
        }
        print("Non-zero keyboard-settings payload bytes:")
        printNonZeroRawBytes(payloads[2], markerRange: 0x3E..<0x40)
    }
    return payloads
}

func printNonZeroRawBytes(_ bytes: [UInt8], markerRange: Range<Int>? = nil) {
    var count = 0
    for (offset, byte) in bytes.enumerated() {
        guard byte != 0 else { continue }
        if let markerRange, markerRange.contains(offset) {
            continue
        }
        count += 1
        print(String(format: "  offset=0x%03X value=0x%02X", offset, byte))
    }
    if count == 0 {
        print("  none")
    }
}

@discardableResult
func validateMacroFirmwareFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count >= 4 else {
        throw DriverError.invalidArgument("Expected at least 4 macro firmware feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every macro firmware feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x19] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 19.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x15] else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 15.")
    }
    guard Array(payloads.last!.prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Final report must begin with 04 02.")
    }

    let chunkCount = Int(payloads[1][8])
    guard chunkCount >= 1, chunkCount <= maxMacroFirmwareChunkCount else {
        throw DriverError.invalidArgument("Report #002 byte 8 must declare 1...\(maxMacroFirmwareChunkCount) table chunks.")
    }
    guard payloads.count == chunkCount + 3 else {
        throw DriverError.invalidArgument("Report #002 declares \(chunkCount) table chunks, but file contains \(payloads.count - 3).")
    }

    let table = Array(payloads[2..<(2 + chunkCount)].joined())
    guard table[table.count - 2] == 0xAA, table[table.count - 1] == 0x55 else {
        throw DriverError.invalidArgument("Expected AA 55 marker at the end of the macro firmware table.")
    }

    if printSummary {
        print("Macro firmware sequence OK: \(payloads.count) reports, selector 04 15 byte8=\(String(format: "%02X", chunkCount)), \(chunkCount) table chunks, AA 55 marker at final table bytes.")
        print("Non-zero macro firmware bytes:")
        printNonZeroRawBytes(table, markerRange: (table.count - 2)..<table.count)
    }
    return payloads
}

@discardableResult
func validateShortOperationFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
    let payloads = try readFeatureSequenceFile(path)
    guard payloads.count == 5 else {
        throw DriverError.invalidArgument("Expected 5 short-op feature reports, found \(payloads.count).")
    }
    guard payloads.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("Every short-op feature report must contain exactly 64 bytes.")
    }
    guard Array(payloads[0].prefix(2)) == [0x04, 0x18] else {
        throw DriverError.invalidArgument("Report #001 must begin with 04 18.")
    }
    guard Array(payloads[1].prefix(2)) == [0x04, 0x13], payloads[1][8] == 0x01 else {
        throw DriverError.invalidArgument("Report #002 must begin with 04 13 and have byte 8 set to 01.")
    }
    guard payloads[2][14] == 0xAA, payloads[2][15] == 0x55 else {
        throw DriverError.invalidArgument("Report #003 must contain AA 55 at payload offsets 0x0E...0x0F.")
    }
    guard Array(payloads[3].prefix(2)) == [0x04, 0x02] else {
        throw DriverError.invalidArgument("Report #004 must begin with 04 02.")
    }
    guard Array(payloads[4].prefix(2)) == [0x04, 0xF0] else {
        throw DriverError.invalidArgument("Report #005 must begin with 04 F0.")
    }

    if printSummary {
        print("Short operation sequence OK: 5 reports, selector 04 13 byte8=01, AA 55 marker at payload offsets 0x0E...0x0F.")
        print("Non-zero short-op payload bytes:")
        printNonZeroRawBytes(payloads[2], markerRange: 14..<16)
    }
    return payloads
}

@discardableResult
func validateKeymapFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
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
func validateCustomLightingRGBFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
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
func validateLightingModeFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
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
func validateAlternateFullTableFeatureSequenceFile(_ path: String, printSummary: Bool = true) throws -> [[UInt8]] {
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

func sendFeatureSequence(driver: HIDDriver, device: IOHIDDevice, payloads: [[UInt8]]) throws {
    for payload in payloads {
        guard payload.count == 64 else {
            throw DriverError.invalidArgument("Feature sequence payloads must be exactly 64 bytes.")
        }
        try driver.setFeature(device: device, reportID: 0, payload: payload)
        usleep(30_000)
    }
}

func sendUnsafeCandidateFeatureSequence(_ payloads: [[UInt8]], writeIndex: Int, kind: String) throws {
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

func parseUnsafeKeymapOptions(_ args: [String]) throws -> (operands: [String], writeIndex: Int) {
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

func parseUnsafeKeymapFileOptions(_ args: [String]) throws -> (path: String, writeIndex: Int) {
    let options = try parseUnsafeKeymapOptions(args)
    guard options.operands.count == 1 else {
        throw DriverError.invalidArgument("Expected exactly one keymap sequence file path.")
    }
    return (options.operands[0], options.writeIndex)
}

func parseUnsafeCandidateFileOptions(_ args: [String], kind: String) throws -> (path: String, writeIndex: Int) {
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

func parseUnsafeCandidateNameOptions(_ args: [String], kind: String) throws -> (name: String, writeIndex: Int) {
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

func parseUnsafeFactoryResetOptions(_ args: [String]) throws -> (writeIndex: Int, readIndex: Int) {
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

func assertSelfTest(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw DriverError.invalidArgument("Self-test failed: \(message)")
    }
}

func expectInvalidArgument(_ message: String, _ body: () throws -> Void) throws {
    do {
        try body()
    } catch DriverError.invalidArgument {
        return
    }
    throw DriverError.invalidArgument("Self-test failed: expected invalid argument for \(message)")
}

func sampleRGBFrames() -> [[UInt8]] {
    (0..<9).map { frameIndex in
        var frame: [UInt8] = []
        for recordIndex in 0..<16 {
            frame += [UInt8(frameIndex * 16 + recordIndex), 0, 0, 0]
        }
        return frame
    }
}

func runSelfTest(verbose: Bool = true) throws {
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
    let macroFirmwareSequence = try macroFirmwareTemplateFeatureSequence()
    try assertSelfTest(macroFirmwareSequence.count == defaultMacroFirmwareChunkCount + 3, "macro firmware sequence report count")
    try assertSelfTest(Array(macroFirmwareSequence[0].prefix(2)) == [0x04, 0x19], "macro firmware begin report")
    try assertSelfTest(
        Array(macroFirmwareSequence[1].prefix(2)) == [0x04, 0x15] &&
            macroFirmwareSequence[1][8] == UInt8(defaultMacroFirmwareChunkCount),
        "macro firmware selector report"
    )
    try assertSelfTest(
        Array(macroFirmwareSequence[defaultMacroFirmwareChunkCount + 1][62..<64]) == [0xAA, 0x55],
        "macro firmware marker"
    )
    try assertSelfTest(
        Array(macroFirmwareSequence[defaultMacroFirmwareChunkCount + 2].prefix(2)) == [0x04, 0x02],
        "macro firmware commit report"
    )
    let macroFirmwarePath = tempDirectory.appendingPathComponent("macro-firmware.hex").path
    try writeFeatureSequenceFile(macroFirmwareSequence, path: macroFirmwarePath)
    let validatedMacroFirmwareSequence = try validateMacroFirmwareFeatureSequenceFile(macroFirmwarePath, printSummary: verbose)
    try assertSelfTest(validatedMacroFirmwareSequence == macroFirmwareSequence, "macro firmware validation returns original sequence")
    let macroFirmwareFileOptions = try parseUnsafeCandidateFileOptions([macroFirmwarePath, unsafeKeymapFlag, "--write-index=5"], kind: "macro firmware")
    try assertSelfTest(macroFirmwareFileOptions.path == macroFirmwarePath && macroFirmwareFileOptions.writeIndex == 5, "macro firmware apply option parsing")
    try expectInvalidArgument("macro firmware chunk guard") {
        _ = try macroFirmwareTemplateFeatureSequence(chunkCount: maxMacroFirmwareChunkCount + 1)
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

    let shortOperationSequence = try shortOperationTemplateFeatureSequence()
    try assertSelfTest(shortOperationSequence.count == 5, "short-op sequence report count")
    try assertSelfTest(Array(shortOperationSequence[0].prefix(2)) == [0x04, 0x18], "short-op begin report")
    try assertSelfTest(
        Array(shortOperationSequence[1].prefix(2)) == [0x04, 0x13] &&
            shortOperationSequence[1][8] == 0x01,
        "short-op selector report"
    )
    try assertSelfTest(Array(shortOperationSequence[2][14..<16]) == [0xAA, 0x55], "short-op marker")
    try assertSelfTest(Array(shortOperationSequence[3].prefix(2)) == [0x04, 0x02], "short-op commit report")
    try assertSelfTest(Array(shortOperationSequence[4].prefix(2)) == [0x04, 0xF0], "short-op finish report")
    let staticShortOperationSequence = try shortOperationTemplateFeatureSequence(variant: "static-80")
    try assertSelfTest(
        staticShortOperationSequence[2][0] == 0x80 &&
            staticShortOperationSequence[2][9] == 0x0F &&
            staticShortOperationSequence[2][10] == 0x0F,
        "short-op static-80 template"
    )
    let shortOperationPath = tempDirectory.appendingPathComponent("short-op.hex").path
    try writeFeatureSequenceFile(shortOperationSequence, path: shortOperationPath)
    let validatedShortOperationSequence = try validateShortOperationFeatureSequenceFile(shortOperationPath, printSummary: verbose)
    try assertSelfTest(validatedShortOperationSequence == shortOperationSequence, "short-op validation returns original sequence")
    try expectInvalidArgument("short-op unknown variant") {
        _ = try shortOperationTemplateFeatureSequence(variant: "unknown")
    }

    let keyboardSettingsAssignments = try parseKeyboardSettingsAssignmentSpecs([
        "gamemode=on",
        "disable-win=true",
        "sleep-light=30",
        "0x07=04"
    ])
    try assertSelfTest(
        keyboardSettingsAssignments.map(\.index) == [0x01, 0x04, 0x06, 0x07] &&
            keyboardSettingsAssignments.map(\.value) == [0x01, 0x01, 0x1E, 0x04],
        "keyboard settings assignment parsing"
    )
    let keyboardSettingsPayloadBytes = try keyboardSettingsPayload(assignments: keyboardSettingsAssignments)
    try assertSelfTest(
        keyboardSettingsPayloadBytes[0x01] == 0x01 &&
            keyboardSettingsPayloadBytes[0x04] == 0x01 &&
            keyboardSettingsPayloadBytes[0x06] == 0x1E &&
            keyboardSettingsPayloadBytes[0x07] == 0x04 &&
            Array(keyboardSettingsPayloadBytes[0x3E..<0x40]) == [0xAA, 0x55],
        "keyboard settings payload"
    )
    let keyboardSettingsSequence = try keyboardSettingsFeatureSequence(profile: 0x02, payload: keyboardSettingsPayloadBytes)
    try assertSelfTest(keyboardSettingsSequence.count == 4, "keyboard settings sequence report count")
    try assertSelfTest(Array(keyboardSettingsSequence[0].prefix(2)) == [0x04, 0x18], "keyboard settings begin report")
    try assertSelfTest(
        Array(keyboardSettingsSequence[1].prefix(2)) == [0x04, 0x17] &&
            keyboardSettingsSequence[1][2] == 0x02 &&
            keyboardSettingsSequence[1][8] == 0x01,
        "keyboard settings selector report"
    )
    try assertSelfTest(Array(keyboardSettingsSequence[3].prefix(2)) == [0x04, 0x02], "keyboard settings commit report")
    let keyboardSettingsPath = tempDirectory.appendingPathComponent("keyboard-settings.hex").path
    try writeFeatureSequenceFile(keyboardSettingsSequence, path: keyboardSettingsPath)
    let validatedKeyboardSettingsSequence = try validateKeyboardSettingsFeatureSequenceFile(keyboardSettingsPath, printSummary: verbose)
    try assertSelfTest(validatedKeyboardSettingsSequence == keyboardSettingsSequence, "keyboard settings validation returns original sequence")
    let keyboardSettingsFileOptions = try parseUnsafeCandidateFileOptions([keyboardSettingsPath, unsafeKeymapFlag, "--write-index=6"], kind: "keyboard settings")
    try assertSelfTest(keyboardSettingsFileOptions.path == keyboardSettingsPath && keyboardSettingsFileOptions.writeIndex == 6, "keyboard settings apply option parsing")
    try expectInvalidArgument("keyboard settings duplicate offset") {
        _ = try parseKeyboardSettingsAssignmentSpecs(["gamemode=on", "0x01=02"])
    }
    try expectInvalidArgument("keyboard settings marker guard") {
        _ = try parseKeyboardSettingsAssignmentSpecs(["0x3E=01"])
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

func runDoctor(openCheck: Bool) throws {
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

func readinessReport(openCheck: Bool) -> String {
    var lines: [String] = []
    func add(_ line: String = "") {
        lines.append(line)
    }

    add("GMK67 driver readiness")
    add("No HID reports are sent by this command.")
    add("")

    var hardFailures: [String] = []
    var warnings: [String] = []
    let inputMonitoringGranted = CGPreflightListenEventAccess()

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
        add("  RGB tables, profiles, keymap sequences, short-op/settings candidates, candidate lighting artifacts, and macro firmware containers validate locally.")
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
            add("Input Monitoring preflight: \(inputMonitoringGranted ? "GRANTED" : "NOT GRANTED")")
            if let index = likelyIndices.first {
                do {
                    _ = try driver.device(at: index, configurationOnly: false)
                    add("macOS HID open permission: OK")
                    add("  opened scan index \(index)")
                } catch {
                    add("macOS HID open permission: FAIL")
                    add("  \(error)")
                    if inputMonitoringGranted {
                        add("  Input Monitoring preflight is granted, but IOHID still refused the open.")
                        add("  Quit/reopen the app or launcher, reconnect the keyboard, and grant the parent app/terminal if macOS lists it separately.")
                        warnings.append("Input Monitoring preflight is granted but IOHID open is still denied")
                    } else {
                        warnings.append("macOS may need Input Monitoring permission for the terminal/app")
                    }
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
    add("  Candidate short lighting/profile operation: export/validate implemented, live writes guarded.")
    add("  Candidate keyboard/settings payload: export/validate implemented, live writes guarded.")
    add("  Candidate lighting/custom-table operations: export/validate implemented, live writes guarded.")
    add("  Candidate macro firmware table container: export/validate implemented, live writes guarded.")
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

func printProtocolCandidates() {
    print(protocolCandidatesText())
}

func windowsFeatureInventoryText() -> String {
    """
    GMK67 Windows software feature inventory

    Sources:
      BOYI GMK67 Driver V1.5 and Zuoya GMK67 Keyboard Setup extracted with innoextract.
      DeviceDriver.exe imports HidD_SetFeature/GetFeature and stores editor state in local SQLite tables.
      The English language resource and embedded SQLite schema identify these UI feature groups.

    Implemented with proven live RGB path:
      - Per-key static RGB readback/write through 04 F5, 04 20, and 04 02.
      - RGB save, restore, backups, built-in presets, and combined profile RGB sections.

    Implemented as app-local profile/library features:
      - Configuration profiles, import/export, rename/delete through JSON profile libraries.
      - Macro Manager JSON profiles with key, down, up, delay, text, repeat count, and library bundles.
      - Keymap profile/library JSON artifacts and combined app-library backup/restore.

    Implemented as guarded protocol candidates:
      - Custom key remapping via 04 18 / 04 11 table sequence.
      - Alternate full table via 04 18 / 04 27 table sequence.
      - Keyboard/settings payload via 04 18 / 04 17 / payload / 04 02, including named gamemode, Alt-Tab, Alt-F4, Win-key, Fn-switch, and sleep-light fields.
      - Custom lighting RGB via 04 18 / 04 23 selector 09 table sequence.
      - Per-key lighting-mode/effect table via 04 18 / 04 23 selector 03.
      - Short lighting/profile operation via 04 18 / 04 13 / payload / 04 02 / 04 F0.
      - Macro firmware table container via 04 19 / 04 15 / 04 02 template and validator.

    Windows UI feature groups not fully mapped to safe live firmware writes yet:
      - Board-side macro event encoding/readback.
      - High-level animated effect selection beyond candidate selector-03 tables.
      - Brightness, speed, and direction opcodes beyond the currently modeled RGB/lighting tables.
      - Open program, open website, send text, switch configuration, and multi-key action records.
      - Device-side profile save/load/readback and true vendor factory reset opcode.
      - Mouse-only panels from the shared driver shell: DPI, report rate, wheel speed, and pointer settings.

    Persistence finding:
      The Windows static RGB write path observed at VA 0x418500 and 0x425E03 sends 04 20,
      writes table chunks, then sends 04 02. No separate RGB save-to-flash opcode has been
      proven on that path. The Windows profile persistence visible in strings is primarily
      local SQLite state; firmware persistence still needs physical reboot validation.
    """
}

func protocolCandidatesText() -> String {
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
        status:  template export/validate implemented; live writes guarded

      Keyboard/settings payload
        begin:   04 18
        select:  04 17, byte2 = profile byte, byte8 = 01
        payload: one 64-byte report; known offsets are gamemode=0x01, disable_alttab=0x02,
                 disable_altf4=0x03, disable_win=0x04, fn_switchfunction=0x05,
                 sleep_light=0x06; AA 55 marker at payload offsets 0x3E...0x3F
        commit:  04 02
        status:  named/raw export and validate implemented; live writes guarded

      Custom lighting mode table
        begin:   04 18
        select:  04 23, byte8 = 03 or 09 depending on board mode
        table:   selector 03 declares 0x100 bytes; AA 55 marker at table offset 0xBE
        commit:  04 02
        finish:  04 F0
        status:  selector 03 export/validate and Windows-named effect artifacts implemented; live writes guarded

      Macro firmware table container
        begin:   04 19
        select:  04 15, byte8 = table chunk count
        table:   variable count of 64-byte reports; observed empty/minimum container uses 8 chunks
        commit:  04 02
        status:  zeroed template export/validate implemented; event encoding remains unmapped

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

func validationPlanText() -> String {
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

func diagnosticsReport() -> String {
    var lines: [String] = []
    func add(_ line: String = "") {
        lines.append(line)
    }

    add("GMK67 diagnostics report")
    add("Generated: \(ISO8601DateFormatter().string(from: Date()))")
    add(String(format: "Target VID:PID: %04X:%04X", GMK67.vendorID, GMK67.productID))
    add("Input Monitoring preflight: \(CGPreflightListenEventAccess() ? "GRANTED" : "NOT GRANTED")")
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

func layoutReportText() throws -> String {
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

func supportBundleSummaryText(directory: String) -> String {
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

func defaultSupportBundlePath() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "gmk67-support-\(formatter.string(from: Date()))"
}

func writeSupportBundle(directoryPath: String) throws {
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
