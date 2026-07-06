import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func ioReturnName(_ code: IOReturn) -> String {
    switch code {
    case kIOReturnSuccess: return "success"
    case kIOReturnNotOpen: return "not open"
    case kIOReturnNotPermitted: return "not permitted"
    case kIOReturnNoDevice: return "no device"
    case kIOReturnExclusiveAccess: return "exclusive access"
    default: return String(format: "0x%08X", code)
    }
}
