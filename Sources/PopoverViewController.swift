import AppKit

enum PopoverSection: Int, CaseIterable {
    case usageLimits = 0
    case proxy = 1

    var title: String {
        switch self {
        case .usageLimits: return "Usage Limits"
        case .proxy: return "Proxy"
        }
    }
}

final class PopoverViewController: NSViewController {
    private let segmentedControl = NSSegmentedControl(labels: PopoverSection.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let contentContainer = NSView()
    private let quitButton: NSButton = {
        let button = NSButton(title: "Quit Orches", target: nil, action: #selector(NSApplication.terminate(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = ""
        return button
    }()
    private let usageLimitsView = UsageLimitsView()
    private let proxyView: ProxyView

    init(proxyService: ProxyService) {
        self.proxyView = ProxyView(service: proxyService)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.proxyView = ProxyView(service: ProxyService())
        super.init(coder: coder)
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        segmentedControl.segmentDistribution = .fillEqually
        layoutViews()
        segmentedControl.selectedSegment = PopoverSection.usageLimits.rawValue
        segmentedControl.target = self
        segmentedControl.action = #selector(sectionChanged(_:))
        showSection(.usageLimits)
    }

    private func layoutViews() {
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        usageLimitsView.translatesAutoresizingMaskIntoConstraints = false
        proxyView.translatesAutoresizingMaskIntoConstraints = false

        quitButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(segmentedControl)
        view.addSubview(contentContainer)
        view.addSubview(quitButton)
        contentContainer.addSubview(usageLimitsView)
        contentContainer.addSubview(proxyView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            contentContainer.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 12),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -12),

            quitButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            quitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            quitButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            usageLimitsView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            usageLimitsView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            usageLimitsView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            usageLimitsView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            proxyView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            proxyView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            proxyView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            proxyView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        guard let section = PopoverSection(rawValue: sender.selectedSegment) else { return }
        showSection(section)
    }

    private func showSection(_ section: PopoverSection) {
        usageLimitsView.isHidden = section != .usageLimits
        proxyView.isHidden = section != .proxy
    }
}
