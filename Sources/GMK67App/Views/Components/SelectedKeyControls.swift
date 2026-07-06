import SwiftUI

struct SelectedKeyColorControls: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Selected Key Color") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Key")
                    Text(model.selectedVisualKey)
                        .monospaced()
                        .frame(width: 90, alignment: .leading)
                    ColorPicker("", selection: Binding(
                        get: { model.keyColor },
                        set: {
                            model.keyColor = $0
                            model.colorHex = rgbHex($0)
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44)
                    TextField("FF0000", text: $model.colorHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    CommandButton("Apply Color", systemImage: "paintbrush") {
                        model.assignSelectedKeyColor()
                    }
                    CommandButton("No Color", systemImage: "lightswitch.off") {
                        model.clearSelectedKeyColor()
                    }
                }
            }
        }
    }
}

struct SelectedKeyRemapControls: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Selected Key Remap") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Source")
                    Text(model.selectedVisualKey)
                        .monospaced()
                        .frame(width: 90, alignment: .leading)
                    Text("Target")
                    TextField("B", text: $model.targetKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Text("Modifier")
                    TextField("shift", text: $model.modifierKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    CommandButton("Set Remap", systemImage: "arrow.triangle.branch") {
                        model.assignSelectedKeyRemap()
                    }
                    CommandButton("Clear", systemImage: "xmark.circle") {
                        model.clearSelectedKeyRemap()
                    }
                }
            }
        }
    }
}
