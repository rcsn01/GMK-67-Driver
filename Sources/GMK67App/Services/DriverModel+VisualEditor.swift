import Foundation

@MainActor
extension DriverModel {
    func selectVisualKey(_ key: String) {
        selectedVisualKey = key
        keyName = key
        sourceKey = key
        if let selectedColor = visualColorHex(for: key) {
            colorHex = selectedColor
            keyColor = colorFromHex(selectedColor)
        } else if currentRGBReadbackLoaded {
            colorHex = "000000"
            keyColor = .black
        }
        if let remap = remapForKey(key, in: keymapSpecs) {
            targetKey = remap.target
            modifierKey = remap.modifier ?? ""
        }
    }

    func assignSelectedKeyColor() {
        let key = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let sanitizedColor = normalizedRGBHex(colorHex) ?? "000000"
        colorHex = sanitizedColor
        keyColor = colorFromHex(sanitizedColor)
        mapSpecs = upsertSpec(mapSpecs, key: key, value: sanitizedColor)
        keyName = key
        combinedProfileIncludesRGBMap = true
    }

    func clearSelectedKeyColor() {
        let key = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        mapSpecs = removeSpec(mapSpecs, key: key)
    }

    func assignSelectedKeyRemap() {
        let source = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targetKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else { return }
        let modifier = modifierKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = modifier.isEmpty ? target : "\(target):\(modifier)"
        keymapSpecs = upsertSpec(keymapSpecs, key: source, value: value)
        sourceKey = source
        combinedProfileIncludesKeymapSpecs = true
    }

    func clearSelectedKeyRemap() {
        let key = selectedVisualKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keymapSpecs = removeSpec(keymapSpecs, key: key)
        if sourceKey.caseInsensitiveCompare(key) == .orderedSame {
            targetKey = ""
            modifierKey = ""
        }
    }
}
