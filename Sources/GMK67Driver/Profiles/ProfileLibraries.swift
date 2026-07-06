import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

func writeCombinedProfile(_ profile: CombinedProfile, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func readCombinedProfile(_ path: String) throws -> CombinedProfile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let profile = try JSONDecoder().decode(CombinedProfile.self, from: data)
    try validateCombinedProfile(profile)
    return profile
}

func validateCombinedProfile(_ profile: CombinedProfile) throws {
    guard profile.format == "gmk67-profile", profile.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 profile format/version.")
    }
    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DriverError.invalidArgument("Profile name must not be empty.")
    }
    _ = try rgbPreset(named: profile.rgbPreset)
    if let keymapPresetName = profile.keymapPreset, !keymapPresetName.isEmpty {
        _ = try keymapPreset(named: keymapPresetName)
    }
    if let rgbFill = profile.rgbFill {
        let fill = try parseHexBytes(rgbFill)
        guard fill.count == 3 else {
            throw DriverError.invalidArgument("Profile rgbFill must be exactly three bytes.")
        }
    }
    if let rgbAssignments = profile.rgbAssignments, !rgbAssignments.isEmpty {
        _ = try parseRGBAssignmentSpecs(rgbAssignments)
    }
    _ = try combinedProfileKeymapRemaps(profile)
}

func printCombinedProfile(_ profile: CombinedProfile) {
    print("Profile: \(profile.name)")
    print("  RGB preset: \(profile.rgbPreset)")
    print("  Keymap preset: \(profile.keymapPreset ?? "-")")
    if let rgbFill = profile.rgbFill {
        print("  RGB fill: \(rgbFill)")
    }
    if let rgbAssignments = profile.rgbAssignments, !rgbAssignments.isEmpty {
        print("  RGB assignments: \(rgbAssignments.joined(separator: " "))")
    }
    if let keymapRemaps = profile.keymapRemaps, !keymapRemaps.isEmpty {
        print("  Keymap remaps: \(keymapRemaps.joined(separator: " "))")
    }
}

func combinedProfileRGBFrames(_ profile: CombinedProfile) throws -> [[UInt8]] {
    var frames: [[UInt8]]
    if let rgbFill = profile.rgbFill {
        let fillColor = try parseHexBytes(rgbFill)
        frames = sampleRGBFrames()
        try applyRGBFill(fillColor, to: &frames, keyMap: physicalKeysByLightIndex())
    } else {
        frames = try rgbPresetFrames(try rgbPreset(named: profile.rgbPreset))
    }

    if let rgbAssignments = profile.rgbAssignments, !rgbAssignments.isEmpty {
        let assignments = try parseRGBAssignmentSpecs(rgbAssignments)
        try applyRGBAssignments(assignments, to: &frames)
    }
    return frames
}

func combinedProfileKeymapRemaps(_ profile: CombinedProfile) throws -> [KeymapRemap] {
    var specs: [String] = []
    if let keymapPresetName = profile.keymapPreset, !keymapPresetName.isEmpty {
        specs += try keymapPreset(named: keymapPresetName).remaps
    }
    if let keymapRemaps = profile.keymapRemaps {
        specs += keymapRemaps
    }
    guard !specs.isEmpty else { return [] }
    let remaps = try parseKeymapRemapSpecs(specs)
    _ = try keymapRemapTable(remaps)
    return remaps
}

func combinedProfileHasKeymap(_ profile: CombinedProfile) -> Bool {
    if let keymapPreset = profile.keymapPreset, !keymapPreset.isEmpty {
        return true
    }
    return !(profile.keymapRemaps ?? []).isEmpty
}

