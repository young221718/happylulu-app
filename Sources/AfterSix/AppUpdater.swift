import AppKit
import Combine
import Foundation
@preconcurrency import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var startupError: String?
    private var controller: SPUStandardUpdaterController!

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("개발 버전", "Development build")
    }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        // Every update requires the user's confirmation, including upgrades
        // from development builds that previously enabled silent downloads.
        controller.updater.automaticallyDownloadsUpdates = false
    }

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "HappyLuluUpdateServiceEnabled") as? Bool == true else {
            return
        }
        do { try controller.updater.start() }
        catch { startupError = "업데이트 설정을 확인하지 못했어요. 제작자에게 알려 주세요." }
    }

    @objc func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

}
