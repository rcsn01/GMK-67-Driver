import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

enum GMK67 {
    static let vendorID = 0x05AC
    static let productID = 0x024F
    static let usagePage = 0xFFFF
    static let usage = 0x0001
    static let productName = "USB DEVICE"
}

struct KeyItem {
    let code: Int
    let name: String
    let desc: String
    let keyIndex: Int
    let lightIndex: Int
}

struct KeymapRemap {
    let source: KeyItem
    let targetUsage: UInt8
    let modifierUsage: UInt8?
}

struct KeymapProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let remaps: [String]
}

struct KeymapLibraryListItem: Codable {
    let slot: String
    let name: String
    let remapCount: Int
}

struct KeymapLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profiles: [KeymapLibraryBundleEntry]
}

struct KeymapLibraryBundleEntry: Codable {
    let slot: String
    let profile: KeymapProfile
}

struct RGBAssignment {
    let lightIndex: Int
    let label: String
    let color: [UInt8]
}

struct ByteAssignment {
    let index: Int
    let label: String
    let value: UInt8
}

struct RGBPresetDefinition: Codable {
    let name: String
    let title: String
    let description: String
    let fill: String
    let assignments: [String]
}

struct RGBLayoutPresetDefinition: Codable {
    let name: String
    let title: String
    let description: String
    let fillRole: String
    let assignments: [String]
}

struct RGBColorThemeDefinition: Codable {
    let name: String
    let title: String
    let description: String
    let colors: [String: String]
}

struct KeymapPresetDefinition: Codable {
    let name: String
    let title: String
    let description: String
    let remaps: [String]
}

struct LightingModePresetDefinition {
    let name: String
    let title: String
    let description: String
    let assignments: [String]
}

struct LightingEffectDefinition {
    let name: String
    let title: String
    let value: UInt8
    let colorType: UInt8
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let byte5: UInt8
    let byte6: UInt8
    let byte7: UInt8
    var aliases: [String] = []
    var summary: String = ""
}

struct CombinedProfilePresetDefinition {
    let name: String
    let title: String
    let description: String
    let rgbPreset: String
    let keymapPreset: String?
}

struct CombinedProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let rgbFill: String?
    let rgbAssignments: [String]?
    let keymapRemaps: [String]?

    init(
        format: String,
        version: Int,
        name: String,
        rgbPreset: String,
        keymapPreset: String?,
        rgbFill: String? = nil,
        rgbAssignments: [String]? = nil,
        keymapRemaps: [String]? = nil
    ) {
        self.format = format
        self.version = version
        self.name = name
        self.rgbPreset = rgbPreset
        self.keymapPreset = keymapPreset
        self.rgbFill = rgbFill
        self.rgbAssignments = rgbAssignments
        self.keymapRemaps = keymapRemaps
    }
}

struct MacroProfile: Codable {
    let format: String
    let version: Int
    let name: String
    let repeatCount: Int
    let events: [MacroEvent]
}

struct MacroEvent: Codable {
    let type: String
    let key: String?
    let usage: String?
    let text: String?
    let delayMS: Int?
}

struct MacroLibraryListItem: Codable {
    let slot: String
    let name: String
    let repeatCount: Int
    let eventCount: Int
}

struct MacroLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let macros: [MacroLibraryBundleEntry]
}

struct MacroLibraryBundleEntry: Codable {
    let slot: String
    let macro: MacroProfile
}

struct ProfileLibraryListItem: Codable {
    let slot: String
    let name: String
    let rgbPreset: String
    let keymapPreset: String?
    let customRGB: Int
    let customRemaps: Int
}

struct ProfileLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profiles: [ProfileLibraryBundleEntry]
}

struct ProfileLibraryBundleEntry: Codable {
    let slot: String
    let profile: CombinedProfile
}

struct AppLibraryBundle: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profiles: [ProfileLibraryBundleEntry]
    let keymaps: [KeymapLibraryBundleEntry]
    let macros: [MacroLibraryBundleEntry]
}

public struct RGBRecord: Codable, Sendable {
    public let chunk: Int
    public let offset: Int
    public let index: Int
    public let key: String?
    public let spec: String?
    public let rgb: String

    public init(chunk: Int, offset: Int, index: Int, key: String?, spec: String? = nil, rgb: String) {
        self.chunk = chunk
        self.offset = offset
        self.index = index
        self.key = key
        self.spec = spec
        self.rgb = rgb
    }
}

typealias RGBRecordJSON = RGBRecord

public struct RGBLightReadback: Sendable {
    public let lightIndex: Int
    public let keyName: String?
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(lightIndex: Int, keyName: String?, red: UInt8, green: UInt8, blue: UInt8) {
        self.lightIndex = lightIndex
        self.keyName = keyName
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var isLit: Bool {
        red != 0 || green != 0 || blue != 0
    }

    public var rgbHex: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

struct KeymapRecordJSON: Codable {
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

struct ByteRecordJSON: Codable {
    let offset: Int
    let key: String?
    let value: String
    let spec: String?
}

struct RGBBackupFile {
    let url: URL
    let frameCount: Int
}

struct HIDDeviceInfo {
    let device: IOHIDDevice
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int
    let primaryUsagePage: Int
    let primaryUsage: Int
    let usagePairs: [(page: Int, usage: Int)]
    let product: String
    let manufacturer: String
    let serial: String
    let maxFeatureReportSize: Int
    let maxInputReportSize: Int
    let maxOutputReportSize: Int

    var isLikelyConfigurationInterface: Bool {
        maxFeatureReportSize >= 64 ||
            usagePairs.contains { $0.page == GMK67.usagePage && $0.usage == GMK67.usage } ||
            (primaryUsagePage == GMK67.usagePage && primaryUsage == GMK67.usage)
    }
}

let unsafeKeymapFlag = "--unsafe-no-backup"
let rgbBackupPrefix = ".gmk67-rgb-backup-"
let rgbBackupSuffix = ".hex"
