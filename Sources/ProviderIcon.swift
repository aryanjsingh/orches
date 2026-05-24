import AppKit

enum ProviderIcon: Equatable {
    case systemSymbol(String)
    case bundledSVG(String, tintable: Bool)

    func makeImage(pointSize: CGFloat = 24) -> NSImage? {
        switch self {
        case .systemSymbol(let name):
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        case .bundledSVG(let name, let tintable):
            return SVGImageRenderer.image(named: name, pointSize: pointSize, tintable: tintable)
        }
    }
}

extension Bundle {
    static let orches: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()
}
