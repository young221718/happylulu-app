import AppKit
import SwiftUI
import Combine
import ServiceManagement
import AfterSixCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = AppModel()
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = LuluBrand.menuBarIcon()
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 364, height: 570)
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        observation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        let firstLaunch = !model.state.didOfferLoginItem
        model.start()
        updateTitle()
        if firstLaunch { togglePanel() }
    }

    private func updateTitle() {
        statusItem.button?.title = " " + model.menuTitle
        statusItem.button?.toolTip = model.departure.map { "출근 \(model.timeLabel(model.arrival!.time)) · 퇴근 예정 \(model.timeLabel($0))" }
            ?? "HappyLulu · 오전 6시 이후 첫 잠금 해제를 기다립니다"
        statusItem.button?.setAccessibilityLabel("HappyLulu, \(model.menuTitle)")
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        model.refresh()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePanel() }
        return true
    }
}

if CommandLine.arguments.contains("--status") {
    // Read-only diagnostics; no notification injection or attendance mutation.
    do {
        let state = try StateStore.standard.load()
        let record = Attendance.today(in: state, now: Date(), calendar: .current)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        print("app=HappyLulu version=\(version)")
        print("loginItemStatus=\(SMAppService.mainApp.status.rawValue)")
        print("todayRecorded=\(record != nil)")
        print("lastUnlockObserved=\(state.lastUnlockAt != nil)")
        print("workMinutes=\(state.settings.workMinutes) breakMinutes=\(state.settings.breakMinutes)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("HappyLulu: state could not be read.\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
if let identifier = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    existing.activate(options: [.activateIgnoringOtherApps])
    exit(0)
}
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
