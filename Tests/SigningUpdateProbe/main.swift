import AppKit
import Foundation

func L(_ ko: String, _ en: String) -> String { en }

@MainActor final class SigningProbeDelegate: NSObject, NSApplicationDelegate {
    private var updater: AppUpdater?
    private var timer: Timer?
    private var lastState = ""

    private func record(_ stage: String, details: [String: Any] = [:]) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "SigningProbeLogPath") as? String else { return }
        var item: [String: Any] = ["stage": stage, "pid": ProcessInfo.processInfo.processIdentifier,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "missing"]
        item.merge(details) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data("\n".utf8))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        record("launched", details: ["resource": (try? String(contentsOf: Bundle.main.resourceURL!
            .appendingPathComponent("probe-version.txt"), encoding: .utf8)) ?? "missing"])
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            record("updatedRelaunch")
            Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
                Task { @MainActor in NSApplication.shared.terminate(nil) }
            }
            return
        }
        let updater = AppUpdater()
        updater.canInstallNow = { true }
        self.updater = updater
        updater.start()
        record("updaterStarted")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordUpdaterState() }
        }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.record("timeout")
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func recordUpdaterState() {
        guard let updater else { return }
        let state = "\(updater.automaticallyChecks)|\(updater.automaticallyInstalls)|\(updater.isPreparingInstallation)|\(updater.isInstallingUpdate)|\(updater.startupError != nil)"
        if state != lastState {
            lastState = state
            record("updaterState", details: ["checks": updater.automaticallyChecks,
                "downloads": updater.automaticallyInstalls, "prepared": updater.isPreparingInstallation,
                "installing": updater.isInstallingUpdate, "startupError": updater.startupError != nil])
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        record("shouldTerminate")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) { record("willTerminate") }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let delegate = SigningProbeDelegate()
application.delegate = delegate
application.run()
