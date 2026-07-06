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

func normalizedRGBHex(_ hex: String) -> String? {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard trimmed.count == 6, Int(trimmed, radix: 16) != nil else {
        return nil
    }
    return trimmed.uppercased()
}

func displayRGBHex(fromHardwareReadback hex: String) -> String? {
    guard let normalized = normalizedRGBHex(hex), let value = Int(normalized, radix: 16) else {
        return nil
    }

    var red = Double((value >> 16) & 0xFF)
    var green = Double((value >> 8) & 0xFF)
    var blue = Double(value & 0xFF)
    let maximum = max(red, green, blue)
    guard maximum > 0 else { return "000000" }

    let minimum = min(red, green, blue)
    let isNearNeutral = (maximum - minimum) / maximum < 0.12
    if isNearNeutral {
        return "FFFFFF"
    }

    // The keyboard reports PWM-like channel values, not display-ready sRGB.
    // On observed yellow LEDs, green is reported at roughly half red.
    if blue / maximum < 0.12, green > 0, red / green >= 1.6, red / green <= 2.4 {
        green = red
    }

    let displayMaximum = max(red, green, blue)
    let scale = 255.0 / displayMaximum
    red = min(255, red * scale)
    green = min(255, green * scale)
    blue = min(255, blue * scale)
    return String(format: "%02X%02X%02X", Int(red.rounded()), Int(green.rounded()), Int(blue.rounded()))
}
