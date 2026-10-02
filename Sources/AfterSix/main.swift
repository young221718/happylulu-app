import AppKit
import SwiftUI
import Combine
import EventKit
import ServiceManagement
import AfterSixCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = AppModel()
    private let calendarSync = CalendarSyncModel()
    private let updater = AppUpdater()
    private var calendarWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var observation: AnyCancellable?
    private var languageObservation: AnyCancellable?

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
        popover.contentSize = NSSize(width: 364, height: 470)
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, onOpenSettings: { [weak self] in
            self?.openSettings()
        }))
        observation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        languageObservation = AppLanguage.shared.$choice.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateTitle()
                self?.settingsWindow?.title = L("HappyLulu 설정", "HappyLulu Settings")
            }
        }
        let firstLaunch = !model.state.didOfferLoginItem
        model.start()
        calendarSync.start()
        updater.start()
        updateTitle()
        if firstLaunch { togglePanel() }
        if CommandLine.arguments.contains("--calendar") { openCalendarSync() }
    }

    private func updateTitle() {
        statusItem.button?.title = " " + model.menuTitle
        statusItem.button?.toolTip = model.departure.map { L("출근 \(model.timeLabel(model.arrival!.time)) · 퇴근 예정 \(model.timeLabel($0))", "Arrived \(model.timeLabel(model.arrival!.time)) · expected departure \(model.timeLabel($0))") }
            ?? L("HappyLulu · 일반 08:00~10:00, 오전 반차 13:00~15:00 잠금 해제를 기다립니다", "HappyLulu · waiting for unlock: regular 08:00–10:00, morning off 13:00–15:00")
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

    private func openCalendarSync() {
        if popover.isShown { popover.performClose(nil) }
        NSApplication.shared.setActivationPolicy(.regular)
        if calendarWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "HappyLulu Calendar"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: CalendarSyncSettingsView(model: calendarSync))
            window.center()
            calendarWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        calendarWindow?.makeKeyAndOrderFront(nil)
    }

    private func openSettings() {
        if popover.isShown { popover.performClose(nil) }
        NSApplication.shared.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = L("HappyLulu 설정", "HappyLulu Settings")
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(
                model: model, updater: updater, onOpenCalendarSync: { [weak self] in
                    self?.openCalendarSync()
                }))
            window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === calendarWindow || closingWindow === settingsWindow else { return }
        DispatchQueue.main.async { [weak self] in
            if self?.calendarWindow?.isVisible != true && self?.settingsWindow?.isVisible != true {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
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
        print("calendarAccessStatus=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let publicKey = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
        print("updaterConfigured=\(feed?.scheme == "https" && publicKey?.count == 32)")
        print("updaterAutomaticChecksDefault=\(info["SUEnableAutomaticChecks"] as? Bool ?? false)")
        print("updaterAutomaticInstallationDefault=\(info["SUAutomaticallyUpdate"] as? Bool ?? false)")
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
