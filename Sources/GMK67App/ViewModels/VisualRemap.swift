import Foundation

struct VisualRemap {
    let target: String
    let modifier: String?

    var badge: String {
        let targetLabel = shortKeyLabel(target)
        guard let modifier, !modifier.isEmpty else {
            return "->\(targetLabel)"
        }
        return "\(shortKeyLabel(modifier))+\(targetLabel)"
    }
}

func remapForKey(_ key: String, in specs: String) -> VisualRemap? {
    guard let value = valueForSpecKey(key, in: specs) else { return nil }
    let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard let targetPart = parts.first else { return nil }
    let target = String(targetPart).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty else { return nil }
    let modifier: String?
    if parts.count == 2 {
        let parsed = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        modifier = parsed.isEmpty ? nil : parsed
    } else {
        modifier = nil
    }
    return VisualRemap(target: target, modifier: modifier)
}

private func shortKeyLabel(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch specKeyToken(normalized) {
    case "control", "ctrl":
        return "C"
    case "shift":
        return "S"
    case "alt", "option":
        return "A"
    case "command", "cmd", "win":
        return "M"
    case "left":
        return "L"
    case "right":
        return "R"
    case "up":
        return "U"
    case "down":
        return "D"
    case "escape":
        return "Esc"
    case "backspace":
        return "Bksp"
    case "pageup":
        return "PgU"
    case "pagedown":
        return "PgD"
    default:
        if normalized.count <= 4 {
            return normalized
        }
        return String(normalized.prefix(4))
    }
}
