import SwiftUI

struct VisualKeyboardView: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Keyboard")
                    .font(.title3.weight(.semibold))
                Text(model.currentRGBStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(model.selectedVisualRGBStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(model.lastKeyStatus)
                    .font(.caption)
                    .foregroundStyle(model.pressedVisualKeys.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
            }

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visualKeyboardRows) { row in
                        HStack(spacing: 6) {
                            ForEach(row.keys) { key in
                                VisualKeyButton(
                                    key: key,
                                    isSelected: model.selectedVisualKey.caseInsensitiveCompare(key.spec) == .orderedSame,
                                    isPressed: model.isVisualKeyPressed(key.spec),
                                    colorHex: model.visualColorHex(for: key.spec),
                                    remap: remapForKey(key.spec, in: model.keymapSpecs)
                                ) {
                                    model.selectVisualKey(key.spec)
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