func parseProfileCreateOptions(_ args: [String]) throws -> (path: String, profile: CombinedProfile) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("profile-create requires a path.")
    }
    var name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var rgbPresetName = "wasd"
    var keymapPresetName: String?
    var rgbFill: String?
    var rgbAssignments: [String] = []
    var keymapRemaps: [String] = []

    for argument in args.dropFirst() {
        if argument.hasPrefix("--name=") {
            name = String(argument.dropFirst("--name=".count))
        } else if argument.hasPrefix("--rgb=") {
            rgbPresetName = String(argument.dropFirst("--rgb=".count))
        } else if argument.hasPrefix("--keymap=") {
            let value = String(argument.dropFirst("--keymap=".count))
            keymapPresetName = value.isEmpty || value == "-" || value.lowercased() == "none" ? nil : value
        } else if argument.hasPrefix("--rgb-fill=") {
            rgbFill = String(argument.dropFirst("--rgb-fill=".count))
        } else if argument.hasPrefix("--remap=") {
            let value = String(argument.dropFirst("--remap=".count))
            guard !value.isEmpty else {
                throw DriverError.invalidArgument("Empty --remap option in profile-create.")
            }
            keymapRemaps.append(value)
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown profile-create option: \(argument)")
        } else {
            rgbAssignments.append(argument)
        }
    }

    let profile = CombinedProfile(
        format: "gmk67-profile",
        version: 1,
        name: name,
        rgbPreset: rgbPresetName,
        keymapPreset: keymapPresetName,
        rgbFill: rgbFill,
        rgbAssignments: rgbAssignments.isEmpty ? nil : rgbAssignments,
        keymapRemaps: keymapRemaps.isEmpty ? nil : keymapRemaps
    )
    try validateCombinedProfile(profile)
    return (path, profile)
}

func parseProfileLibraryCreateOptions(_ args: [String]) throws -> CombinedProfile {
    let parsed = try parseProfileCreateOptions(["profile"] + args)
    return parsed.profile
}

func parseKeymapProfileCreateOptions(_ args: [String]) throws -> (path: String, profile: KeymapProfile) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("keymap-profile-create requires a path.")
    }
    var name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var remaps: [String] = []

    for argument in args.dropFirst() {
        if argument.hasPrefix("--name=") {
            name = String(argument.dropFirst("--name=".count))
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown keymap-profile-create option: \(argument)")
        } else {
            remaps.append(argument)
        }
    }

    let profile = KeymapProfile(format: "gmk67-keymap-profile", version: 1, name: name, remaps: remaps)
    try validateKeymapProfile(profile)
    return (path, profile)
}

func parseKeymapLibraryCreateOptions(_ args: [String]) throws -> KeymapProfile {
    let parsed = try parseKeymapProfileCreateOptions(["keymap-profile"] + args)
    return parsed.profile
}

func validateKeymapProfile(_ profile: KeymapProfile) throws {
    guard profile.format == "gmk67-keymap-profile", profile.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 keymap profile format/version.")
    }
    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DriverError.invalidArgument("Keymap profile name must not be empty.")
    }
    let remaps = try parseKeymapRemapSpecs(profile.remaps)
    _ = try keymapRemapTable(remaps)
}

func writeKeymapProfile(_ profile: KeymapProfile, path: String) throws {
    try validateKeymapProfile(profile)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func readKeymapProfile(_ path: String) throws -> KeymapProfile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let profile = try JSONDecoder().decode(KeymapProfile.self, from: data)
    try validateKeymapProfile(profile)
    return profile
}

func printKeymapProfile(_ profile: KeymapProfile) {
    print("Keymap profile: \(profile.name)")
    print("  remaps: \(profile.remaps.count)")
    for remap in (try? parseKeymapRemapSpecs(profile.remaps)) ?? [] {
        print("    \(keymapRemapSummary(remap))")
    }
}

