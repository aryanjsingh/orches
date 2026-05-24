import AppKit

struct IconTileItem: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: ProviderIcon
}

extension IconTileItem {
    static func from(_ provider: Provider) -> IconTileItem {
        IconTileItem(id: provider.id, title: provider.title, icon: provider.icon)
    }
}

final class IconTileView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectionLine = NSView()
    private let selectionBackground = NSView()
    private let icon: ProviderIcon

    var isSelected = false {
        didSet { updateSelectionAppearance() }
    }

    var onSelect: (() -> Void)?

    init(item: IconTileItem) {
        icon = item.icon
        super.init(frame: .zero)
        titleLabel.stringValue = item.title
        iconView.image = item.icon.makeImage(pointSize: 24)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true

        selectionBackground.wantsLayer = true
        selectionBackground.layer?.cornerRadius = 8
        selectionBackground.layer?.backgroundColor = NSColor.clear.cgColor

        selectionLine.wantsLayer = true
        selectionLine.layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        iconView.imageScaling = .scaleNone
        iconView.wantsLayer = true
        iconView.layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        [selectionBackground, iconView, titleLabel, selectionLine].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            selectionBackground.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            selectionBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            selectionBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            selectionBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),

            selectionLine.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            selectionLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            selectionLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            selectionLine.heightAnchor.constraint(equalToConstant: 2),
            selectionLine.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        updateSelectionAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateSelectionAppearance() {
        let accent = NSColor.controlAccentColor
        selectionBackground.layer?.backgroundColor = isSelected
            ? accent.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        selectionLine.layer?.backgroundColor = isSelected ? accent.cgColor : NSColor.clear.cgColor
        titleLabel.textColor = isSelected ? accent : .secondaryLabelColor

        switch icon {
        case .systemSymbol:
            iconView.contentTintColor = isSelected ? accent : .labelColor
        case .bundledSVG(_, let tintable):
            if tintable {
                iconView.contentTintColor = isSelected ? accent : .labelColor
            } else {
                iconView.contentTintColor = nil
            }
        }
    }
}

final class IconTileBarView: NSView {
    private let stackView = NSStackView()
    private var tiles: [IconTileView] = []
    private(set) var selectedIndex: Int = 0

    var onSelectionChanged: ((Int) -> Void)?

    init(items: [IconTileItem]) {
        super.init(frame: .zero)
        setup(items: items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(items: [IconTileItem]) {
        stackView.orientation = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        tiles = items.enumerated().map { index, item in
            let tile = IconTileView(item: item)
            tile.onSelect = { [weak self] in self?.select(index: index) }
            stackView.addArrangedSubview(tile)
            return tile
        }

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 58),
        ])

        select(index: 0, notify: false)
    }

    func select(index: Int, notify: Bool = true) {
        guard tiles.indices.contains(index) else { return }
        selectedIndex = index
        for (i, tile) in tiles.enumerated() {
            tile.isSelected = i == index
        }
        if notify {
            onSelectionChanged?(index)
        }
    }
}

enum IconTileBarFactory {
    static func providerBar() -> IconTileBarView {
        IconTileBarView(items: Provider.allCases.map(IconTileItem.from))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
