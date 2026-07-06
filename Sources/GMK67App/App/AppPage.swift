import Foundation

enum AppPage: String, CaseIterable, Identifiable, Hashable {
    case rgb
    case profiles
    case keymap
    case macros
    case device
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rgb: return "RGB"
        case .profiles: return "Profiles"
        case .keymap: return "Keymap"
        case .macros: return "Macros"
        case .device: return "Device"
        case .developer: return "Developer"
        }
    }

    var systemImage: String {
        switch self {
        case .rgb: return "paintpalette"
        case .profiles: return "rectangle.stack"
        case .keymap: return "arrow.triangle.branch"
        case .macros: return "text.badge.plus"
        case .device: return "keyboard"
        case .developer: return "hammer"
        }
    }

    static let userPages: [AppPage] = [.rgb, .profiles, .keymap, .macros, .device]
}
