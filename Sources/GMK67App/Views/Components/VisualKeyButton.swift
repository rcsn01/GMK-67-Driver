import SwiftUI

struct VisualKeyButton: View {
    let key: VisualKey
    let isSelected: Bool
    let isPressed: Bool
    let colorHex: String?
    let remap: VisualRemap?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(keyFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPressed ? Color.green.opacity(0.20) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isPressed ? Color.green : Color.clear, lineWidth: 3)
                    )
                Text(key.label)
                    .font(.system(size: key.width > 70 ? 10 : 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if let remap {
                    Text(remap.badge)
                        .font(.system(size: key.width > 70 ? 9 : 8, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if let colorHex {
                    Rectangle()
                        .fill(colorFromHex(colorHex))
                        .frame(height: 5)
                        .clipShape(.rect(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                }
            }
            .frame(width: key.width, height: 38)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var keyFill: Color {
        if let colorHex {
            return colorFromHex(colorHex).opacity(0.34)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var helpText: String {
        let prefix = isPressed ? "Pressed: " : ""
        let colorText = colorHex.map { " RGB #\($0)" } ?? " RGB not loaded"
        if let remap {
            return "\(prefix)\(key.label) (\(key.spec))\(colorText) -> \(remap.target)\(remap.modifier.map { " + \($0)" } ?? "")"
        }
        let label = key.label == key.spec ? key.spec : "\(key.label) (\(key.spec))"
        return prefix + label + colorText
    }
}
