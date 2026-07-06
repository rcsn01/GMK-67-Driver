import Foundation
import SwiftUI

struct VisualKey: Identifiable {
    let id = UUID()
    let spec: String
    let label: String
    let width: CGFloat
}

struct VisualKeyRow: Identifiable {
    let id = UUID()
    let keys: [VisualKey]
}

private func vk(_ spec: String, _ label: String? = nil, width: CGFloat = 38) -> VisualKey {
    VisualKey(spec: spec, label: label ?? spec, width: width)
}

let visualKeyboardRows: [VisualKeyRow] = [
    VisualKeyRow(keys: [
        vk("esc", width: 38), vk("1"), vk("2"), vk("3"), vk("4"), vk("5"), vk("6"), vk("7"),
        vk("8"), vk("9"), vk("0"), vk("-"), vk("equal", "=", width: 38), vk("backspace", "backspace", width: 86)
    ]),
    VisualKeyRow(keys: [
        vk("tab", width: 60), vk("Q"), vk("W"), vk("E"), vk("R"), vk("T"), vk("Y"), vk("U"),
        vk("I"), vk("O"), vk("P"), vk("["), vk("]"), vk("\\|", "\\|", width: 64), vk("del")
    ]),
    VisualKeyRow(keys: [
        vk("Caps", width: 70), vk("A"), vk("S"), vk("D"), vk("F"), vk("G"), vk("H"), vk("J"),
        vk("K"), vk("L"), vk(";"), vk("quote", "'\"", width: 38), vk("enter", width: 96), vk("pageup", "pg up")
    ]),
    VisualKeyRow(keys: [
        vk("0x49", "shift", width: 94), vk("Z"), vk("X"), vk("C"), vk("V"), vk("B"), vk("N"), vk("M"),
        vk("comma", "<"), vk("period", ">"), vk("slash", "?"), vk("0x54", "shift", width: 70), vk("up", "up"), vk("pagedown", "pg dn")
    ]),
    VisualKeyRow(keys: [
        vk("control", "ctrl", width: 48), vk("win", width: 48), vk("0x5D", "alt", width: 48),
        vk("space", width: 286), vk("0x5F", "alt", width: 48), vk("fn", width: 48),
        vk("left", "left"), vk("down", "down"), vk("right", "right")
    ])
]

private let visualKeySpecsByToken: [String: String] = {
    var specs: [String: String] = [:]
    for row in visualKeyboardRows {
        for key in row.keys {
            specs[specKeyToken(key.spec)] = key.spec
        }
    }
    return specs
}()

private let visualKeyLabelsByToken: [String: String] = {
    var labels: [String: String] = [:]
    for row in visualKeyboardRows {
        for key in row.keys {
            labels[specKeyToken(key.spec)] = key.label
        }
    }
    return labels
}()

private let visualKeyOrderByToken: [String: Int] = {
    var order: [String: Int] = [:]
    var index = 0
    for row in visualKeyboardRows {
        for key in row.keys {
            order[specKeyToken(key.spec)] = index
            index += 1
        }
    }
    return order
}()

private let visualKeySpecByLightIndex: [Int: String] = [
    0x01: "esc",
    0x14: "1", 0x15: "2", 0x16: "3", 0x17: "4", 0x18: "5", 0x19: "6", 0x1A: "7",
    0x1B: "8", 0x1C: "9", 0x1D: "0", 0x1E: "-", 0x1F: "equal", 0x67: "backspace",
    0x25: "tab", 0x26: "Q", 0x27: "W", 0x28: "E", 0x29: "R", 0x2A: "T", 0x2B: "Y",
    0x2C: "U", 0x2D: "I", 0x2E: "O", 0x2F: "P", 0x30: "[", 0x31: "]", 0x43: "\\|", 0x77: "del",
    0x37: "Caps", 0x38: "A", 0x39: "S", 0x3A: "D", 0x3B: "F", 0x3C: "G", 0x3D: "H",
    0x3E: "J", 0x3F: "K", 0x40: "L", 0x41: ";", 0x42: "quote", 0x55: "enter", 0x76: "pageup",
    0x49: "0x49", 0x4A: "Z", 0x4B: "X", 0x4C: "C", 0x4D: "V", 0x4E: "B", 0x4F: "N",
    0x50: "M", 0x51: "comma", 0x52: "period", 0x53: "slash", 0x54: "0x54", 0x65: "up", 0x79: "pagedown",
    0x5B: "control", 0x5C: "win", 0x5D: "0x5D", 0x5E: "space", 0x5F: "0x5F", 0x60: "fn",
    0x63: "left", 0x64: "down", 0x66: "right"
]