func printKeymapProfileJSON(_ profile: KeymapProfile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func keymapProfileSequence(_ profile: KeymapProfile) throws -> [[UInt8]] {
    keymapFeatureSequence(table: try keymapRemapTable(try parseKeymapRemapSpecs(profile.remaps)))
}

func writeKeymapProfileSequence(_ profile: KeymapProfile, path: String) throws {
    try writeFeatureSequenceFile(try keymapProfileSequence(profile), path: path)
}

func parseMacroCreateOptions(_ args: [String]) throws -> (path: String, macro: MacroProfile) {
    guard let path = args.first else {
        throw DriverError.invalidArgument("macro-create requires a path.")
    }
    var name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    var repeatCount = 1
    var eventSpecs: [String] = []

    for argument in args.dropFirst() {
        if argument.hasPrefix("--name=") {
            name = String(argument.dropFirst("--name=".count))
        } else if argument.hasPrefix("--repeat=") {
            let value = String(argument.dropFirst("--repeat=".count))
            guard let parsed = Int(value), parsed >= 1, parsed <= 255 else {
                throw DriverError.invalidArgument("Macro repeat count must be between 1 and 255.")
            }
            repeatCount = parsed
        } else if argument.hasPrefix("--event=") {
            let value = String(argument.dropFirst("--event=".count))
            guard !value.isEmpty else {
                throw DriverError.invalidArgument("Empty --event option in macro-create.")
            }
            eventSpecs.append(value)
        } else if argument.hasPrefix("--") {
            throw DriverError.invalidArgument("Unknown macro-create option: \(argument)")
        } else {
            eventSpecs.append(argument)
        }
    }

    let macro = MacroProfile(
        format: "gmk67-macro",
        version: 1,
        name: name,
        repeatCount: repeatCount,
        events: try parseMacroEventSpecs(eventSpecs)
    )
    try validateMacroProfile(macro)
    return (path, macro)
}

func parseMacroLibraryCreateOptions(_ args: [String]) throws -> MacroProfile {
    let parsed = try parseMacroCreateOptions(["macro"] + args)
    return parsed.macro
}

func parseMacroEventSpecs(_ specs: [String]) throws -> [MacroEvent] {
    guard !specs.isEmpty else {
        throw DriverError.invalidArgument("At least one macro event is required.")
    }
    return try specs.map(parseMacroEventSpec)
}

func parseMacroEventSpec(_ spec: String) throws -> MacroEvent {
    let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
        throw DriverError.invalidArgument("Invalid macro event '\(spec)'. Use key:A, down:A, up:A, delay:50, or text:hello.")
    }
    let type = String(parts[0]).lowercased()
    let value = String(parts[1])

    switch type {
    case "key", "tap", "down", "up":
        let usage = try hidUsageByArgument(value)
        let normalizedType = type == "tap" ? "key" : type
        return MacroEvent(type: normalizedType, key: value, usage: hexByte(usage), text: nil, delayMS: nil)
    case "delay", "wait":
        guard let delay = Int(value), delay >= 0, delay <= 60_000 else {
            throw DriverError.invalidArgument("Macro delay must be between 0 and 60000 ms in '\(spec)'.")
        }
        return MacroEvent(type: "delay", key: nil, usage: nil, text: nil, delayMS: delay)
    case "text":
        guard value.count <= 256 else {
            throw DriverError.invalidArgument("Macro text event is limited to 256 characters.")
        }
        return MacroEvent(type: "text", key: nil, usage: nil, text: value, delayMS: nil)
    default:
        throw DriverError.invalidArgument("Unknown macro event type '\(type)' in '\(spec)'.")
    }
}

func validateMacroProfile(_ macro: MacroProfile) throws {
    guard macro.format == "gmk67-macro", macro.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 macro format/version.")
    }
    guard !macro.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DriverError.invalidArgument("Macro name must not be empty.")
    }
    guard macro.repeatCount >= 1, macro.repeatCount <= 255 else {
        throw DriverError.invalidArgument("Macro repeat count must be between 1 and 255.")
    }
    guard !macro.events.isEmpty else {
        throw DriverError.invalidArgument("Macro must contain at least one event.")
    }
    for event in macro.events {
        switch event.type {
        case "key", "down", "up":
            guard let key = event.key, let usage = event.usage, usage.hasPrefix("0x") else {
                throw DriverError.invalidArgument("Macro key event is missing key or usage.")
            }
            _ = try hidUsageByArgument(key)
        case "delay":
            guard let delay = event.delayMS, delay >= 0, delay <= 60_000 else {
                throw DriverError.invalidArgument("Macro delay event must be between 0 and 60000 ms.")
            }
        case "text":
            guard let text = event.text, !text.isEmpty, text.count <= 256 else {
                throw DriverError.invalidArgument("Macro text event must be 1...256 characters.")
            }
        default:
            throw DriverError.invalidArgument("Unknown macro event type '\(event.type)'.")
        }
    }
}

