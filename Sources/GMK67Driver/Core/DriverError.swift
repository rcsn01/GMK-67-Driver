import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

enum DriverError: Error, CustomStringConvertible {
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
                return "Could not open HID device: not permitted. On macOS, grant Input Monitoring permission to the process running gmk67 (GMK67.app/helper, Terminal, Cursor, or Codex), then reconnect the keyboard and retry."
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
