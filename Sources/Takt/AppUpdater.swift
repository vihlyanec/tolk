import AppKit
import Combine
import Observation
import Sparkle
import TaktCore

@Observable final class AppUpdater {
    private(set) var canCheck = false
    private(set) var configured = false
    private(set) var status = "Канал обновлений ещё не настроен."
    var automaticChecks = false {
        didSet {
            if controller?.updater.automaticallyChecksForUpdates != automaticChecks {
                controller?.updater.automaticallyChecksForUpdates = automaticChecks
            }
        }
    }
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations = Set<AnyCancellable>()
    init(bundle: Bundle = .main) {
        guard UpdateConfiguration(feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                                  publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            configured = true; status = "Обновления загружаются из GitHub Releases."
            controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] value in
                MainActor.assumeIsolated { self?.canCheck = value }
            }.store(in: &observations)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] value in
                MainActor.assumeIsolated { self?.automaticChecks = value }
            }.store(in: &observations)
        } catch { status = "Не удалось включить обновления: \(error.localizedDescription)" }
    }
    func check() { guard canCheck else { return }; controller?.checkForUpdates(nil) }
}
