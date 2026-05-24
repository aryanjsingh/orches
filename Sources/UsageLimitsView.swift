import AppKit

final class UsageLimitsView: NSView {
    private let tileBar = IconTileBarFactory.providerBar()
    private let separator = NSBox()
    private let detailLabel = MenuLabels.body("")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        tileBar.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tileBar)
        addSubview(separator)
        addSubview(detailLabel)

        tileBar.onSelectionChanged = { [weak self] index in
            guard let provider = Provider.allCases[safe: index] else { return }
            self?.showDetail(for: provider)
        }

        NSLayoutConstraint.activate([
            tileBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            tileBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tileBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            separator.topAnchor.constraint(equalTo: tileBar.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])

        if let provider = Provider.allCases[safe: tileBar.selectedIndex] {
            showDetail(for: provider)
        }
    }

    private func showDetail(for provider: Provider) {
        detailLabel.stringValue = "\(provider.title) usage limits and credits go here."
    }
}
