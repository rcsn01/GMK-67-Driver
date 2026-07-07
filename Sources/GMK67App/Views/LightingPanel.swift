import SwiftUI

struct LightingPanel: View {
    @ObservedObject var model: DriverModel
    private let builtInLightingEffects = [
        "static", "single-on", "single-off", "glittering", "falling", "colourful",
        "breath", "spectrum", "outward", "scrolling", "rolling", "rotating",
        "explode", "launch", "ripples", "flowing", "pulsating", "tilt", "shuttle", "led-off"
    ]
    private let lightingModePresets = ["empty", "wasd-steps", "nav-steps", "row-steps"]

    var body: some View {
        Panel("Lighting") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Custom RGB")
                        TextField("W=FF0000 A=00FF00", text: $model.lightingSpecs)
                            .textFieldStyle(.roundedBorder)
                        CommandButton("Export", systemImage: "doc.badge.plus") {
                            model.exportCustomLightingProfile()
                        }
                        CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                            model.validateCustomLightingProfile()
                        }
                        CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                            model.loadCustomLightingProfileIntoEditor()
                        }
                        CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                            model.applyCustomLightingProfile()
                        }
                    }
                    HStack {
                        Text("Brightness")
                        Slider(value: $model.lightingBrightnessPercent, in: 0...100, step: 1)
                            .frame(width: 180)
                        Text("\(Int(model.lightingBrightnessPercent.rounded()))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                HStack {
                    Text("Built-in Effect")
                    Picker("", selection: $model.lightingEffectName) {
                        ForEach(builtInLightingEffects, id: \.self) { effect in
                            Text(effect).tag(effect)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    Text("Color")
                    ColorPicker("", selection: Binding(
                        get: { model.lightingEffectColor },
                        set: {
                            model.lightingEffectColor = $0
                            model.lightingEffectColorHex = rgbHex($0)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
                    TextField("FFFFFF", text: $model.lightingEffectColorHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportLightingEffectProfile()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyLightingEffect()
                    }
                }

                HStack {
                    Text("Test Pattern")
                    Picker("", selection: $model.lightingModePresetName) {
                        ForEach(lightingModePresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportLightingModePresetProfile()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyLightingModePreset()
                    }
                }

                HStack {
                    Text("Mode Table")
                    TextField("W=01 A=02", text: $model.lightingModeSpecs)
                        .textFieldStyle(.roundedBorder)
                    CommandButton("Export", systemImage: "doc.badge.plus") {
                        model.exportLightingModeProfile()
                    }
                    CommandButton("Validate", systemImage: "doc.text.magnifyingglass") {
                        model.validateLightingModeProfile()
                    }
                    CommandButton("Load File", systemImage: "square.and.arrow.down.on.square") {
                        model.loadLightingModeProfileIntoEditor()
                    }
                    CommandButton("Apply", systemImage: "exclamationmark.triangle") {
                        model.applyLightingModeProfile()
                    }
                }

                Toggle("Allow unsafe lighting writes", isOn: $model.unsafeKeymapWrites)
                    .toggleStyle(.checkbox)

                Text("Custom lighting profiles and test-pattern writes require the unsafe toggle. Built-in effects use the confirmed mode+color path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.deviceStatusKind != .ready {
                    Text("Live lighting writes are disabled until the Device status is ready. Export and validate commands remain available.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
