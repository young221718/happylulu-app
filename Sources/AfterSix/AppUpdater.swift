import AppKit
import Combine
import Foundation
@preconcurrency import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var isPreparingInstallation = false
    var canInstallNow: () -> Bool = { false }
    private var pendingInstall: (() -> Void)?
    private var installAttemptInFlight = false
    var isInstallingUpdate: Bool { installAttemptInFlight }
    private var installTimer: Timer?
    @Published private(set) var startupError: String?
    private var controller: SPUStandardUpdaterController!

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("개발 버전", "Development build")
    }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: self, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyInstalls)
    }

    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "HappyLuluUpdateServiceEnabled") as? Bool == true else {
            return
        }
        do {
            try controller.updater.start()
            if controller.updater.automaticallyChecksForUpdates {
                controller.updater.checkForUpdatesInBackground()
            }
        }
        catch { startupError = "업데이트 설정을 확인하지 못했어요. 제작자에게 알려 주세요." }
    }

    @objc func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        guard !isPreparingInstallation else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyInstalls(_ enabled: Bool) {
        guard !isPreparingInstallation else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard updater.automaticallyChecksForUpdates, updater.automaticallyDownloadsUpdates else { return false }
        isPreparingInstallation = true
        pendingInstall = immediateInstallHandler
        installTimer?.invalidate()
        // Never interrupt attendance persistence, calendar synchronization or an
        // open editor. Sparkle also installs a prepared update on normal quit.
        installTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.installWhenIdle() }
        }
        return true
    }

    func installWhenIdle() {
        // Preferences cannot cancel this committed installation. In-app setters
        // are locked until restart, so the held Sparkle cycle cannot be stranded.
        guard !installAttemptInFlight, canInstallNow(), let install = pendingInstall else { return }
        installAttemptInFlight = true
        install()
    }

    // Called only after our application delegate actually cancels termination.
    func installationWasDeferred() { installAttemptInFlight = false }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { clearPreparedInstall() }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        clearPreparedInstall()
    }

    private func clearPreparedInstall() {
        installAttemptInFlight = false
        pendingInstall = nil
        installTimer?.invalidate()
        installTimer = nil
        isPreparingInstallation = false
    }
}
