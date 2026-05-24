import AppKit

enum Provider: String, CaseIterable, Identifiable {
    case kiro
    case codex
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kiro: return "Kiro"
        case .codex: return "Codex"
        case .opencode: return "Opencode"
        }
    }

    var icon: ProviderIcon {
        switch self {
        case .kiro:
            // No brand SVG yet — SF Symbol placeholder.
            return .systemSymbol("bolt.circle")
        case .codex:
            return .bundledSVG("codex", tintable: false)
        case .opencode:
            return .bundledSVG("opencode", tintable: false)
        }
    }
}