func writeMacroProfile(_ macro: MacroProfile, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(macro)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func readMacroProfile(_ path: String) throws -> MacroProfile {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let macro = try JSONDecoder().decode(MacroProfile.self, from: data)
    try validateMacroProfile(macro)
    return macro
}

func printMacroProfile(_ macro: MacroProfile) {
    print("Macro: \(macro.name)")
    print("  repeat: \(macro.repeatCount)")
    print("  events: \(macro.events.count)")
    for (index, event) in macro.events.enumerated() {
        switch event.type {
        case "key", "down", "up":
            print("    \(index + 1). \(event.type) \(event.key ?? "-") usage=\(event.usage ?? "-")")
        case "delay":
            print("    \(index + 1). delay \(event.delayMS ?? 0) ms")
        case "text":
            print("    \(index + 1). text \(event.text ?? "")")
        default:
            print("    \(index + 1). \(event.type)")
        }
    }
}

func printMacroProfileJSON(_ macro: MacroProfile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(macro)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func defaultProfileLibraryDirectory() -> URL {
    if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("GMK67", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }
    return URL(fileURLWithPath: ".gmk67-profiles", isDirectory: true)
}

func profileLibraryDirectory(from args: inout [String]) throws -> URL {
    if let index = args.firstIndex(where: { $0.hasPrefix("--directory=") }) {
        let value = String(args.remove(at: index).dropFirst("--directory=".count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("--directory must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return defaultProfileLibraryDirectory()
}

func profileLibrarySlotName(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw DriverError.invalidArgument("Profile slot name must not be empty.")
    }

    var result = ""
    var previousWasDash = false
    for scalar in trimmed.unicodeScalars {
        let isAllowed = CharacterSet.alphanumerics.contains(scalar)
        if isAllowed {
            result.unicodeScalars.append(scalar)
            previousWasDash = false
        } else if !previousWasDash {
            result.append("-")
            previousWasDash = true
        }
    }
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    guard !result.isEmpty else {
        throw DriverError.invalidArgument("Profile slot name contains no usable filename characters.")
    }
    return result
}

func profileLibraryURL(slot: String, directory: URL) throws -> URL {
    directory.appendingPathComponent(try profileLibrarySlotName(slot)).appendingPathExtension("json")
}

func ensureProfileLibraryDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

func profileLibraryEntries(directory: URL) throws -> [(slot: String, url: URL, profile: CombinedProfile)] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )

    var entries: [(slot: String, url: URL, profile: CombinedProfile)] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        let profile = try readCombinedProfile(url.path)
        entries.append((url.deletingPathExtension().lastPathComponent, url, profile))
    }
    return entries.sorted { $0.slot.localizedStandardCompare($1.slot) == .orderedAscending }
}

func printProfileLibraryList(directory: URL) throws {
    let entries = try profileLibraryListItems(directory: directory)
    print("Profile library: \(directory.path)")
    if entries.isEmpty {
        print("  no saved profiles")
        return
    }

    for entry in entries {
        let keymap = entry.keymapPreset ?? "-"
        print("  \(entry.slot) - \(entry.name)")
        print("    rgb=\(entry.rgbPreset) keymap=\(keymap) custom-rgb=\(entry.customRGB) custom-remaps=\(entry.customRemaps)")
    }
}

func profileLibraryListItems(directory: URL) throws -> [ProfileLibraryListItem] {
    try profileLibraryEntries(directory: directory).map { entry in
        ProfileLibraryListItem(
            slot: entry.slot,
            name: entry.profile.name,
            rgbPreset: entry.profile.rgbPreset,
            keymapPreset: entry.profile.keymapPreset,
            customRGB: (entry.profile.rgbAssignments ?? []).count,
            customRemaps: (entry.profile.keymapRemaps ?? []).count
        )
    }
}

func printProfileLibraryJSON(directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profileLibraryListItems(directory: directory))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

func printCombinedProfileJSON(_ profile: CombinedProfile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func saveProfileToLibrary(_ profile: CombinedProfile, slot: String?, directory: URL) throws -> URL {
    try ensureProfileLibraryDirectory(directory)
    let url = try profileLibraryURL(slot: slot ?? profile.name, directory: directory)
    try writeCombinedProfile(profile, path: url.path)
    return url
}

func readProfileFromLibrary(slot: String, directory: URL) throws -> CombinedProfile {
    try readCombinedProfile(try profileLibraryURL(slot: slot, directory: directory).path)
}

func profileLibraryBundle(from directory: URL) throws -> ProfileLibraryBundle {
    let entries = try profileLibraryEntries(directory: directory).map { entry in
        ProfileLibraryBundleEntry(slot: entry.slot, profile: entry.profile)
    }
    return ProfileLibraryBundle(
        format: "gmk67-profile-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        profiles: entries
    )
}

func writeProfileLibraryBundle(directory: URL, path: String) throws -> ProfileLibraryBundle {
    let bundle = try profileLibraryBundle(from: directory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

func readProfileLibraryBundle(_ path: String) throws -> ProfileLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(ProfileLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-profile-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 profile library bundle format/version.")
    }
    var seenSlots = Set<String>()
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        guard seenSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate profile slot in library bundle: \(slot)")
        }
        try validateCombinedProfile(entry.profile)
    }
    return bundle
}

func importProfileLibraryBundle(_ path: String, directory: URL) throws -> [String] {
    let bundle = try readProfileLibraryBundle(path)
    try ensureProfileLibraryDirectory(directory)
    var importedSlots: [String] = []
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        let url = try profileLibraryURL(slot: slot, directory: directory)
        try writeCombinedProfile(entry.profile, path: url.path)
        importedSlots.append(slot)
    }
    return importedSlots
}

func defaultKeymapLibraryDirectory() -> URL {
    if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("GMK67", isDirectory: true)
            .appendingPathComponent("Keymaps", isDirectory: true)
    }
    return URL(fileURLWithPath: ".gmk67-keymaps", isDirectory: true)
}

