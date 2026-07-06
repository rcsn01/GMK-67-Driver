import SwiftUI

struct VisualKeyboardPanel: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        Panel("Keyboard") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visualKeyboardRows) { row in
                        HStack(spacing: 6) {
                            ForEach(row.keys) { key in
                                VisualKeyButton(
                                    key: key,
                                    isSelected: model.selectedVisualKey.caseInsensitiveCompare(key.spec) == .orderedSame,
                                    colorHex: visualColorForKey(key.spec, in: model.mapSpecs, fillHex: model.profileFillHex),
                                    remap: remapForKey(key.spec, in: model.keymapSpecs)
                                ) {
                                    model.selectVisualKey(key.spec)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("Selected")
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
                        CommandButton("Color", systemImage: "paintbrush") {
                            model.assignSelectedKeyColor()
                        }
                        CommandButton("No Color", systemImage: "lightswitch.off") {
                            model.clearSelectedKeyColor()
                        }
                    }

                    GridRow {
                        Text("Remap")
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
                        CommandButton("Set", systemImage: "arrow.triangle.branch") {
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
}
