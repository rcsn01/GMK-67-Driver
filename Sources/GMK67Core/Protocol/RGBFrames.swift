import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func printRGBRecords(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) {
    for record in rgbRecordJSON(chunks, keyByLightIndex: keyByLightIndex, recordByteLimit: recordByteLimit) {
        let label = record.key.map { " key=\($0)" } ?? ""
        let specLabel = record.spec.flatMap { $0 == record.key ? nil : " spec=\($0)" } ?? ""
        let rgbBytes = try? parseHexBytes(record.rgb)
        if let rgbBytes, rgbBytes.count == 3 {
            print(String(
                format: "  chunk=%02d offset=%02d index=0x%02X%@%@ rgb=%02X %02X %02X",
                record.chunk,
                record.offset,
                record.index,
                label,
                specLabel,
                rgbBytes[0],
                rgbBytes[1],
                rgbBytes[2]
            ))
        }
    }
}

func rgbRecordJSON(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) -> [RGBRecordJSON] {
    let duplicateTokens = duplicateKeyNameTokens(Array(keyByLightIndex.values))
    return rgbLightReadbackRecords(chunks, keyByLightIndex: keyByLightIndex, recordByteLimit: recordByteLimit)
        .map { record in
            let key = keyByLightIndex[record.lightIndex]
            let spec = keyByLightIndex.isEmpty ? nil : parseableSpecTarget(
                for: key,
                offset: record.lightIndex,
                duplicateKeyTokens: duplicateTokens
            )
            return RGBRecordJSON(
                chunk: record.lightIndex / 16,
                offset: (record.lightIndex % 16) * 4,
                index: record.lightIndex,
                key: record.keyName,
                spec: spec,
                rgb: record.rgbHex
            )
        }
}