func keymapLibraryDirectory(from args: inout [String]) throws -> URL {
    if let index = args.firstIndex(where: { $0.hasPrefix("--directory=") }) {
        let value = String(args.remove(at: index).dropFirst("--directory=".count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("--directory must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return defaultKeymapLibraryDirectory()
}

func keymapLibraryURL(slot: String, directory: URL) throws -> URL {
    directory.appendingPathComponent(try profileLibrarySlotName(slot)).appendingPathExtension("json")
}

func ensureKeymapLibraryDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

func saveKeymapToLibrary(_ profile: KeymapProfile, slot: String?, directory: URL) throws -> URL {
    try ensureKeymapLibraryDirectory(directory)
    let url = try keymapLibraryURL(slot: slot ?? profile.name, directory: directory)
    try writeKeymapProfile(profile, path: url.path)
    return url
}

func readKeymapFromLibrary(slot: String, directory: URL) throws -> KeymapProfile {
    try readKeymapProfile(try keymapLibraryURL(slot: slot, directory: directory).path)
}

func keymapLibraryEntries(directory: URL) throws -> [(slot: String, url: URL, profile: KeymapProfile)] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    var entries: [(slot: String, url: URL, profile: KeymapProfile)] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        let profile = try readKeymapProfile(url.path)
        entries.append((url.deletingPathExtension().lastPathComponent, url, profile))
    }
    return entries.sorted { $0.slot.localizedStandardCompare($1.slot) == .orderedAscending }
}

func keymapLibraryListItems(directory: URL) throws -> [KeymapLibraryListItem] {
    try keymapLibraryEntries(directory: directory).map { entry in
        KeymapLibraryListItem(slot: entry.slot, name: entry.profile.name, remapCount: entry.profile.remaps.count)
    }
}

func printKeymapLibraryList(directory: URL) throws {
    let entries = try keymapLibraryListItems(directory: directory)
    print("Keymap library: \(directory.path)")
    if entries.isEmpty {
        print("  no saved keymaps")
        return
    }
    for entry in entries {
        print("  \(entry.slot) - \(entry.name)")
        print("    remaps=\(entry.remapCount)")
    }
}

func printKeymapLibraryJSON(directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(keymapLibraryListItems(directory: directory))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

func keymapLibraryBundle(from directory: URL) throws -> KeymapLibraryBundle {
    let entries = try keymapLibraryEntries(directory: directory).map { entry in
        KeymapLibraryBundleEntry(slot: entry.slot, profile: entry.profile)
    }
    return KeymapLibraryBundle(
        format: "gmk67-keymap-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        profiles: entries
    )
}

func writeKeymapLibraryBundle(directory: URL, path: String) throws -> KeymapLibraryBundle {
    let bundle = try keymapLibraryBundle(from: directory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

func readKeymapLibraryBundle(_ path: String) throws -> KeymapLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(KeymapLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-keymap-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 keymap library bundle format/version.")
    }
    var seenSlots = Set<String>()
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        guard seenSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate keymap slot in library bundle: \(slot)")
        }
        try validateKeymapProfile(entry.profile)
    }
    return bundle
}

func importKeymapLibraryBundle(_ path: String, directory: URL) throws -> [String] {
    let bundle = try readKeymapLibraryBundle(path)
    try ensureKeymapLibraryDirectory(directory)
    var importedSlots: [String] = []
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        let url = try keymapLibraryURL(slot: slot, directory: directory)
        try writeKeymapProfile(entry.profile, path: url.path)
        importedSlots.append(slot)
    }
    return importedSlots
}

func defaultMacroLibraryDirectory() -> URL {
    if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("GMK67", isDirectory: true)
            .appendingPathComponent("Macros", isDirectory: true)
    }
    return URL(fileURLWithPath: ".gmk67-macros", isDirectory: true)
}

