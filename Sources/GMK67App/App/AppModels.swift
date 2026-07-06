import Foundation
import GMK67Core

struct AppProfileLibraryEntry: Codable, Identifiable {
    let slot: String
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let customRGB: Int
    let customRemaps: Int

    var id: String { slot }
    var summary: String {
        let keymap = keymapPreset ?? "-"
        return "rgb=\(rgbPreset) keymap=\(keymap) custom-rgb=\(customRGB) custom-remaps=\(customRemaps)"
    }
}

struct AppCombinedProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let rgbFill: String?
    let rgbAssignments: [String]?
    let keymapRemaps: [String]?
}

struct AppMacroLibraryEntry: Codable, Identifiable {
    let slot: String
    let name: String
    let repeatCount: Int
    let eventCount: Int

    var id: String { slot }
}

struct AppKeymapLibraryEntry: Codable, Identifiable {
    let slot: String
    let name: String
    let remapCount: Int

    var id: String { slot }
}

struct AppKeymapProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let remaps: [String]
}

struct AppRGBPreset: Codable {
    let name: String
    let title: String
    let description: String
    let fill: String
    let assignments: [String]
}

struct AppKeymapPreset: Codable {
    let name: String
    let title: String
    let description: String
    let remaps: [String]
}

struct AppMacroProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let repeatCount: Int
    let events: [AppMacroEvent]
}

struct AppMacroEvent: Codable {
    let type: String
    let key: String?
    let usage: String?
    let text: String?
    let delayMS: Int?
}

typealias AppRGBRecord = RGBRecord
typealias AppRGBLightReadback = RGBLightReadback

struct AppKeymapRecord: Codable {
    let offset: Int
    let keyIndex: Int
    let source: String?
    let target: String
    let targetUsage: String
    let targetEncoded: String
    let modifier: String?
    let modifierUsage: String?
    let modifierEncoded: String
    let record: String
    let spec: String?
    let warning: String?
}

struct AppByteRecord: Codable {
    let offset: Int
    let key: String?
    let value: String
    let spec: String?
}
