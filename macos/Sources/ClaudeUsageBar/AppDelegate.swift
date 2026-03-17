import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables: Set<AnyCancellable> = []

    let usageService = UsageService()
    let historyService = UsageHistoryService()
    let farmService = RepoFarmService()
    let appUpdater = AppUpdater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient

        let contentView = PopoverView(
            usageService: usageService,
            historyService: historyService,
            farmService: farmService
        )
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Wire services
        usageService.historyService = historyService
        usageService.loadCredentials()

        // Observe state changes to update icon
        usageService.$isAuthenticated
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        usageService.$currentUsage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        if usageService.isAuthenticated, let usage = usageService.currentUsage {
            button.image = MenuBarIconRenderer.renderIcon(
                pct5h: usage.fiveHour?.fraction ?? 0,
                pct7d: usage.sevenDay?.fraction ?? 0
            )
        } else {
            button.image = MenuBarIconRenderer.renderUnauthenticatedIcon()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