func macroLibraryDirectory(from args: inout [String]) throws -> URL {
    if let index = args.firstIndex(where: { $0.hasPrefix("--directory=") }) {
        let value = String(args.remove(at: index).dropFirst("--directory=".count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("--directory must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
    return defaultMacroLibraryDirectory()
}

func macroLibraryURL(slot: String, directory: URL) throws -> URL {
    directory.appendingPathComponent(try profileLibrarySlotName(slot)).appendingPathExtension("json")
}

func ensureMacroLibraryDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

func saveMacroToLibrary(_ macro: MacroProfile, slot: String?, directory: URL) throws -> URL {
    try ensureMacroLibraryDirectory(directory)
    let url = try macroLibraryURL(slot: slot ?? macro.name, directory: directory)
    try writeMacroProfile(macro, path: url.path)
    return url
}

func readMacroFromLibrary(slot: String, directory: URL) throws -> MacroProfile {
    try readMacroProfile(try macroLibraryURL(slot: slot, directory: directory).path)
}

func macroLibraryEntries(directory: URL) throws -> [(slot: String, url: URL, macro: MacroProfile)] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    var entries: [(slot: String, url: URL, macro: MacroProfile)] = []
    for url in urls where url.pathExtension.lowercased() == "json" {
        let macro = try readMacroProfile(url.path)
        entries.append((url.deletingPathExtension().lastPathComponent, url, macro))
    }
    return entries.sorted { $0.slot.localizedStandardCompare($1.slot) == .orderedAscending }
}

func macroLibraryListItems(directory: URL) throws -> [MacroLibraryListItem] {
    try macroLibraryEntries(directory: directory).map { entry in
        MacroLibraryListItem(
            slot: entry.slot,
            name: entry.macro.name,
            repeatCount: entry.macro.repeatCount,
            eventCount: entry.macro.events.count
        )
    }
}

func printMacroLibraryList(directory: URL) throws {
    let entries = try macroLibraryListItems(directory: directory)
    print("Macro library: \(directory.path)")
    if entries.isEmpty {
        print("  no saved macros")
        return
    }
    for entry in entries {
        print("  \(entry.slot) - \(entry.name)")
        print("    repeat=\(entry.repeatCount) events=\(entry.eventCount)")
    }
}

func printMacroLibraryJSON(directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(macroLibraryListItems(directory: directory))
    print(String(data: data, encoding: .utf8) ?? "[]")
}

func macroLibraryBundle(from directory: URL) throws -> MacroLibraryBundle {
    let entries = try macroLibraryEntries(directory: directory).map { entry in
        MacroLibraryBundleEntry(slot: entry.slot, macro: entry.macro)
    }
    return MacroLibraryBundle(
        format: "gmk67-macro-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        macros: entries
    )
}

func writeMacroLibraryBundle(directory: URL, path: String) throws -> MacroLibraryBundle {
    let bundle = try macroLibraryBundle(from: directory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

func readMacroLibraryBundle(_ path: String) throws -> MacroLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(MacroLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-macro-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 macro library bundle format/version.")
    }
    var seenSlots = Set<String>()
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        guard seenSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate macro slot in library bundle: \(slot)")
        }
        try validateMacroProfile(entry.macro)
    }
    return bundle
}

func importMacroLibraryBundle(_ path: String, directory: URL) throws -> [String] {
    let bundle = try readMacroLibraryBundle(path)
    try ensureMacroLibraryDirectory(directory)
    var importedSlots: [String] = []
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        let url = try macroLibraryURL(slot: slot, directory: directory)
        try writeMacroProfile(entry.macro, path: url.path)
        importedSlots.append(slot)
    }
    return importedSlots
}

func appLibraryDirectories(from args: inout [String]) throws -> (profiles: URL, keymaps: URL, macros: URL) {
    var profiles = defaultProfileLibraryDirectory()
    var keymaps = defaultKeymapLibraryDirectory()
    var macros = defaultMacroLibraryDirectory()

    func popDirectoryOption(_ prefix: String) throws -> URL? {
        guard let index = args.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let value = String(args.remove(at: index).dropFirst(prefix.count))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DriverError.invalidArgument("\(prefix.dropLast()) must not be empty.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    if let value = try popDirectoryOption("--profiles=") {
        profiles = value
    }
    if let value = try popDirectoryOption("--keymaps=") {
        keymaps = value
    }
    if let value = try popDirectoryOption("--macros=") {
        macros = value
    }
    return (profiles, keymaps, macros)
}

func appLibraryBundle(profileDirectory: URL, keymapDirectory: URL, macroDirectory: URL) throws -> AppLibraryBundle {
    AppLibraryBundle(
        format: "gmk67-app-library",
        version: 1,
        exportedAt: ISO8601DateFormatter().string(from: Date()),
        profiles: try profileLibraryEntries(directory: profileDirectory).map { ProfileLibraryBundleEntry(slot: $0.slot, profile: $0.profile) },
        keymaps: try keymapLibraryEntries(directory: keymapDirectory).map { KeymapLibraryBundleEntry(slot: $0.slot, profile: $0.profile) },
        macros: try macroLibraryEntries(directory: macroDirectory).map { MacroLibraryBundleEntry(slot: $0.slot, macro: $0.macro) }
    )
}

func writeAppLibraryBundle(profileDirectory: URL, keymapDirectory: URL, macroDirectory: URL, path: String) throws -> AppLibraryBundle {
    let bundle = try appLibraryBundle(profileDirectory: profileDirectory, keymapDirectory: keymapDirectory, macroDirectory: macroDirectory)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(bundle)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    return bundle
}

func readAppLibraryBundle(_ path: String) throws -> AppLibraryBundle {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let bundle = try JSONDecoder().decode(AppLibraryBundle.self, from: data)
    guard bundle.format == "gmk67-app-library", bundle.version == 1 else {
        throw DriverError.invalidArgument("Unsupported GMK67 app library bundle format/version.")
    }

    var profileSlots = Set<String>()
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        guard profileSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate profile slot in app library bundle: \(slot)")
        }
        try validateCombinedProfile(entry.profile)
    }

    var keymapSlots = Set<String>()
    for entry in bundle.keymaps {
        let slot = try profileLibrarySlotName(entry.slot)
        guard keymapSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate keymap slot in app library bundle: \(slot)")
        }
        try validateKeymapProfile(entry.profile)
    }

    var macroSlots = Set<String>()
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        guard macroSlots.insert(slot).inserted else {
            throw DriverError.invalidArgument("Duplicate macro slot in app library bundle: \(slot)")
        }
        try validateMacroProfile(entry.macro)
    }

    return bundle
}

