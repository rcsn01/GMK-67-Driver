import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func parseHexBytes(_ text: String) throws -> [UInt8] {
    let cleaned = text
        .replacingOccurrences(of: "0x", with: "")
        .replacingOccurrences(of: ",", with: " ")
        .replacingOccurrences(of: ":", with: " ")
        .replacingOccurrences(of: "-", with: " ")
    let chunks = cleaned.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
    if chunks.count > 1 {
        return try chunks.map { chunk in
            guard let byte = UInt8(chunk, radix: 16) else { throw DriverError.invalidHex(String(chunk)) }
            return byte
        }
    }
    guard let only = chunks.first else { return [] }
    let compact = String(only)
    guard compact.count % 2 == 0 else { throw DriverError.invalidHex(text) }
    var bytes: [UInt8] = []
    var index = compact.startIndex
    while index < compact.endIndex {
        let next = compact.index(index, offsetBy: 2)
        let part = compact[index..<next]
        guard let byte = UInt8(part, radix: 16) else { throw DriverError.invalidHex(String(part)) }
        bytes.append(byte)
        index = next
    }
    return bytes
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
