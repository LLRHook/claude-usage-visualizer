import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables: Set<AnyCancellable> = []
    private var indicatorDot: NSView?

    let usageService = UsageService()
    let historyService = UsageHistoryService()
    let farmService = RepoFarmService()
    let appUpdater = AppUpdater()
    let paceCoachService = PaceCoachService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient

        let contentView = PopoverView(
            usageService: usageService,
            historyService: historyService,
            farmService: farmService,
            paceCoachService: paceCoachService
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

        // Wire pace coach: recalculate whenever usage or history changes
        Publishers.CombineLatest(usageService.$currentUsage, historyService.$dataPoints)
            .receive(on: RunLoop.main)
            .sink { [weak self] usage, dataPoints in
                guard let self else { return }
                let utilization = usage?.fiveHour?.utilization ?? 0
                let resetDate = usage?.fiveHour?.resetDate
                self.paceCoachService.recalculate(
                    dataPoints: dataPoints,
                    currentUtilization: utilization,
                    resetDate: resetDate
                )
            }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        if usageService.isAuthenticated, let usage = usageService.currentUsage {
            button.image = MenuBarIconRenderer.renderIcon(
                pct5h: usage.fiveHour?.fraction ?? 0,
                pct7d: usage.sevenDay?.fraction ?? 0
            )
            updateIndicatorDot(on: button, utilization: usage.fiveHour?.utilization ?? 0)
        } else {
            button.image = MenuBarIconRenderer.renderUnauthenticatedIcon()
            indicatorDot?.removeFromSuperview()
            indicatorDot = nil
        }
    }

    private func updateIndicatorDot(on button: NSStatusBarButton, utilization: Double) {
        if indicatorDot == nil {
            let dot = NSView(frame: NSRect(x: 16, y: 1, width: 5, height: 5))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 2.5
            button.addSubview(dot)
            indicatorDot = dot
        }
        indicatorDot?.layer?.backgroundColor = dotColor(for: utilization).cgColor
    }

    private func dotColor(for utilization: Double) -> NSColor {
        NSColor(HealthTier.utilizationColor(for: utilization))
    }

    // MARK: - Click Handling

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        if usageService.isAuthenticated {
            if let usage = usageService.currentUsage {
                let pct5h = String(format: "5h: %.0f%%", usage.fiveHour?.utilization ?? 0)
                let pct7d = String(format: "7d: %.0f%%", usage.sevenDay?.utilization ?? 0)
                let statusItem = NSMenuItem(title: "\(pct5h)  \(pct7d)", action: nil, keyEquivalent: "")
                statusItem.isEnabled = false
                menu.addItem(statusItem)
                menu.addItem(NSMenuItem.separator())
            }

            let refreshItem = NSMenuItem(title: "Refresh Usage", action: #selector(refreshUsage), keyEquivalent: "")
            refreshItem.target = self
            menu.addItem(refreshItem)

            let scanItem = NSMenuItem(title: "Scan Repos", action: #selector(scanRepos), keyEquivalent: "")
            scanItem.target = self
            menu.addItem(scanItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshUsage() {
        Task { await usageService.fetchUsage() }
    }

    @objc private func scanRepos() {
        Task { await farmService.scanRepos() }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