func printRGBRecordsJSON(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(rgbRecordJSON(chunks, keyByLightIndex: keyByLightIndex, recordByteLimit: recordByteLimit))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

func printByteTableRecords(_ chunks: [[UInt8]], byteLimit: Int, keyByLightIndex: [Int: KeyItem] = [:]) {
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

func parseableSpecTarget(for key: KeyItem?, offset: Int, duplicateKeyTokens: Set<String>) -> String {
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

func duplicateKeyNameTokens(_ keys: [KeyItem]) -> Set<String> {
    var counts: [String: Int] = [:]
    for key in keys {
        counts[keyLookupToken(key.name), default: 0] += 1
    }
    return Set(counts.filter { !$0.key.isEmpty && $0.value > 1 }.map(\.key))
}

func byteRecordJSON(_ chunks: [[UInt8]], byteLimit: Int, keyByLightIndex: [Int: KeyItem] = [:]) -> [ByteRecordJSON] {
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

func printByteRecordsJSON(_ chunks: [[UInt8]], byteLimit: Int, keyByLightIndex: [Int: KeyItem] = [:]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(byteRecordJSON(chunks, byteLimit: byteLimit, keyByLightIndex: keyByLightIndex))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

func rgbFramesToRecords(_ frames: [[UInt8]]) -> [Int: (red: UInt8, green: UInt8, blue: UInt8)] {
    var records: [Int: (red: UInt8, green: UInt8, blue: UInt8)] = [:]
    for (chunkIndex, bytes) in frames.enumerated() {
        var offset = 0
        while offset + 3 < bytes.count {
            let tableOffset = chunkIndex * 64 + offset
            let slotIndex = tableOffset / 4
            let encodedIndex = Int(bytes[offset])
            let lightIndex = encodedIndex == 0 ? slotIndex : encodedIndex
            records[lightIndex] = (bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
            offset += 4
        }
    }
    return records
}

func rgbLightReadbackRecords(_ chunks: [[UInt8]], keyByLightIndex: [Int: KeyItem] = [:], recordByteLimit: Int? = nil) -> [RGBLightReadback] {
    var records: [RGBLightReadback] = []
    for (chunkIndex, bytes) in chunks.enumerated() {
        var offset = 0
        while offset + 3 < bytes.count {
            let tableOffset = chunkIndex * 64 + offset
            if let recordByteLimit, tableOffset + 3 >= recordByteLimit {
                break
            }
            let slotIndex = tableOffset / 4
            let encodedIndex = Int(bytes[offset])
            let red = bytes[offset + 1]
            let green = bytes[offset + 2]
            let blue = bytes[offset + 3]
            if red != 0 || green != 0 || blue != 0 {
                let lightIndex: Int
                if keyByLightIndex.isEmpty {
                    lightIndex = encodedIndex == 0 ? slotIndex : encodedIndex
                } else if keyByLightIndex[encodedIndex] != nil {
                    lightIndex = encodedIndex
                } else if encodedIndex == 0, keyByLightIndex[slotIndex] != nil {
                    lightIndex = slotIndex
                } else {
                    offset += 4
                    continue
                }
                records.append(RGBLightReadback(
                    lightIndex: lightIndex,
                    keyName: keyByLightIndex[lightIndex]?.name,
                    red: red,
                    green: green,
                    blue: blue
                ))
            }
            offset += 4
        }
    }
    return records
}

func setRGBRecord(frames: inout [[UInt8]], lightIndex: Int, color: [UInt8]) throws {
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

func isRGBReadbackEchoFrame(_ frame: [UInt8]) -> Bool {
    frame.count >= 9 && frame[0] == 0x04 && frame[1] == 0xF5
}

func normalizedRGBTableFrames(_ frames: [[UInt8]]) -> [[UInt8]] {
    guard let first = frames.first, isRGBReadbackEchoFrame(first) else {
        return frames
    }
    return Array(frames.dropFirst())
}

enum RGBWriteMode {
    case persistentCustomLighting
    case legacyTable

    var description: String {
        switch self {
        case .persistentCustomLighting:
            return "native custom-lighting RGB path (04 23 selector 09, then 04 13 static-80 activation)"
        case .legacyTable:
            return "legacy static RGB table path (04 20 / table chunks / 04 02)"
        }
    }
}

func rgbFrameAssignments(from frames: [[UInt8]], recordByteLimit: Int = 0x23E) throws -> [RGBAssignment] {
    guard !frames.isEmpty, frames.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("RGB frames must be 64-byte tables.")
    }

    let keyMap = keyMapByLightIndex()
    var assignmentsByLightIndex: [Int: RGBAssignment] = [:]
    for (chunkIndex, bytes) in frames.enumerated() {
        var offset = 0
        while offset + 3 < bytes.count {
            let tableOffset = chunkIndex * 64 + offset
            guard tableOffset + 3 < recordByteLimit else {
                break
            }

            let slotIndex = tableOffset / 4
            let encodedIndex = Int(bytes[offset])
            let lightIndex = encodedIndex == 0 ? slotIndex : encodedIndex
            guard lightIndex * 4 + 3 < recordByteLimit else {
                offset += 4
                continue
            }

            assignmentsByLightIndex[lightIndex] = RGBAssignment(
                lightIndex: lightIndex,
                label: keyMap[lightIndex]?.name ?? String(format: "0x%02X", lightIndex),
                color: [bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]]
            )
            offset += 4
        }
    }

    return assignmentsByLightIndex.keys.sorted().compactMap { assignmentsByLightIndex[$0] }
}

func readRGBFrames(driver: HIDDriver, writeDevice: IOHIDDevice, readDevice: IOHIDDevice, chunks: Int = 9) throws -> [[UInt8]] {
    var readRequest = [UInt8](repeating: 0, count: 64)
    readRequest[0] = 0x04
    readRequest[1] = 0xF5
    readRequest[8] = UInt8(chunks)
    try driver.setVendorFeature64(device: writeDevice, payload: readRequest)

    var frames: [[UInt8]] = []
    for _ in 0..<chunks {
        usleep(50_000)
        frames.append(try driver.getInput(device: readDevice, reportID: 0, length: 64))
    }
    if ProcessInfo.processInfo.environment["GMK67_RAW_RGB_READBACK"] == "1" {
        return frames
    }
    return normalizedRGBTableFrames(frames)
}

public func readCurrentRGBRecords(writeIndex: Int = 0, readIndex: Int = 0, chunks: Int = 9) throws -> [RGBRecord] {
    let keyMap = keyMapByLightIndex()
    let duplicateTokens = duplicateKeyNameTokens(Array(keyMap.values))
    return try readCurrentRGBReadback(writeIndex: writeIndex, readIndex: readIndex, chunks: chunks).map { record in
        let key = keyMap[record.lightIndex]
        let spec = parseableSpecTarget(for: key, offset: record.lightIndex, duplicateKeyTokens: duplicateTokens)
        return RGBRecord(
            chunk: record.lightIndex / 16,
            offset: (record.lightIndex % 16) * 4,
            index: record.lightIndex,
            key: record.keyName,
            spec: spec,
            rgb: record.rgbHex
        )
    }
}

public func readCurrentRGBReadback(writeIndex: Int = 0, readIndex: Int = 0, chunks: Int = 9) throws -> [RGBLightReadback] {
    guard chunks > 0, chunks <= 9 else {
        throw DriverError.invalidArgument("RGB readback chunks must be between 1 and 9.")
    }

    let driver = HIDDriver()
    let devices = driver.devices()
    guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
        throw DriverError.noDevice
    }

    let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
    let readDevice = try driver.device(at: readIndex, configurationOnly: false)
    let frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice, chunks: chunks)
    return rgbLightReadbackRecords(frames, keyByLightIndex: keyMapByLightIndex())
}

func writeRGBFrames(driver: HIDDriver, writeDevice: IOHIDDevice, frames: [[UInt8]], mode: RGBWriteMode = .persistentCustomLighting) throws {
    switch mode {
    case .persistentCustomLighting:
        try writePersistentRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
    case .legacyTable:
        try writeLegacyRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
    }
}

private func writePersistentRGBFrames(driver: HIDDriver, writeDevice: IOHIDDevice, frames: [[UInt8]]) throws {
    let assignments = try rgbFrameAssignments(from: normalizedRGBTableFrames(frames))
    let table = try customLightingRGBTable(assignments: assignments)
    try sendFeatureSequence(driver: driver, device: writeDevice, payloads: try nativePersistentRGBFeatureSequence(table: table))
}

private func writeLegacyRGBFrames(driver: HIDDriver, writeDevice: IOHIDDevice, frames: [[UInt8]]) throws {
    let normalizedFrames = normalizedRGBTableFrames(frames)
    guard normalizedFrames.count >= 8, normalizedFrames.prefix(8).allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("RGB restore requires at least eight 64-byte frames.")
    }
    let tableFrames = Array(normalizedFrames.prefix(8))
    try driver.sendFeature64(device: writeDevice, bytes: [0x04, 0x20, 0, 0, 0, 0, 0, 0, 0x08])
    usleep(30_000)
    for frame in tableFrames {
        try driver.sendTableChunk64(device: writeDevice, payload: frame)
        usleep(30_000)
    }
    try driver.sendFeature64(device: writeDevice, bytes: [0x04, 0x02])
}

func writeRGBFramesFile(_ frames: [[UInt8]], path: String) throws {
    let text = frames.map(hex).joined(separator: "\n") + "\n"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func backupRGBFrames(_ frames: [[UInt8]]) throws -> String {
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

func readRGBFramesFile(_ path: String) throws -> [[UInt8]] {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let frames = try text
        .split(whereSeparator: \.isNewline)
        .map { try parseHexBytes(String($0)) }
    guard (frames.count == 8 || frames.count == 9), frames.allSatisfy({ $0.count == 64 }) else {
        throw DriverError.invalidArgument("RGB table file must contain 8 or 9 lines of 64 hex bytes.")
    }
    return frames
}

func rgbBackupFiles(directoryPath: String = ".") -> [RGBBackupFile] {
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

func latestRGBBackup(directoryPath: String = ".") throws -> RGBBackupFile {
    guard let latest = rgbBackupFiles(directoryPath: directoryPath).first else {
        throw DriverError.invalidArgument("No valid RGB backup files found in \(directoryPath).")
    }
    return latest
}