private let inputNameToVisualKeySpec: [String: String] = {
    let pairs = [
        ("escape", "esc"),
        ("esc", "esc"),
        ("caps", "Caps"),
        ("capslock", "Caps"),
        ("delete", "del"),
        ("del", "del"),
        ("pageup", "pageup"),
        ("page up", "pageup"),
        ("pagedown", "pagedown"),
        ("page down", "pagedown"),
        ("arrowup", "up"),
        ("up", "up"),
        ("arrowdown", "down"),
        ("down", "down"),
        ("arrowleft", "left"),
        ("left", "left"),
        ("arrowright", "right"),
        ("right", "right"),
        ("equal", "equal"),
        ("equals", "equal"),
        ("=", "equal"),
        ("minus", "-"),
        ("dash", "-"),
        ("-", "-"),
        ("leftbracket", "["),
        ("lbracket", "["),
        ("[", "["),
        ("rightbracket", "]"),
        ("rbracket", "]"),
        ("]", "]"),
        ("backslash", "\\|"),
        ("pipe", "\\|"),
        ("\\|", "\\|"),
        ("semicolon", ";"),
        (";", ";"),
        ("quote", "quote"),
        ("apostrophe", "quote"),
        ("'\"", "quote"),
        ("comma", "comma"),
        ("<", "comma"),
        ("period", "period"),
        ("dot", "period"),
        (">", "period"),
        ("slash", "slash"),
        ("?", "slash"),
        ("left-control", "control"),
        ("left-ctrl", "control"),
        ("control", "control"),
        ("ctrl", "control"),
        ("left-shift", "0x49"),
        ("right-shift", "0x54"),
        ("left-alt", "0x5D"),
        ("right-alt", "0x5F"),
        ("left-option", "0x5D"),
        ("right-option", "0x5F"),
        ("left-command", "win"),
        ("left-cmd", "win"),
        ("command", "win"),
        ("cmd", "win")
    ]
    return Dictionary(uniqueKeysWithValues: pairs.map { (specKeyToken($0.0), $0.1) })
}()

func visualKeySpec(forInputName name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let token = specKeyToken(trimmed)
    if let mapped = inputNameToVisualKeySpec[token] {
        return mapped
    }
    if let exact = visualKeySpecsByToken[token] {
        return exact
    }
    if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
        return trimmed.uppercased()
    }
    return nil
}

func visualKeySpec(forLightIndex lightIndex: Int, keyName: String?) -> String? {
    if let mapped = visualKeySpecByLightIndex[lightIndex] {
        return mapped
    }
    if let keyName, let mapped = visualKeySpec(forInputName: keyName) {
        return mapped
    }
    return nil
}

func visualKeyIsPressed(_ spec: String, in pressedKeys: Set<String>) -> Bool {
    let token = specKeyToken(spec)
    return pressedKeys.contains { specKeyToken($0) == token }
}

func visualKeyStatusText(for pressedKeys: Set<String>) -> String {
    guard !pressedKeys.isEmpty else { return "No keys pressed" }
    let labels = pressedKeys
        .sorted { lhs, rhs in
            let lhsOrder = visualKeyOrderByToken[specKeyToken(lhs)] ?? Int.max
            let rhsOrder = visualKeyOrderByToken[specKeyToken(rhs)] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        .map { visualKeyLabelsByToken[specKeyToken($0)] ?? $0 }
    return "Pressed: \(labels.joined(separator: " + "))"
}
