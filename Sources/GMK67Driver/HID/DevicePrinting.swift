import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func printDevices(_ devices: [HIDDeviceInfo]) {
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

func formatUsagePairs(_ pairs: [(page: Int, usage: Int)]) -> String {
    guard !pairs.isEmpty else { return "-" }
    return pairs
        .map { String(format: "%04X:%04X", $0.page, $0.usage) }
        .joined(separator: ", ")
}
