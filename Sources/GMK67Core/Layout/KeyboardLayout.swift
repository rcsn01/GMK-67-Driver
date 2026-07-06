import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func loadKeyboardLayout() throws -> [KeyItem] {
    var candidates: [URL] = []

    func appendResourceCandidates(from baseURL: URL) {
        candidates.append(baseURL.appendingPathComponent("Resources/vendor/KeyboardLayout.xml"))
        candidates.append(baseURL.appendingPathComponent("vendor/KeyboardLayout.xml"))
    }

    if let resourceDirectory = ProcessInfo.processInfo.environment["GMK67_RESOURCES_DIR"], !resourceDirectory.isEmpty {
        appendResourceCandidates(from: URL(fileURLWithPath: resourceDirectory))
    }

    if let resourceURL = Bundle.main.resourceURL {
        appendResourceCandidates(from: resourceURL)
    }

    if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
        var directory = executableDirectory
        for _ in 0..<6 {
            appendResourceCandidates(from: directory)
            directory.deleteLastPathComponent()
        }
    }

    var currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        appendResourceCandidates(from: currentDirectory)
        currentDirectory.deleteLastPathComponent()
    }

    appendResourceCandidates(
        from: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    )

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

func parseAttributes(_ line: String) -> [String: String] {
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

func isAttributeStart(_ character: Character) -> Bool {
    character == "_" || character.isLetter
}

func isAttributeName(_ character: Character) -> Bool {
    character == "_" || character.isLetter || character.isNumber
}

func xmlUnescape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
}

let bootModifierNames: [(mask: UInt8, name: String)] = [
    (0x01, "left-control"),
    (0x02, "left-shift"),
    (0x04, "left-alt"),
    (0x08, "left-command"),
    (0x10, "right-control"),
    (0x20, "right-shift"),
    (0x40, "right-alt"),
    (0x80, "right-command")
]

func keyboardUsageNamesByCode() throws -> [UInt8: String] {
    var names: [UInt8: String] = [:]
    for key in try loadKeyboardLayout() where key.code >= 0 && key.code <= 0xFF {
        names[UInt8(key.code)] = key.name
    }
    for (usage, name) in preferredHIDUsageNames {
        names[usage] = name
    }
    for (name, usage) in hidUsageAliases where names[usage] == nil {
        names[usage] = name
    }
    for modifier in bootModifierNames.enumerated() {
        names[UInt8(0xE0 + modifier.offset)] = modifier.element.name
    }
    return names
}

func pressedKeyNamesFromBootKeyboardReport(_ bytes: [UInt8], usageNames: [UInt8: String]) -> Set<String>? {
    let report = bytes.count >= 9 && bytes[0] == 0 ? Array(bytes.dropFirst()) : bytes
    guard report.count >= 8 else { return nil }

    let modifierByte = report[0]
    let modifiers = bootModifierNames.compactMap { modifierByte & $0.mask == 0 ? nil : $0.name }
    let usages = report[2..<min(report.count, 8)].filter { $0 != 0 && $0 != 1 }
    let keyNames = usages.map { usage -> String in
        usageNames[usage] ?? String(format: "0x%02X", usage)
    }

    return Set(modifiers + keyNames)
}

func decodeBootKeyboardReport(_ bytes: [UInt8], usageNames: [UInt8: String]) -> String? {
    guard let pressedKeys = pressedKeyNamesFromBootKeyboardReport(bytes, usageNames: usageNames) else { return nil }
    if pressedKeys.isEmpty {
        return "release"
    }

    var parts: [String] = []
    let modifiers = bootModifierNames.map(\.name).filter { pressedKeys.contains($0) }
    if !modifiers.isEmpty {
        parts.append("mods=\(modifiers.joined(separator: "+"))")
    }
    let keyNames = pressedKeys
        .filter { !modifiers.contains($0) }
        .sorted()
    if !keyNames.isEmpty {
        parts.append("keys=\(keyNames.joined(separator: "+"))")
    }
    return parts.joined(separator: " ")
}