func importAppLibraryBundle(_ path: String, profileDirectory: URL, keymapDirectory: URL, macroDirectory: URL) throws -> (profiles: [String], keymaps: [String], macros: [String]) {
    let bundle = try readAppLibraryBundle(path)
    try ensureProfileLibraryDirectory(profileDirectory)
    try ensureKeymapLibraryDirectory(keymapDirectory)
    try ensureMacroLibraryDirectory(macroDirectory)

    var importedProfiles: [String] = []
    for entry in bundle.profiles {
        let slot = try profileLibrarySlotName(entry.slot)
        try writeCombinedProfile(entry.profile, path: try profileLibraryURL(slot: slot, directory: profileDirectory).path)
        importedProfiles.append(slot)
    }

    var importedKeymaps: [String] = []
    for entry in bundle.keymaps {
        let slot = try profileLibrarySlotName(entry.slot)
        try writeKeymapProfile(entry.profile, path: try keymapLibraryURL(slot: slot, directory: keymapDirectory).path)
        importedKeymaps.append(slot)
    }

    var importedMacros: [String] = []
    for entry in bundle.macros {
        let slot = try profileLibrarySlotName(entry.slot)
        try writeMacroProfile(entry.macro, path: try macroLibraryURL(slot: slot, directory: macroDirectory).path)
        importedMacros.append(slot)
    }

    return (importedProfiles, importedKeymaps, importedMacros)
}
