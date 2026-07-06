import SwiftUI

struct VisualKeyboardView: View {
    @ObservedObject var model: DriverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard")
                .font(.title3.weight(.semibold))

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
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
