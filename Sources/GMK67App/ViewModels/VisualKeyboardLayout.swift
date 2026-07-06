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
