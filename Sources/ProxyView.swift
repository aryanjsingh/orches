import AppKit

final class ProxyView: NSView {
    private let service: ProxyService
    private let tileBar = IconTileBarFactory.providerBar()
    private let separator = NSBox()
    private let stack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let tokenField = NSSecureTextField()
    private let autoDetectButton = NSButton(title: "Auto Detect", target: nil, action: nil)
    private let tokenButton = NSButton(title: "Save Manual", target: nil, action: nil)
    private let startStopButton = NSButton(title: "Start Proxy", target: nil, action: nil)
    private let baseURLField = NSTextField(labelWithString: "Base URL appears after start.")
    private let apiKeyField = NSTextField(labelWithString: "")
    private let copyBaseURLButton = NSButton(title: "Copy Base URL", target: nil, action: nil)
    private let copyAPIKeyButton = NSButton(title: "Copy API Key", target: nil, action: nil)
    private let revealAPIKeyButton = NSButton(title: "Reveal", target: nil, action: nil)
    private let errorLabel = MenuLabels.body("")
    private var apiKeyRevealed = false
    private var selectedProvider: Provider = .kiro

    init(service: ProxyService) {
        self.service = service
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.service = ProxyService()
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        separator.boxType = .separator
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        [tileBar, separator, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        configureControls()
        layoutContent()
        bindActions()

        service.onChange = { [weak self] in
            self?.refresh()
        }

        tileBar.onSelectionChanged = { [weak self] index in
            guard let provider = Provider.allCases[safe: index] else { return }
            self?.selectedProvider = provider
            self?.refresh()
        }

        refresh()
    }

    private func configureControls() {
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 6
        statusLabel.layer?.masksToBounds = true

        tokenField.placeholderString = "Optional manual Kiro refresh token"
        tokenField.font = .systemFont(ofSize: 12)

        [autoDetectButton, tokenButton, startStopButton, copyBaseURLButton, copyAPIKeyButton, revealAPIKeyButton].forEach {
            $0.bezelStyle = .rounded
            $0.font = .systemFont(ofSize: 12)
        }

        baseURLField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        baseURLField.lineBreakMode = .byTruncatingMiddle
        apiKeyField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        apiKeyField.lineBreakMode = .byTruncatingMiddle
        errorLabel.textColor = .secondaryLabelColor
    }

    private func layoutContent() {
        let tokenRow = row([autoDetectButton, tokenField, tokenButton], firstFills: false)
        let controlsRow = row([startStopButton, copyBaseURLButton], firstFills: false)
        let keyRow = row([apiKeyField, revealAPIKeyButton, copyAPIKeyButton], firstFills: true)

        [
            statusLabel,
            tokenRow,
            controlsRow,
            labelPair(title: "Base URL", value: baseURLField),
            labelPair(title: "API Key", value: keyRow),
            errorLabel,
        ].forEach { view in
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            tileBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            tileBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tileBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            separator.topAnchor.constraint(equalTo: tileBar.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            tokenField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            baseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    private func bindActions() {
        autoDetectButton.target = self
        autoDetectButton.action = #selector(autoDetectKiroAuth)
        tokenButton.target = self
        tokenButton.action = #selector(saveToken)
        startStopButton.target = self
        startStopButton.action = #selector(toggleProxy)
        copyBaseURLButton.target = self
        copyBaseURLButton.action = #selector(copyBaseURL)
        copyAPIKeyButton.target = self
        copyAPIKeyButton.action = #selector(copyAPIKey)
        revealAPIKeyButton.target = self
        revealAPIKeyButton.action = #selector(toggleAPIKeyReveal)
    }

    private func refresh() {
        let enabled = selectedProvider == .kiro
        autoDetectButton.isEnabled = enabled
        tokenField.isEnabled = enabled
        tokenButton.isEnabled = enabled
        startStopButton.isEnabled = enabled
        copyBaseURLButton.isEnabled = enabled && service.baseURL != nil
        copyAPIKeyButton.isEnabled = enabled
        revealAPIKeyButton.isEnabled = enabled

        if !enabled {
            statusLabel.stringValue = "\(selectedProvider.title) proxy coming soon"
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            errorLabel.stringValue = "Kiro is implemented first. Other proxy providers stay reserved."
            return
        }

        statusLabel.stringValue = "Kiro Proxy: \(service.status.title)"
        switch service.status {
        case .running:
            statusLabel.textColor = .systemGreen
            statusLabel.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
            startStopButton.title = "Stop Proxy"
            errorLabel.stringValue = service.authMessage
        case .starting:
            statusLabel.textColor = .controlAccentColor
            statusLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            startStopButton.title = "Starting..."
            errorLabel.stringValue = "Checking Kiro Keychain auth."
        case .failed(let message):
            statusLabel.textColor = .systemRed
            statusLabel.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
            startStopButton.title = "Start Proxy"
            errorLabel.stringValue = message
        case .stopped:
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            startStopButton.title = "Start Proxy"
            errorLabel.stringValue = service.authMessage
        }

        baseURLField.stringValue = service.baseURL ?? "Base URL appears after start."
        apiKeyField.stringValue = apiKeyRevealed ? service.currentAPIKey : masked(service.currentAPIKey)
        revealAPIKeyButton.title = apiKeyRevealed ? "Hide" : "Reveal"
    }

    @objc private func saveToken() {
        let token = tokenField.stringValue
        Task {
            do {
                try await service.saveToken(token)
                await MainActor.run {
                    tokenField.stringValue = ""
                    errorLabel.stringValue = "Kiro token saved."
                }
            } catch {
                await MainActor.run {
                    errorLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func autoDetectKiroAuth() {
        Task {
            do {
                try await service.autoDetectKiroAuth()
                await MainActor.run {
                    tokenField.stringValue = ""
                    errorLabel.stringValue = service.authMessage
                }
            } catch {
                await MainActor.run {
                    errorLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func toggleProxy() {
        if case .running = service.status {
            service.stop()
        } else {
            service.start()
        }
    }

    @objc private func copyBaseURL() {
        service.copyBaseURL()
    }

    @objc private func copyAPIKey() {
        service.copyAPIKey()
    }

    @objc private func toggleAPIKeyReveal() {
        apiKeyRevealed.toggle()
        refresh()
    }

    private func row(_ views: [NSView], firstFills: Bool) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        if firstFills, let first = views.first {
            first.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        return row
    }

    private func labelPair(title: String, value: NSView) -> NSStackView {
        let titleLabel = MenuLabels.section(title)
        let stack = NSStackView(views: [titleLabel, value])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        return stack
    }

    private func masked(_ value: String) -> String {
        guard value.count > 12 else { return "••••••••" }
        return "\(value.prefix(8))••••\(value.suffix(4))"
    }
}
