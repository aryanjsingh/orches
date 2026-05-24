import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let proxyService = ProxyService()
    private lazy var popoverController = PopoverViewController(proxyService: proxyService)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "Orches"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.contentViewController = popoverController
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        proxyService.stop()
    }
}
