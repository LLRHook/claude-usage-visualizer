import Foundation
import Sparkle
import Combine

@MainActor
final class AppUpdater: ObservableObject {
    @Published var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    init() {
        // Only start Sparkle if SUFeedURL and SUPublicEDKey are configured
        let feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String ?? ""
        let edKey = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String ?? ""

        guard !feedURL.isEmpty, !edKey.isEmpty else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller

        // KVO bridge for canCheckForUpdates
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: \.canCheckForUpdates, on: self)

        controller.startUpdater()
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
