import SwiftUI
import AppKit
import Foundation

func rgbHex(_ color: Color) -> String {
    let nsColor = NSColor(color)
    guard let rgb = nsColor.usingColorSpace(.sRGB) else {
        return "000000"
    }

    let red = UInt8(max(0, min(255, Int((rgb.redComponent * 255).rounded()))))
    let green = UInt8(max(0, min(255, Int((rgb.greenComponent * 255).rounded()))))
    let blue = UInt8(max(0, min(255, Int((rgb.blueComponent * 255).rounded()))))
    return String(format: "%02X%02X%02X", red, green, blue)
}

func colorFromHex(_ hex: String) -> Color {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
        return Color(nsColor: .separatorColor)
    }

    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
}

func colorForKey(_ key: String, in specs: String) -> String? {
    valueForSpecKey(key, in: specs).flatMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        return trimmed.count == 6 && Int(trimmed, radix: 16) != nil ? trimmed.uppercased() : nil
    }
}

func visualColorForKey(_ key: String, in specs: String, fillHex: String) -> String? {
    if let explicit = colorForKey(key, in: specs) {
        return explicit
    }

    let fill = fillHex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "").uppercased()
    guard fill.count == 6, Int(fill, radix: 16) != nil, fill != "000000" else {
        return nil
    }
    return fill
}
