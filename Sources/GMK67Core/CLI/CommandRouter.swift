import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

public func runGMK67Command(_ args: [String]) throws {
    try run(args)
}

func run(_ args: [String]) throws {
    guard let command = args.dropFirst().first else {
        printUsage()
        return
    }

    switch command {
    case "list":
        let driver = HIDDriver()
        let devices = driver.configurationDevices()
        if devices.isEmpty {
            throw DriverError.noDevice
        }
        printDevices(devices)

    case "scan":
        let driver = HIDDriver()
        let devices = driver.devices()
        if devices.isEmpty {
            throw DriverError.noDevice
        }
        printDevices(devices)

    case "dump-layout":
        print(try layoutReportText(), terminator: "")

    case "self-test":
        guard args.count == 2 else {
            printUsage()
            return
        }
        try runSelfTest()

    case "doctor":
        guard args.count == 2 || (args.count == 3 && args[2] == "--open-check") else {
            printUsage()
            return
        }
        try runDoctor(openCheck: args.contains("--open-check"))

    case "readiness":
        guard args.count == 2 || (args.count == 3 && args[2] == "--open-check") else {
            printUsage()
            return
        }
        print(readinessReport(openCheck: args.contains("--open-check")), terminator: "")

    case "protocol-candidates":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printProtocolCandidates()

    case "windows-features":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(windowsFeatureInventoryText())

    case "validation-plan":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(validationPlanText())

    case "diagnostics":
        guard args.count == 2 || args.count == 3 else {
            printUsage()
            return
        }
        let report = diagnosticsReport()
        if args.count == 3 {
            try report.write(toFile: args[2], atomically: true, encoding: .utf8)
            print("Saved diagnostics report to \(args[2]). No HID reports were sent.")
        } else {
            print(report, terminator: "")
        }

    case "support-bundle":
        guard args.count == 2 || args.count == 3 else {
            printUsage()
            return
        }
        let path = args.count == 3 ? args[2] : defaultSupportBundlePath()
        try writeSupportBundle(directoryPath: path)
        print("Saved support bundle to \(path). No HID reports were sent.")

    case "permission-status":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(inputMonitoringPermissionReport(request: false), terminator: "")

    case "permission-request":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print(inputMonitoringPermissionReport(request: true), terminator: "")

    case "factory-reset-dry-run":
        guard args.count == 2 else {
            printUsage()
            return
        }
        print("Modeled GMK67 factory reset preview:")
        print("  RGB: clear all known physical key LED records to 00 00 00.")
        print("  Keymap: write the empty custom-keymap table.")
        print("Rendered RGB records:")
        printRGBRecords(try factoryResetRGBFrames(), keyByLightIndex: keyMapByLightIndex())
        print("Candidate keymap clear sequence: \(factoryResetKeymapSequence().count) reports, 9 table chunks, AA 55 marker at table offset 0x23E.")
        print("Dry run only: no HID device was opened and no reports were sent.")

    case "factory-reset-export":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let outputs = try writeFactoryResetArtifacts(prefix: args[2])
        print("Saved modeled factory-reset RGB artifact to \(outputs.rgbPath).")
        print("Saved modeled factory-reset keymap-clear artifact to \(outputs.keymapPath).")
        print("No HID device was opened.")

    case "factory-reset":
        let options = try parseUnsafeFactoryResetOptions(Array(args.dropFirst(2)))
        try applyFactoryResetToDevice(writeIndex: options.writeIndex, readIndex: options.readIndex)

    case "profile-create":
        let options = try parseProfileCreateOptions(Array(args.dropFirst(2)))
        try writeCombinedProfile(options.profile, path: options.path)
        print("Saved GMK67 profile to \(options.path). No HID device was opened.")
        printCombinedProfile(options.profile)

    case "profile-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        print("GMK67 profile OK. No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-preview":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        try printCombinedProfilePreview(profile)

    case "profile-show":
        guard args.count == 3 || (args.count == 4 && args[3] == "--json") else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        if args.contains("--json") {
            try printCombinedProfileJSON(profile)
        } else {
            printCombinedProfile(profile)
        }

    case "profile-preview-spec":
        let profile = try parseProfileLibraryCreateOptions(Array(args.dropFirst(2)))
        try printCombinedProfilePreview(profile)

    case "profile-export-spec":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let prefix = args[2]
        let profile = try parseProfileLibraryCreateOptions(Array(args.dropFirst(3)))
        let outputs = try exportCombinedProfileArtifacts(profile, prefix: prefix)
        print("Saved composed RGB artifact to \(outputs.rgbPath). No HID device was opened.")
        if let keymapPath = outputs.keymapPath {
            print("Saved composed keymap artifact to \(keymapPath).")
        } else {
            print("Inline profile has no keymap changes; no keymap artifact was written.")
        }

    case "profile-apply-spec":
        let options = try parseInlineProfileApplyOptions(Array(args.dropFirst(2)))
        try applyCombinedProfileToDevice(
            options.profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let profile = try readCombinedProfile(args[2])
        let outputs = try exportCombinedProfileArtifacts(profile, prefix: args[3])
        print("Saved composed RGB artifact to \(outputs.rgbPath). No HID device was opened.")
        if let keymapPath = outputs.keymapPath {
            print("Saved composed keymap artifact to \(keymapPath).")
        } else {
            print("Profile has no keymap changes; no keymap artifact was written.")
        }

    case "profile-apply":
        let options = try parseProfileApplyOptions(Array(args.dropFirst(2)))
        let profile = try readCombinedProfile(options.path)
        try applyCombinedProfileToDevice(
            profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printCombinedProfilePresetList()

    case "profile-preset-show":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let preset = try combinedProfilePreset(named: args[2])
        if args.count == 4 {
            switch args[3] {
            case "--json":
                try printCombinedProfileJSON(try makeCombinedProfile(from: preset))
            case "--editor-json":
                try printCombinedProfileJSON(try makeEditableCombinedProfile(from: preset))
            default:
                printUsage()
                return
            }
        } else {
            printCombinedProfile(try makeCombinedProfile(from: preset))
        }

    case "profile-preset-create":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let preset = try combinedProfilePreset(named: args[3])
        let profile = try makeCombinedProfile(from: preset)
        try writeCombinedProfile(profile, path: args[2])
        print("Saved GMK67 profile preset \(preset.name) to \(args[2]). No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-preset-apply":
        let options = try parseProfilePresetApplyOptions(Array(args.dropFirst(2)))
        let preset = try combinedProfilePreset(named: options.name)
        let profile = try makeCombinedProfile(from: preset)
        try applyCombinedProfileToDevice(
            profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-library-create":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        var slot: String?
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--slot=") }) {
            slot = String(arguments.remove(at: index).dropFirst("--slot=".count))
        }
        let profile = try parseProfileLibraryCreateOptions(arguments)
        let url = try saveProfileToLibrary(profile, slot: slot, directory: directory)
        print("Saved profile library entry to \(url.path). No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-library-save":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard !arguments.isEmpty else {
            printUsage()
            return
        }
        let path = arguments.removeFirst()
        var slot: String?
        for argument in arguments {
            if argument.hasPrefix("--slot=") {
                slot = String(argument.dropFirst("--slot=".count))
            } else {
                throw DriverError.invalidArgument("Unknown profile-library-save option: \(argument)")
            }
        }
        let profile = try readCombinedProfile(path)
        let url = try saveProfileToLibrary(profile, slot: slot, directory: directory)
        print("Saved profile library entry to \(url.path). No HID device was opened.")
        printCombinedProfile(profile)

    case "profile-library-list":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.isEmpty else {
            throw DriverError.invalidArgument("Unknown profile-library-list option: \(arguments.joined(separator: " "))")
        }
        if wantsJSON {
            try printProfileLibraryJSON(directory: directory)
        } else {
            try printProfileLibraryList(directory: directory)
        }

    case "profile-library-preview":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let profile = try readProfileFromLibrary(slot: arguments[0], directory: directory)
        try printCombinedProfilePreview(profile)

    case "profile-library-show":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let profile = try readProfileFromLibrary(slot: arguments[0], directory: directory)
        if wantsJSON {
            try printCombinedProfileJSON(profile)
        } else {
            printCombinedProfile(profile)
        }

    case "profile-library-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 2 else {
            printUsage()
            return
        }
        let profile = try readProfileFromLibrary(slot: arguments[0], directory: directory)
        let outputs = try exportCombinedProfileArtifacts(profile, prefix: arguments[1])
        print("Saved composed RGB artifact to \(outputs.rgbPath). No HID device was opened.")
        if let keymapPath = outputs.keymapPath {
            print("Saved composed keymap artifact to \(keymapPath).")
        } else {
            print("Profile has no keymap section; no keymap artifact was written.")
        }

    case "profile-library-apply":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard let slot = arguments.first else {
            printUsage()
            return
        }
        let options = try parseProfileApplyOptions(["library-profile"] + Array(arguments.dropFirst()))
        let profile = try readProfileFromLibrary(slot: slot, directory: directory)
        try applyCombinedProfileToDevice(
            profile,
            hasUnsafeFlag: options.hasUnsafeFlag,
            writeIndex: options.writeIndex,
            readIndex: options.readIndex
        )

    case "profile-library-delete":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let url = try profileLibraryURL(slot: arguments[0], directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DriverError.invalidArgument("Profile library entry not found: \(arguments[0])")
        }
        try FileManager.default.removeItem(at: url)
        print("Deleted profile library entry \(arguments[0]) from \(directory.path).")

    case "profile-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeProfileLibraryBundle(directory: directory, path: arguments[0])
        print("Saved \(bundle.profiles.count) profile library entr\(bundle.profiles.count == 1 ? "y" : "ies") to \(arguments[0]).")
        print("No HID device was opened.")

    case "profile-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directory = try profileLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let importedSlots = try importProfileLibraryBundle(arguments[0], directory: directory)
        print("Imported \(importedSlots.count) profile library entr\(importedSlots.count == 1 ? "y" : "ies") into \(directory.path).")
        if !importedSlots.isEmpty {
            print("Slots: \(importedSlots.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "app-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directories = try appLibraryDirectories(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeAppLibraryBundle(
            profileDirectory: directories.profiles,
            keymapDirectory: directories.keymaps,
            macroDirectory: directories.macros,
            path: arguments[0]
        )
        print("Saved app library bundle to \(arguments[0]).")
        print("  profiles: \(bundle.profiles.count)")
        print("  keymaps: \(bundle.keymaps.count)")
        print("  macros: \(bundle.macros.count)")
        print("No HID device was opened.")

    case "app-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directories = try appLibraryDirectories(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let imported = try importAppLibraryBundle(
            arguments[0],
            profileDirectory: directories.profiles,
            keymapDirectory: directories.keymaps,
            macroDirectory: directories.macros
        )
        print("Imported app library bundle into:")
        print("  profiles: \(directories.profiles.path) (\(imported.profiles.count))")
        print("  keymaps: \(directories.keymaps.path) (\(imported.keymaps.count))")
        print("  macros: \(directories.macros.path) (\(imported.macros.count))")
        if !imported.profiles.isEmpty {
            print("Profile slots: \(imported.profiles.joined(separator: ", "))")
        }
        if !imported.keymaps.isEmpty {
            print("Keymap slots: \(imported.keymaps.joined(separator: ", "))")
        }
        if !imported.macros.isEmpty {
            print("Macro slots: \(imported.macros.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "macro-create":
        let options = try parseMacroCreateOptions(Array(args.dropFirst(2)))
        try writeMacroProfile(options.macro, path: options.path)
        print("Saved GMK67 macro to \(options.path). No HID device was opened.")
        printMacroProfile(options.macro)

    case "macro-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let macro = try readMacroProfile(args[2])
        print("GMK67 macro OK. No HID device was opened.")
        printMacroProfile(macro)

    case "macro-show":
        guard args.count == 3 || (args.count == 4 && args[3] == "--json") else {
            printUsage()
            return
        }
        let macro = try readMacroProfile(args[2])
        if args.contains("--json") {
            try printMacroProfileJSON(macro)
        } else {
            printMacroProfile(macro)
        }

    case "macro-firmware-template":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let chunkCount: Int
        if args.count == 4 {
            guard let parsed = Int(args[3]) else {
                throw DriverError.invalidArgument("Macro firmware chunk count must be a decimal integer.")
            }
            chunkCount = parsed
        } else {
            chunkCount = defaultMacroFirmwareChunkCount
        }
        let sequence = try macroFirmwareTemplateFeatureSequence(chunkCount: chunkCount)
        try writeFeatureSequenceFile(sequence, path: args[2])
        print("Saved \(sequence.count) candidate macro firmware feature reports to \(args[2]). No HID device was opened.")
        print("This models the Windows 04 19 / 04 15 macro-table container with \(chunkCount) table chunks and an AA 55 marker.")
        print("It is a zeroed template for captured/raw firmware tables; app-local macro JSON event encoding is not proven yet.")

    case "macro-firmware-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        _ = try validateMacroFirmwareFeatureSequenceFile(args[2])

    case "macro-firmware-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "macro firmware")
        let sequence = try validateMacroFirmwareFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "macro firmware")

    case "macro-library-create":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        var slot: String?
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--slot=") }) {
            slot = String(arguments.remove(at: index).dropFirst("--slot=".count))
        }
        let macro = try parseMacroLibraryCreateOptions(arguments)
        let url = try saveMacroToLibrary(macro, slot: slot, directory: directory)
        print("Saved macro library entry to \(url.path). No HID device was opened.")
        printMacroProfile(macro)

    case "macro-library-save":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard !arguments.isEmpty else {
            printUsage()
            return
        }
        let path = arguments.removeFirst()
        var slot: String?
        for argument in arguments {
            if argument.hasPrefix("--slot=") {
                slot = String(argument.dropFirst("--slot=".count))
            } else {
                throw DriverError.invalidArgument("Unknown macro-library-save option: \(argument)")
            }
        }
        let macro = try readMacroProfile(path)
        let url = try saveMacroToLibrary(macro, slot: slot, directory: directory)
        print("Saved macro library entry to \(url.path). No HID device was opened.")
        printMacroProfile(macro)

    case "macro-library-list":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.isEmpty else {
            throw DriverError.invalidArgument("Unknown macro-library-list option: \(arguments.joined(separator: " "))")
        }
        if wantsJSON {
            try printMacroLibraryJSON(directory: directory)
        } else {
            try printMacroLibraryList(directory: directory)
        }

    case "macro-library-show":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let macro = try readMacroFromLibrary(slot: arguments[0], directory: directory)
        if wantsJSON {
            try printMacroProfileJSON(macro)
        } else {
            printMacroProfile(macro)
        }

    case "macro-library-delete":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let url = try macroLibraryURL(slot: arguments[0], directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DriverError.invalidArgument("Macro library entry not found: \(arguments[0])")
        }
        try FileManager.default.removeItem(at: url)
        print("Deleted macro library entry \(arguments[0]) from \(directory.path).")

    case "macro-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeMacroLibraryBundle(directory: directory, path: arguments[0])
        print("Saved \(bundle.macros.count) macro library entr\(bundle.macros.count == 1 ? "y" : "ies") to \(arguments[0]).")
        print("No HID device was opened.")

    case "macro-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directory = try macroLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let importedSlots = try importMacroLibraryBundle(arguments[0], directory: directory)
        print("Imported \(importedSlots.count) macro library entr\(importedSlots.count == 1 ? "y" : "ies") into \(directory.path).")
        if !importedSlots.isEmpty {
            print("Slots: \(importedSlots.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "keymap-dry-run":
        guard args.count == 4 || args.count == 5 else {
            printUsage()
            return
        }
        let source = try keyByArgument(args[2])
        let targetUsage = try hidUsageByArgument(args[3])
        let modifierUsage = args.count == 5 ? try hidUsageByArgument(args[4]) : nil
        let table = try keymapSimpleRemapTable(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        let sequence = keymapFeatureSequence(table: table)
        let tableReportCount = sequence.count - 4

        let modifierText = modifierUsage.map { String(format: " modifier=0x%02X encoded=0x%02X", $0, keymapEncodedUsage($0)) } ?? ""
        let remap = KeymapRemap(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        print(String(
            format: "Candidate simple remap: source=%@ key_index=%d target_hid=0x%02X encoded=0x%02X%@",
            source.name,
            source.keyIndex,
            targetUsage,
            keymapEncodedUsage(targetUsage),
            modifierText
        ))
        print(String(
            format: "Changed table record offset=0x%03X bytes=%@",
            source.keyIndex * 4,
            hex(keymapRemapRecord(remap))
        ))
        print("Dry run only: no HID device was opened and no reports were sent.")
        print(String(
            format: "Modeled Windows chunking: declared table length=0x%03X, table reports=%d, AA 55 marker at offset=0x23E.",
            table.count,
            tableReportCount
        ))
        print("This sequence represents a full custom-keymap table containing only the displayed remap.")
        print("Candidate feature sequence:")
        printFeatureSequence(sequence)

    case "keymap-clear-dry-run":
        guard args.count == 2 else {
            printUsage()
            return
        }
        let table = emptyKeymapTable()
        let sequence = keymapFeatureSequence(table: table)
        print("Candidate empty custom keymap table.")
        print("Dry run only: no HID device was opened and no reports were sent.")
        print(String(
            format: "Modeled Windows chunking: declared table length=0x%03X, table reports=%d, AA 55 marker at offset=0x23E.",
            table.count,
            sequence.count - 4
        ))
        print("Candidate feature sequence:")
        printFeatureSequence(sequence)

    case "keymap-export":
        guard args.count == 5 || args.count == 6 else {
            printUsage()
            return
        }
        let path = args[2]
        let source = try keyByArgument(args[3])
        let targetUsage = try hidUsageByArgument(args[4])
        let modifierUsage = args.count == 6 ? try hidUsageByArgument(args[5]) : nil
        let table = try keymapSimpleRemapTable(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        let sequence = keymapFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print(String(
            format: "Saved %d keymap feature reports to %@ for %@ -> HID 0x%02X. No HID device was opened.",
            sequence.count,
            path,
            source.name,
            targetUsage
        ))

    case "keymap-clear-export":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let sequence = keymapFeatureSequence(table: emptyKeymapTable())
        try writeFeatureSequenceFile(sequence, path: args[2])
        print("Saved \(sequence.count) empty-keymap feature reports to \(args[2]). No HID device was opened.")

    case "keymap-map-dry-run":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let remaps = try parseKeymapRemapSpecs(Array(args.dropFirst(2)))
        let table = try keymapRemapTable(remaps)
        let sequence = keymapFeatureSequence(table: table)
        print("Candidate multi-remap custom keymap table:")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print("Dry run only: no HID device was opened and no reports were sent.")
        print(String(
            format: "Modeled Windows chunking: declared table length=0x%03X, table reports=%d, AA 55 marker at offset=0x23E.",
            table.count,
            sequence.count - 4
        ))
        print("Candidate feature sequence:")
        printFeatureSequence(sequence)

    case "keymap-map-export":
        guard args.count >= 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let remaps = try parseKeymapRemapSpecs(Array(args.dropFirst(3)))
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) keymap feature reports with \(remaps.count) remap(s) to \(path). No HID device was opened.")

    case "keymap-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printKeymapPresetList()

    case "keymap-preset-show":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let preset = try keymapPreset(named: args[2])
        if args.count == 4 {
            guard args[3] == "--json" else {
                printUsage()
                return
            }
            try printKeymapPresetJSON(preset)
        } else {
            printKeymapPreset(preset)
        }

    case "keymap-preset-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let preset = try keymapPreset(named: args[3])
        let remaps = try keymapPresetRemaps(preset)
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) keymap feature reports for preset \(preset.name) to \(path). No HID device was opened.")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }

    case "keymap-preset-apply":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        guard options.operands.count == 1 else {
            printUsage()
            return
        }
        let preset = try keymapPreset(named: options.operands[0])
        let remaps = try keymapPresetRemaps(preset)
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying keymap preset \(preset.name): \(preset.description)")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate keymap preset sequence sent.")

    case "keymap-sequence-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateKeymapFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printKeymapRecordsJSON(sequence)
        }

    case "keymap-file-apply":
        let options = try parseUnsafeKeymapFileOptions(Array(args.dropFirst(2)))
        let sequence = try validateKeymapFeatureSequenceFile(options.path)
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Writing validated keymap sequence file \(options.path).")
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Validated keymap sequence file sent.")

    case "keymap-profile-create":
        let options = try parseKeymapProfileCreateOptions(Array(args.dropFirst(2)))
        try writeKeymapProfile(options.profile, path: options.path)
        print("Saved GMK67 keymap profile to \(options.path). No HID device was opened.")
        printKeymapProfile(options.profile)

    case "keymap-profile-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let profile = try readKeymapProfile(args[2])
        print("GMK67 keymap profile OK. No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-profile-show":
        guard args.count == 3 || (args.count == 4 && args[3] == "--json") else {
            printUsage()
            return
        }
        let profile = try readKeymapProfile(args[2])
        if args.contains("--json") {
            try printKeymapProfileJSON(profile)
        } else {
            printKeymapProfile(profile)
        }

    case "keymap-profile-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let profile = try readKeymapProfile(args[2])
        try writeKeymapProfileSequence(profile, path: args[3])
        print("Saved \(try keymapProfileSequence(profile).count) keymap feature reports to \(args[3]). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-profile-apply":
        let options = try parseUnsafeKeymapFileOptions(Array(args.dropFirst(2)))
        let profile = try readKeymapProfile(options.path)
        let sequence = try keymapProfileSequence(profile)
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying keymap profile \(profile.name).")
        printKeymapProfile(profile)
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Keymap profile sequence sent.")

    case "keymap-library-create":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        var slot: String?
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--slot=") }) {
            slot = String(arguments.remove(at: index).dropFirst("--slot=".count))
        }
        let profile = try parseKeymapLibraryCreateOptions(arguments)
        let url = try saveKeymapToLibrary(profile, slot: slot, directory: directory)
        print("Saved keymap library entry to \(url.path). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-library-save":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard !arguments.isEmpty else {
            printUsage()
            return
        }
        let path = arguments.removeFirst()
        var slot: String?
        for argument in arguments {
            if argument.hasPrefix("--slot=") {
                slot = String(argument.dropFirst("--slot=".count))
            } else {
                throw DriverError.invalidArgument("Unknown keymap-library-save option: \(argument)")
            }
        }
        let profile = try readKeymapProfile(path)
        let url = try saveKeymapToLibrary(profile, slot: slot, directory: directory)
        print("Saved keymap library entry to \(url.path). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-library-list":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.isEmpty else {
            throw DriverError.invalidArgument("Unknown keymap-library-list option: \(arguments.joined(separator: " "))")
        }
        if wantsJSON {
            try printKeymapLibraryJSON(directory: directory)
        } else {
            try printKeymapLibraryList(directory: directory)
        }

    case "keymap-library-show":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        var wantsJSON = false
        if let index = arguments.firstIndex(of: "--json") {
            arguments.remove(at: index)
            wantsJSON = true
        }
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let profile = try readKeymapFromLibrary(slot: arguments[0], directory: directory)
        if wantsJSON {
            try printKeymapProfileJSON(profile)
        } else {
            printKeymapProfile(profile)
        }

    case "keymap-library-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 2 else {
            printUsage()
            return
        }
        let profile = try readKeymapFromLibrary(slot: arguments[0], directory: directory)
        try writeKeymapProfileSequence(profile, path: arguments[1])
        print("Saved \(try keymapProfileSequence(profile).count) keymap feature reports to \(arguments[1]). No HID device was opened.")
        printKeymapProfile(profile)

    case "keymap-library-apply":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        let options = try parseUnsafeKeymapOptions(arguments)
        guard options.operands.count == 1 else {
            printUsage()
            return
        }
        let profile = try readKeymapFromLibrary(slot: options.operands[0], directory: directory)
        let sequence = try keymapProfileSequence(profile)
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Applying saved keymap profile \(options.operands[0]): \(profile.name).")
        printKeymapProfile(profile)
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Saved keymap profile sequence sent.")

    case "keymap-library-delete":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let url = try keymapLibraryURL(slot: arguments[0], directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DriverError.invalidArgument("Keymap library entry not found: \(arguments[0])")
        }
        try FileManager.default.removeItem(at: url)
        print("Deleted keymap library entry \(arguments[0]) from \(directory.path).")

    case "keymap-library-bundle-export":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let bundle = try writeKeymapLibraryBundle(directory: directory, path: arguments[0])
        print("Saved \(bundle.profiles.count) keymap library entr\(bundle.profiles.count == 1 ? "y" : "ies") to \(arguments[0]).")
        print("No HID device was opened.")

    case "keymap-library-bundle-import":
        var arguments = Array(args.dropFirst(2))
        let directory = try keymapLibraryDirectory(from: &arguments)
        guard arguments.count == 1 else {
            printUsage()
            return
        }
        let importedSlots = try importKeymapLibraryBundle(arguments[0], directory: directory)
        print("Imported \(importedSlots.count) keymap library entr\(importedSlots.count == 1 ? "y" : "ies") into \(directory.path).")
        if !importedSlots.isEmpty {
            print("Slots: \(importedSlots.joined(separator: ", "))")
        }
        print("No HID device was opened.")

    case "keymap-map-apply":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        let remaps = try parseKeymapRemapSpecs(options.operands)
        let sequence = keymapFeatureSequence(table: try keymapRemapTable(remaps))
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("This writes a full custom-keymap table containing \(remaps.count) simple remap(s).")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate multi-remap keymap sequence sent.")

    case "keymap-apply":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        guard options.operands.count == 2 || options.operands.count == 3 else {
            printUsage()
            return
        }
        let source = try keyByArgument(options.operands[0])
        let targetUsage = try hidUsageByArgument(options.operands[1])
        let modifierUsage = options.operands.count == 3 ? try hidUsageByArgument(options.operands[2]) : nil
        let table = try keymapSimpleRemapTable(source: source, targetUsage: targetUsage, modifierUsage: modifierUsage)
        let sequence = keymapFeatureSequence(table: table)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("This writes a full custom-keymap table containing only the requested remap.")
        print(String(
            format: "Writing %@ -> HID 0x%02X on scanned interface %d using %d feature reports...",
            source.name,
            targetUsage,
            options.writeIndex,
            sequence.count
        ))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate keymap write sequence sent.")

    case "keymap-clear":
        let options = try parseUnsafeKeymapOptions(Array(args.dropFirst(2)))
        guard options.operands.isEmpty else {
            printUsage()
            return
        }
        let sequence = keymapFeatureSequence(table: emptyKeymapTable())
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex) else {
            throw DriverError.noDevice
        }
        let device = try driver.device(at: options.writeIndex, configurationOnly: false)
        print("WARNING: writing keymaps is not yet backed by a proven device readback/backup path.")
        print("Writing an empty custom-keymap table; this is expected to clear custom remaps.")
        print(String(format: "Writing on scanned interface %d using %d feature reports...", options.writeIndex, sequence.count))
        try sendFeatureSequence(driver: driver, device: device, payloads: sequence)
        print("Candidate empty keymap sequence sent.")

    case "short-op-template":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let variant = args.count == 4 ? args[3] : "empty"
        let sequence = try shortOperationTemplateFeatureSequence(variant: variant)
        try writeFeatureSequenceFile(sequence, path: args[2])
        print("Saved \(sequence.count) candidate short-op feature reports to \(args[2]). No HID device was opened.")
        print("This models the Windows 04 18 / 04 13 / payload / 04 02 / 04 F0 sequence with template variant \(variant).")
        print("Known variants: empty, static-80. Live apply is guarded by \(unsafeKeymapFlag).")

    case "short-op-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        _ = try validateShortOperationFeatureSequenceFile(args[2])

    case "short-op-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "short-op")
        let sequence = try validateShortOperationFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "short-op")

    case "keyboard-settings-export":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let path = args[2]
        var profile: UInt8 = 0
        var specs: [String] = []
        for argument in args.dropFirst(3) {
            if argument.hasPrefix("--profile=") {
                profile = try parseOneByteLiteral(String(argument.dropFirst("--profile=".count)), field: "keyboard-settings profile")
            } else {
                specs.append(argument)
            }
        }
        let assignments = try parseKeyboardSettingsAssignmentSpecs(specs)
        let sequence = try keyboardSettingsFeatureSequence(profile: profile, payload: try keyboardSettingsPayload(assignments: assignments))
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate keyboard-settings feature reports to \(path). No HID device was opened.")
        print("This models the Windows 04 18 / 04 17 / payload / 04 02 sequence with profile byte 0x\(String(format: "%02X", profile)).")
        print("Known named fields: gamemode, disable-alttab, disable-altf4, disable-win, fn-switchfunction, sleep-light.")
        print("Raw writable payload bytes are offsets 0x00...0x3D; offsets 0x3E...0x3F contain the AA 55 marker.")
        for assignment in assignments {
            print(String(format: "  %@ = %02X", assignment.label, assignment.value))
        }

    case "keyboard-settings-validate":
        guard args.count == 3 else {
            printUsage()
            return
        }
        _ = try validateKeyboardSettingsFeatureSequenceFile(args[2])

    case "keyboard-settings-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "keyboard settings")
        let sequence = try validateKeyboardSettingsFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "keyboard settings")

    case "lighting-custom-rgb-export":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let path = args[2]
        let keyMap = keyMapByLightIndex()
        let assignments = args.count > 3 ? try parseRGBAssignmentSpecs(Array(args.dropFirst(3)), keyMap: keyMap) : []
        let table = try customLightingRGBTable(assignments: assignments)
        let sequence = customLightingRGBFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate custom-lighting RGB feature reports to \(path). No HID device was opened.")
        print("This is an offline artifact for the 04 23 extended/custom-RGB path. Live apply is guarded by \(unsafeKeymapFlag).")
        for assignment in assignments {
            print(String(
                format: "  %@ (0x%02X) = %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }

    case "lighting-custom-rgb-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateCustomLightingRGBFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printRGBRecordsJSON(Array(sequence[2...10]), keyByLightIndex: keyMapByLightIndex(), recordByteLimit: 0x23E)
        }

    case "lighting-custom-rgb-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "custom-lighting RGB")
        let sequence = try validateCustomLightingRGBFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "custom-lighting RGB")

    case "lighting-mode-export":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let path = args[2]
        let keyMap = keyMapByLightIndex()
        let assignments = args.count > 3 ? try parseByteAssignmentSpecs(Array(args.dropFirst(3)), keyMap: keyMap) : []
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate lighting-mode feature reports to \(path). No HID device was opened.")
        print("This is an offline artifact for the 04 23 selector-03 table path. Live apply is guarded by \(unsafeKeymapFlag).")
        for assignment in assignments {
            print(String(format: "  %@ (0x%02X) = %02X", assignment.label, assignment.index, assignment.value))
        }

    case "lighting-mode-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printLightingModePresetList()

    case "lighting-mode-preset-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let preset = try lightingModePreset(named: args[3])
        let assignments = try lightingModePresetAssignments(preset)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate lighting-mode preset \(preset.name) to \(path). No HID device was opened.")
        print("\(preset.title): \(preset.description)")
        for assignment in assignments {
            print(String(format: "  %@ (0x%02X) = %02X", assignment.label, assignment.index, assignment.value))
        }

    case "lighting-mode-preset-apply":
        let options = try parseUnsafeCandidateNameOptions(Array(args.dropFirst(2)), kind: "lighting-mode preset")
        let preset = try lightingModePreset(named: options.name)
        let assignments = try lightingModePresetAssignments(preset)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        print("Applying candidate lighting-mode preset \(preset.name): \(preset.description)")
        for assignment in assignments {
            print(String(format: "  %@ (0x%02X) = %02X", assignment.label, assignment.index, assignment.value))
        }
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "lighting-mode preset")

    case "lighting-effect-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printLightingEffectList()

    case "lighting-effect-export":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let effect = try lightingEffect(named: args[3])
        let assignments = lightingEffectAssignments(effect)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate lighting effect \(effect.name) to \(path). No HID device was opened.")
        print(String(format: "%@ maps all %d known physical keys to selector-03 value 0x%02X.", effect.title, assignments.count, effect.value))
        print("This is an offline artifact for the 04 23 selector-03 table path. Live apply is guarded by \(unsafeKeymapFlag).")

    case "lighting-effect-apply":
        let options = try parseUnsafeCandidateNameOptions(Array(args.dropFirst(2)), kind: "lighting effect")
        let effect = try lightingEffect(named: options.name)
        let assignments = lightingEffectAssignments(effect)
        let table = try lightingModeTable(assignments: assignments)
        let sequence = lightingModeFeatureSequence(table: table)
        print(String(format: "Applying candidate lighting effect %@: all %d known physical keys -> selector-03 value 0x%02X.", effect.name, assignments.count, effect.value))
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "lighting effect")

    case "effect-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printEffectPresetList()

    case "effect-apply":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let effect = try lightingEffect(named: args[2])
        throw DriverError.invalidArgument(
            "Animated effect apply is not proven yet for \(effect.name). The old one-click command only sent a candidate selector-03 table and may not change visible lighting. Use RGB presets for proven color changes, or use lighting-effect-export / lighting-effect-apply --unsafe-no-backup for controlled protocol tests."
        )

    case "lighting-mode-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateLightingModeFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printByteRecordsJSON(Array(sequence[2...4]), byteLimit: 0xBE, keyByLightIndex: keyMapByLightIndex())
        }

    case "lighting-mode-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "lighting-mode")
        let sequence = try validateLightingModeFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "lighting-mode")

    case "alternate-table-export":
        guard args.count >= 4 else {
            printUsage()
            return
        }
        let path = args[2]
        let remaps = try parseKeymapRemapSpecs(Array(args.dropFirst(3)))
        let table = try keymapRemapTable(remaps)
        let sequence = alternateFullTableFeatureSequence(table: table)
        try writeFeatureSequenceFile(sequence, path: path)
        print("Saved \(sequence.count) candidate 04 27 alternate full-table feature reports to \(path). No HID device was opened.")
        print("This is an offline artifact for the alternate full-table path. Live apply is guarded by \(unsafeKeymapFlag).")
        for remap in remaps {
            print("  \(keymapRemapSummary(remap))")
        }

    case "alternate-table-validate":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let sequence = try validateAlternateFullTableFeatureSequenceFile(args[2], printSummary: !wantsJSON)
        if wantsJSON {
            try printKeymapRecordsJSON(sequence)
        }

    case "alternate-table-apply":
        let options = try parseUnsafeCandidateFileOptions(Array(args.dropFirst(2)), kind: "alternate full-table")
        let sequence = try validateAlternateFullTableFeatureSequenceFile(options.path)
        try sendUnsafeCandidateFeatureSequence(sequence, writeIndex: options.writeIndex, kind: "alternate full-table")

    case "feature-get":
        guard args.count == 4, let reportID = Int(args[2], radix: 16), let length = Int(args[3]) else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let bytes = try driver.getFeature(reportID: reportID, length: length)
        print(hex(bytes))

    case "feature-get-at":
        guard
            args.count == 5,
            let index = Int(args[2]),
            let reportID = Int(args[3], radix: 16),
            let length = Int(args[4])
        else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let device = try driver.device(at: index, configurationOnly: true)
        let bytes = try driver.getFeature(device: device, reportID: reportID, length: length)
        print(hex(bytes))

    case "feature-scan":
        let index = args.count > 2 ? Int(args[2]) : 0
        let start = args.count > 3 ? Int(args[3], radix: 16) : 0
        let end = args.count > 4 ? Int(args[4], radix: 16) : 0xFF
        let length = args.count > 5 ? Int(args[5]) : 64
        guard
            args.count <= 6,
            let index,
            let start,
            let end,
            let length,
            start <= end,
            length > 0
        else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let device = try driver.device(at: index, configurationOnly: true)
        for reportID in start...end {
            do {
                let bytes = try driver.getFeature(device: device, reportID: reportID, length: length)
                let meaningful = bytes.contains { $0 != 0 }
                print(String(
                    format: "0x%02X  ok  len=%3d  %@%@",
                    reportID,
                    bytes.count,
                    meaningful ? "" : "(all zero) ",
                    hex(bytes)
                ))
            } catch DriverError.getReportFailed {
                continue
            }
        }

    case "input-listen":
        let index = args.count > 2 ? Int(args[2]) : 0
        let length = args.count > 3 ? Int(args[3]) : nil
        let seconds = args.count > 4 ? Double(args[4]) : 10.0
        guard args.count <= 5, let index, let seconds, seconds > 0 else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let infos = driver.configurationDevices()
        guard infos.indices.contains(index) else { throw DriverError.noDevice }
        let reportLength = length ?? max(infos[index].maxInputReportSize, 1)
        guard reportLength > 0 else { throw DriverError.invalidArgument("Input report length must be positive.") }
        let device = try driver.device(at: index, configurationOnly: true)
        print(String(format: "Listening on configuration interface %d for %.1f seconds...", index, seconds))
        try driver.listenInput(device: device, length: reportLength, seconds: seconds)

    case "key-test":
        let index = args.count > 2 ? Int(args[2]) : 0
        let length = args.count > 3 ? Int(args[3]) : nil
        let seconds = args.count > 4 ? Double(args[4]) : 10.0
        guard args.count <= 5, let index, let seconds, seconds > 0 else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let infos = driver.configurationDevices()
        guard infos.indices.contains(index) else { throw DriverError.noDevice }
        let reportLength = length ?? max(infos[index].maxInputReportSize, 8)
        guard reportLength >= 8 else {
            throw DriverError.invalidArgument("Key test report length must be at least 8 bytes.")
        }
        let device = try driver.device(at: index, configurationOnly: true)
        print(String(format: "Key test on configuration interface %d for %.1f seconds...", index, seconds))
        print("Press keys on the GMK67. Reports are decoded as boot keyboard modifiers/usages.")
        try driver.listenKeyboardInput(device: device, length: reportLength, seconds: seconds)

    case "input-get-at":
        guard
            args.count == 5,
            let index = Int(args[2]),
            let reportID = Int(args[3], radix: 16),
            let length = Int(args[4])
        else {
            printUsage()
            return
        }
        let driver = HIDDriver()
        let device = try driver.device(at: index, configurationOnly: false)
        let bytes = try driver.getInput(device: device, reportID: reportID, length: length)
        print(hex(bytes))

    case "feature-set":
        guard args.count == 4, let reportID = Int(args[2], radix: 16) else {
            printUsage()
            return
        }
        let payload = try parseHexBytes(args[3])
        let driver = HIDDriver()
        try driver.setFeature(reportID: reportID, payload: payload)
        print("Wrote \(payload.count) bytes to feature report 0x\(String(format: "%02X", reportID)).")

    case "feature-set64":
        guard args.count == 4, let reportID = Int(args[2], radix: 16) else {
            printUsage()
            return
        }
        var payload = try parseHexBytes(args[3])
        guard payload.count <= 64 else {
            throw DriverError.invalidArgument("feature-set64 payload must be 64 bytes or fewer before padding.")
        }
        payload += [UInt8](repeating: 0, count: 64 - payload.count)
        let driver = HIDDriver()
        try driver.setFeature(reportID: reportID, payload: payload)
        print("Wrote 64 bytes to feature report 0x\(String(format: "%02X", reportID)).")

    case "rgb-read-probe":
        let writeIndex = args.count > 2 ? Int(args[2]) : 0
        let listenIndex = args.count > 3 ? Int(args[3]) : 1
        let chunks = args.count > 4 ? Int(args[4]) : 3
        let seconds = args.count > 5 ? Double(args[5]) : 2.0
        guard
            args.count <= 6,
            let writeIndex,
            let listenIndex,
            let chunks,
            let seconds,
            chunks > 0,
            chunks <= 9,
            seconds > 0
        else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let infos = driver.configurationDevices()
        guard infos.indices.contains(writeIndex), infos.indices.contains(listenIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: true)
        let listenDevice = try driver.device(at: listenIndex, configurationOnly: true)
        let listenLength = max(infos[listenIndex].maxInputReportSize, 1)
        var payload = [UInt8](repeating: 0, count: 64)
        payload[0] = 0x04
        payload[1] = 0xF5
        payload[8] = UInt8(chunks)
        print(String(
            format: "Listening on interface %d for %.1f seconds, then probing via feature interface %d...",
            listenIndex,
            seconds,
            writeIndex
        ))
        try driver.listenAfterWrite(
            listenDevice: listenDevice,
            listenLength: listenLength,
            seconds: seconds,
            writeDevice: writeDevice,
            payload: payload
        )

    case "rgb-read-get-probe":
        let writeIndex = args.count > 2 ? Int(args[2]) : 0
        let readIndex = args.count > 3 ? Int(args[3]) : 0
        let readReportID = args.count > 4 ? Int(args[4], radix: 16) : 0
        let length = args.count > 5 ? Int(args[5]) : 64
        let chunks = args.count > 6 ? Int(args[6]) : 3
        guard
            args.count <= 7,
            let writeIndex,
            let readIndex,
            let readReportID,
            let length,
            let chunks,
            length > 0,
            chunks > 0,
            chunks <= 9
        else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        var payload = [UInt8](repeating: 0, count: 64)
        payload[0] = 0x04
        payload[1] = 0xF5
        payload[8] = UInt8(chunks)
        try driver.setFeature(device: writeDevice, reportID: 0, payload: payload)
        print("Sent feature report 0x00 on scanned interface \(writeIndex): \(hex(payload))")
        for attempt in 1...chunks {
            usleep(50_000)
            do {
                let bytes = try driver.getInput(device: readDevice, reportID: readReportID, length: length)
                print(String(format: "#%03d report=0x%02X len=%3d  %@", attempt, readReportID, bytes.count, hex(bytes)))
            } catch {
                print("#\(String(format: "%03d", attempt)) error: \(error)")
            }
        }

    case "rgb-dump":
        var dumpArgs = Array(args.dropFirst(2))
        var wantsJSON = false
        if let jsonIndex = dumpArgs.firstIndex(of: "--json") {
            dumpArgs.remove(at: jsonIndex)
            wantsJSON = true
        }
        let writeIndex = dumpArgs.count > 0 ? Int(dumpArgs[0]) : 0
        let readIndex = dumpArgs.count > 1 ? Int(dumpArgs[1]) : 0
        let chunks = dumpArgs.count > 2 ? Int(dumpArgs[2]) : 9
        guard
            dumpArgs.count <= 3,
            let writeIndex,
            let readIndex,
            let chunks,
            chunks > 0,
            chunks <= 9
        else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        var payload = [UInt8](repeating: 0, count: 64)
        payload[0] = 0x04
        payload[1] = 0xF5
        payload[8] = UInt8(chunks)
        try driver.setFeature(device: writeDevice, reportID: 0, payload: payload)

        var frames: [[UInt8]] = []
        for chunk in 1...chunks {
            usleep(50_000)
            let bytes = try driver.getInput(device: readDevice, reportID: 0, length: 64)
            frames.append(bytes)
            if !wantsJSON {
                if chunk == 1 {
                    print("Sent RGB readback request for \(chunks) chunks.")
                }
                print(String(format: "#%03d len=%3d  %@", chunk, bytes.count, hex(bytes)))
            }
        }
        if wantsJSON {
            try printRGBRecordsJSON(frames, keyByLightIndex: keyMapByLightIndex())
        } else {
            print("Non-zero RGB records:")
            printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())
        }

    case "rgb-set-key":
        guard args.count >= 4, args.count <= 6 else {
            printUsage()
            return
        }
        let keyArgument = args[2]
        let colorBytes = try parseHexBytes(args[3])
        guard colorBytes.count == 3 else {
            throw DriverError.invalidArgument("Color must be exactly three bytes, for example FF0000 or FF 00 00.")
        }
        let writeIndex = args.count > 4 ? Int(args[4]) : 0
        let readIndex = args.count > 5 ? Int(args[5]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let keyMap = keyMapByLightIndex()
        let target = try lightTargetByArgument(keyArgument, keyMap: keyMap)
        let lightIndex = target.lightIndex

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)

        var frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(frames)
        print("Saved pre-write RGB table to \(backupPath).")

        try setRGBRecord(frames: &frames, lightIndex: lightIndex, color: colorBytes)

        let keyLabel = target.label
        print(String(format: "Setting %@ (0x%02X) to %02X %02X %02X", keyLabel, lightIndex, colorBytes[0], colorBytes[1], colorBytes[2]))
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")

        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let records = rgbFramesToRecords(verifyFrames)
        if let record = records[lightIndex] {
            print(String(
                format: "Rendered readback 0x%02X %@ rgb=%02X %02X %02X",
                lightIndex,
                keyLabel,
                record.red,
                record.green,
                record.blue
            ))
        }
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the bytes sent.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMap)

    case "rgb-map":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let options = try parseRGBMapOptions(Array(args.dropFirst(2)))
        let keyMap = keyMapByLightIndex()
        let assignments = try parseRGBAssignmentSpecs(options.specs, keyMap: keyMap)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex), devices.indices.contains(options.readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: options.writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: options.readIndex, configurationOnly: false)

        var frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(frames)
        print("Saved pre-write RGB table to \(backupPath).")

        try applyRGBAssignments(assignments, to: &frames)
        for assignment in assignments {
            print(String(
                format: "Setting %@ (0x%02X) to %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")

        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the bytes sent.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMap)

    case "rgb-file-map":
        guard args.count >= 5 else {
            printUsage()
            return
        }
        let inputPath = args[2]
        let outputPath = args[3]
        let keyMap = keyMapByLightIndex()
        let assignments = try parseRGBAssignmentSpecs(Array(args.dropFirst(4)), keyMap: keyMap)
        var frames = try readRGBFramesFile(inputPath)
        try applyRGBAssignments(assignments, to: &frames)
        try writeRGBFramesFile(frames, path: outputPath)
        print("Saved edited RGB table to \(outputPath). No HID device was opened.")
        for assignment in assignments {
            print(String(
                format: "  %@ (0x%02X) = %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }

    case "rgb-profile-create":
        guard args.count >= 3 else {
            printUsage()
            return
        }
        let outputPath = args[2]
        let keyMap = keyMapByLightIndex()
        let options = try parseRGBProfileCreateOptions(Array(args.dropFirst(3)))
        let assignments = options.specs.isEmpty ? [] : try parseRGBAssignmentSpecs(options.specs, keyMap: keyMap)
        var frames = sampleRGBFrames()
        if let fillColor = options.fillColor {
            try applyRGBFill(fillColor, to: &frames, keyMap: physicalKeysByLightIndex())
            print(String(
                format: "Filled known physical keys with %02X %02X %02X.",
                fillColor[0],
                fillColor[1],
                fillColor[2]
            ))
        }
        try applyRGBAssignments(assignments, to: &frames)
        try writeRGBFramesFile(frames, path: outputPath)
        print("Saved RGB profile to \(outputPath). No HID device was opened.")
        for assignment in assignments {
            print(String(
                format: "  %@ (0x%02X) = %02X %02X %02X",
                assignment.label,
                assignment.lightIndex,
                assignment.color[0],
                assignment.color[1],
                assignment.color[2]
            ))
        }

    case "rgb-preset-list":
        guard args.count == 2 else {
            printUsage()
            return
        }
        printRGBPresetList()

    case "rgb-preset-show":
        guard args.count == 3 || args.count == 4 else {
            printUsage()
            return
        }
        let preset = try rgbPreset(named: args[2])
        if args.count == 4 {
            guard args[3] == "--json" else {
                printUsage()
                return
            }
            try printRGBPresetJSON(preset)
        } else {
            printRGBPreset(preset)
        }

    case "rgb-preset-create":
        guard args.count == 4 else {
            printUsage()
            return
        }
        let outputPath = args[2]
        let preset = try rgbPreset(named: args[3])
        let frames = try rgbPresetFrames(preset)
        try writeRGBFramesFile(frames, path: outputPath)
        print("Saved RGB preset \(preset.name) to \(outputPath). No HID device was opened.")
        print("\(preset.title): \(preset.description)")
        print("Non-zero RGB records:")
        printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-preset-apply":
        guard args.count >= 3, args.count <= 5 else {
            printUsage()
            return
        }
        let preset = try rgbPreset(named: args[2])
        let writeIndex = args.count > 3 ? Int(args[3]) : 0
        let readIndex = args.count > 4 ? Int(args[4]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)

        let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(currentFrames)
        print("Saved pre-write RGB table to \(backupPath).")

        let frames = try rgbPresetFrames(preset)
        print("Applying RGB preset \(preset.name): \(preset.description)")
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")

        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the preset bytes.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-file-dump":
        let wantsJSON = args.contains("--json")
        guard args.count == 3 || (args.count == 4 && wantsJSON) else {
            printUsage()
            return
        }
        let frames = try readRGBFramesFile(args[2])
        if wantsJSON {
            try printRGBRecordsJSON(frames, keyByLightIndex: keyMapByLightIndex())
        } else {
            print("Loaded \(frames.count) RGB frames from \(args[2]).")
            print("Non-zero RGB records:")
            printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())
        }

    case "rgb-set-all", "rgb-clear":
        let colorBytes: [UInt8]
        let writeIndexArgument: Int
        if command == "rgb-clear" {
            colorBytes = [0, 0, 0]
            writeIndexArgument = 2
        } else {
            guard args.count >= 3 else {
                printUsage()
                return
            }
            let parsedColor = try parseHexBytes(args[2])
            guard parsedColor.count == 3 else {
                throw DriverError.invalidArgument("Color must be exactly three bytes, for example FF0000 or FF 00 00.")
            }
            colorBytes = parsedColor
            writeIndexArgument = 3
        }
        let writeIndex = args.count > writeIndexArgument ? Int(args[writeIndexArgument]) : 0
        let readIndex = args.count > writeIndexArgument + 1 ? Int(args[writeIndexArgument + 1]) : 0
        guard args.count <= writeIndexArgument + 2, let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let keyMap = physicalKeysByLightIndex()
        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        var frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(frames)
        print("Saved pre-write RGB table to \(backupPath).")
        for lightIndex in keyMap.keys {
            try setRGBRecord(frames: &frames, lightIndex: lightIndex, color: colorBytes)
        }

        print(String(
            format: "Setting %d physical keys to %02X %02X %02X",
            keyMap.count,
            colorBytes[0],
            colorBytes[1],
            colorBytes[2]
        ))
        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Write sequence sent. Reading rendered table back...")
        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the bytes sent.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-save":
        guard args.count >= 3, args.count <= 5 else {
            printUsage()
            return
        }
        let path = args[2]
        let writeIndex = args.count > 3 ? Int(args[3]) : 0
        let readIndex = args.count > 4 ? Int(args[4]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        let frames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        try writeRGBFramesFile(frames, path: path)
        print("Saved \(frames.count) RGB frames to \(path).")
        print("Non-zero RGB records:")
        printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-restore":
        guard args.count >= 3, args.count <= 5 else {
            printUsage()
            return
        }
        let path = args[2]
        let writeIndex = args.count > 3 ? Int(args[3]) : 0
        let readIndex = args.count > 4 ? Int(args[4]) : 0
        guard let writeIndex, let readIndex else {
            printUsage()
            return
        }
        let frames = try readRGBFramesFile(path)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(writeIndex), devices.indices.contains(readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: readIndex, configurationOnly: false)
        let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(currentFrames)
        print("Saved pre-restore RGB table to \(backupPath).")

        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Restored RGB table from \(path). Reading rendered table back...")
        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the file bytes.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-restore-dry-run":
        guard args.count == 3 else {
            printUsage()
            return
        }
        let frames = try readRGBFramesFile(args[2])
        print("RGB restore dry run: \(args[2]) is valid with \(frames.count) 64-byte frame(s).")
        print("Dry run only: no HID device was opened and no reports were sent.")
        print("Non-zero RGB records:")
        printRGBRecords(frames, keyByLightIndex: keyMapByLightIndex())

    case "rgb-backups":
        guard args.count == 2 || args.count == 3 else {
            printUsage()
            return
        }
        let directory = args.count == 3 ? args[2] : "."
        let backups = rgbBackupFiles(directoryPath: directory)
        if backups.isEmpty {
            print("No valid RGB backup files found in \(directory).")
        } else {
            print("Valid RGB backups in \(directory):")
            for backup in backups {
                print("  \(backup.url.path)  frames=\(backup.frameCount)")
            }
        }
        print("No HID device was opened.")

    case "rgb-restore-latest":
        let options = try parseRGBRestoreLatestOptions(Array(args.dropFirst(2)))
        let backup = try latestRGBBackup(directoryPath: options.directory)
        let frames = try readRGBFramesFile(backup.url.path)

        let driver = HIDDriver()
        let devices = driver.devices()
        guard devices.indices.contains(options.writeIndex), devices.indices.contains(options.readIndex) else {
            throw DriverError.noDevice
        }
        let writeDevice = try driver.device(at: options.writeIndex, configurationOnly: false)
        let readDevice = try driver.device(at: options.readIndex, configurationOnly: false)
        let currentFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        let backupPath = try backupRGBFrames(currentFrames)
        print("Saved pre-restore RGB table to \(backupPath).")

        try writeRGBFrames(driver: driver, writeDevice: writeDevice, frames: frames)
        print("Restored latest RGB backup from \(backup.url.path). Reading rendered table back...")
        let verifyFrames = try readRGBFrames(driver: driver, writeDevice: writeDevice, readDevice: readDevice)
        print("Note: rendered readback may be scaled or mode-composited and may not exactly echo the backup file bytes.")
        print("Non-zero RGB records:")
        printRGBRecords(verifyFrames, keyByLightIndex: keyMapByLightIndex())

    case "help", "--help", "-h":
        printUsage()

    default:
        printUsage()
    }
}
