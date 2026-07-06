import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func physicalKeysByLightIndex() -> [Int: KeyItem] {
    keyMapByLightIndex().filter { index, _ in
        (0...0x8F).contains(index)
    }
}

func keyMapByLightIndex() -> [Int: KeyItem] {
    guard let keys = try? loadKeyboardLayout() else { return [:] }
    return Dictionary(uniqueKeysWithValues: keys.map { ($0.lightIndex, $0) })
}
