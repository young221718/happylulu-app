import AppKit
import Foundation
import CalendarSyncServices

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

actor FakeCalendarAccess: CalendarSyncAccess {
    private var allowed = false
    private var suspendNextRead = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0
    private(set) var permissionRequests = 0

    func setAllowed(_ value: Bool) { allowed = value }
    func suspendRead() { suspendNextRead = true }
    func releaseRead() { continuation?.resume(); continuation = nil }
    func isSuspended() -> Bool { continuation != nil }
    func requestAccess() async throws { permissionRequests += 1 }

    func writableCalendars() async throws -> [SystemCalendarSummary] {
        readCount += 1
        let allowedAtStart = allowed
        if suspendNextRead {
            suspendNextRead = false
            await withCheckedContinuation { continuation = $0 }
        }
        guard allowedAtStart else { throw SystemCalendarError.accessDenied }
        return [SystemCalendarSummary(id: "fixture", title: "Fixture", accountName: "Fixture",
                                      accountID: "fixture-account", colorHex: "#000000")]
    }
}

@MainActor
func waitUntil(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<100 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

let access = FakeCalendarAccess()
// The injected model opens no SyncStore, starts no timers/network monitor,
// requests no OS permission, and touches no actual EventKit calendar.
let model = CalendarSyncModel(calendarAccess: access)
await model.requestCalendarAccess(requestPermission: false)
require(!model.calendarAccessReady, "initial permission denial disables calendar actions")
await access.setAllowed(true)
NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
let refreshed = await waitUntil { model.calendarAccessReady && !model.isRunning }
require(refreshed, "returning to app after permission grant refreshes calendar readiness without reopening settings")
require(model.calendars.count == 1, "activation refreshes displayed writable calendars")
require(await access.permissionRequests == 0, "activation does not request OS permission")

await access.setAllowed(false)
await access.suspendRead()
let busyRefresh = Task { await model.requestCalendarAccess(requestPermission: false) }
require(await waitUntil { await access.isSuspended() }, "fixture pauses an in-flight calendar read")
await access.setAllowed(true)
NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
try? await Task.sleep(for: .milliseconds(30))
require(await access.readCount == 3, "activation cannot overlap a running operation")
await access.releaseRead()
await busyRefresh.value
let deferredRefresh = await waitUntil {
    let count = await access.readCount
    return count == 4 && model.calendarAccessReady && !model.isRunning
}
require(deferredRefresh, "activation during a busy operation is refreshed after it finishes")
require(await access.permissionRequests == 0, "deferred activation also requests no OS permission")
print("PASS calendar model: permission-grant activation refresh and deferred busy refresh without OS requests or storage")
