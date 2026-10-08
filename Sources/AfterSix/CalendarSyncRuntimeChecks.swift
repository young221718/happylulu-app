import Foundation
import AppKit
import EventKit
import CryptoKit
import CalendarSyncCore
import CalendarSyncServices

/// Explicit CLI validation, dispatched before the application's models/timers.
/// Reports contain aggregates only. Selected-calendar preview does not write events.
@MainActor enum CalendarSyncRuntimeChecks {
    enum Mode { case previewSelected, resumeSelected(reviewedReceipt: String), isolatedRoundtrip }
    typealias ProviderFactory = @MainActor (String, String) -> (any CalendarProvider, any CalendarProvider)

    struct Report: Encodable {
        var status: String
        var counts: [String: Int]?
        var receipt: String?
        var checks: [String: Bool]?
        var cleanupComplete = true
        var fixtureLeftBehind = false
        var cleanupManifestPath: String?
        var cleanupToken: String?
        // EventKit success does not prove arrival at the account's web server.
        var proof = "localEventKitOnly"
    }

    static func run(mode: Mode) async throws {
        let bundleID = Bundle.main.bundleIdentifier ?? "local.chanyoung.AfterSix"
        let runningPIDs = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .map(\.processIdentifier)
        let report: Report
        if hasAnotherProcess(currentPID: ProcessInfo.processInfo.processIdentifier, runningPIDs: runningPIDs) {
            report = Report(status: "appAlreadyRunning")
        } else {
            report = await execute(mode: mode, databaseURL: SyncStore.standardURL,
                                   authorization: EKEventStore.authorizationStatus(for: .event))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report) + Data("\n".utf8))
    }

    static func execute(mode: Mode, databaseURL: URL, authorization: EKAuthorizationStatus,
                        providerFactory: ProviderFactory? = nil) async -> Report {
        // No permission request, store creation, or EventKit query before this guard.
        guard hasFullAccess(authorization) else { return Report(status: "permissionRequired") }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return Report(status: "notConfigured")
        }
        do {
            let store = try SyncStore(url: databaseURL)
            let state = try await store.load()
            guard state.configuration.daouBaseURL == "eventkit",
                  state.configuration.systemAccountsConfirmed == true,
                  let daouID = state.configuration.daouCalendarURL,
                  let googleID = state.configuration.googleCalendarID,
                  daouID != googleID,
                  state.pairKey == "eventkit|\(daouID)|\(googleID)" else {
                return Report(status: "notConfigured")
            }
            if case .isolatedRoundtrip = mode {
                return await isolatedRoundtrip(daouID: daouID, googleID: googleID)
            }
            let providers = (providerFactory ?? { daou, google in
                (SystemCalendarProvider(side: .daou, calendarID: daou),
                 SystemCalendarProvider(side: .google, calendarID: google))
            })(daouID, googleID)
            let coordinator = SyncCoordinator(store: store, daou: providers.0, google: providers.1)
            let preview = try await coordinator.run(allowWrites: false)
            var freshState = try await store.load()
            let receipt = try reviewReceipt(freshState)
            if case .resumeSelected(let reviewedReceipt) = mode {
                guard reviewedReceipt == receipt else {
                    return Report(status: "previewChanged", counts: counts(preview), receipt: receipt)
                }
                try freshState.beginSystemSync(reviewedPairKey: freshState.pairKey)
                try await store.save(freshState)
                let summary = try await coordinator.run(allowWrites: true)
                return Report(status: "syncCompleted", counts: counts(summary))
            }
            return Report(status: "previewReady", counts: counts(preview), receipt: receipt)
        } catch SyncCoordinatorError.previewChanged {
            return Report(status: "previewChanged")
        } catch SystemCalendarError.accessDenied {
            return Report(status: "permissionRequired")
        } catch SystemCalendarError.calendarMissing {
            return Report(status: "selectedCalendarMissing")
        } catch SystemCalendarError.calendarReadOnly {
            return Report(status: "selectedCalendarReadOnly")
        } catch {
            // Errors may include account URLs, private IDs, or event contents.
            return Report(status: "runtimeFailed")
        }
    }

    private static func hasFullAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) { return status == .fullAccess }
        else { return status == .authorized }
    }

    private static func counts(_ summary: SyncRunSummary) -> [String: Int] {
        ["toDaou": summary.toDaou, "toGoogle": summary.toGoogle,
         "completed": summary.completed, "held": summary.held,
         "excluded": summary.excluded, "conflicts": summary.conflicts]
    }

    private struct ReviewedSnapshot: Encodable {
        let daouID: String?
        let googleID: String?
        let pairKey: String?
        let daouObserved: [String: CalendarEvent]
        let googleObserved: [String: CalendarEvent]
        let mappings: [String: CalendarMapping]
        let conflicts: [String: SyncConflict]
        let pending: [String: PendingSyncOperation]
    }

    private static func reviewReceipt(_ state: CalendarSyncState) throws -> String {
        let snapshot = ReviewedSnapshot(daouID: state.configuration.daouCalendarURL,
            googleID: state.configuration.googleCalendarID, pairKey: state.pairKey,
            daouObserved: state.daouObserved, googleObserved: state.googleObserved,
            mappings: state.mappings, conflicts: state.conflicts, pending: state.pendingOperations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(snapshot)).map { String(format: "%02x", $0) }.joined()
    }

    static func hasAnotherProcess(currentPID: Int32, runningPIDs: [Int32]) -> Bool {
        runningPIDs.contains { $0 != currentPID }
    }
    struct CleanupManifest: Codable {
        let token: String
        let calendars: [OwnedCalendar]
        let uncertainCreation: Bool
    }
    static func finalizeCleanup(folder: URL, manifest: CleanupManifest, cleanupComplete: Bool) throws -> URL? {
        if cleanupComplete {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
            return nil
        }
        return try persistCleanupManifest(folder: folder, manifest: manifest)
    }

    @discardableResult private static func persistCleanupManifest(folder: URL, manifest: CleanupManifest) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let url = folder.appendingPathComponent("cleanup.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    struct OwnedCalendar: Codable {
        let id: String
        let name: String
        let sourceID: String
    }
    private enum FixtureError: Error { case invalidFixture }

    private static func isolatedRoundtrip(daouID: String, googleID: String) async -> Report {
        let events = EKEventStore()
        guard let daou = events.calendar(withIdentifier: daouID),
              let google = events.calendar(withIdentifier: googleID),
              daou.allowsContentModifications, google.allowsContentModifications,
              daou.source.sourceType == .calDAV, google.source.sourceType == .calDAV else {
            return Report(status: "fixtureSourcesUnavailable")
        }
        let token = UUID().uuidString
        let prefix = "HappyLulu verification " + token
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HappyLulu-check-" + token)
        var owned: [OwnedCalendar] = []
        var uncertainCreation = false
        var report = Report(status: "fixtureCreationFailed", checks: [:])
        do {
            // Establish a private journal before the first remote mutation.
            try persistCleanupManifest(folder: folder,
                manifest: CleanupManifest(token: token, calendars: owned, uncertainCreation: false))
            for (side, source) in [("daou", daou.source!), ("google", google.source!)] {
                let calendar = EKCalendar(for: .event, eventStore: events)
                calendar.title = prefix + " " + side
                calendar.source = source
                do { try events.saveCalendar(calendar, commit: true) }
                catch {
                    // A failed save may still have assigned a local identity.
                    // Clean only that exact identity; otherwise report uncertainty.
                    if !calendar.calendarIdentifier.isEmpty {
                        owned.append(OwnedCalendar(id: calendar.calendarIdentifier, name: calendar.title,
                                                   sourceID: source.sourceIdentifier))
                    } else { uncertainCreation = true }
                    try persistCleanupManifest(folder: folder,
                        manifest: CleanupManifest(token: token, calendars: owned, uncertainCreation: uncertainCreation))
                    throw error
                }
                // Record each success immediately so a later failure still cleans it.
                owned.append(OwnedCalendar(id: calendar.calendarIdentifier, name: calendar.title,
                                           sourceID: source.sourceIdentifier))
                try persistCleanupManifest(folder: folder,
                    manifest: CleanupManifest(token: token, calendars: owned, uncertainCreation: uncertainCreation))
            }
            guard owned.count == 2 else { throw FixtureError.invalidFixture }
            let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60)
                .addingTimeInterval(7 * 86_400)
            report.status = "fixtureEventCreationFailed"
            for (index, item) in owned.enumerated() {
                guard let calendar = events.calendar(withIdentifier: item.id) else { throw FixtureError.invalidFixture }
                let oneoff = EKEvent(eventStore: events)
                oneoff.calendar = calendar
                oneoff.title = prefix + " oneoff " + String(index)
                oneoff.startDate = start.addingTimeInterval(Double(index) * 7200)
                oneoff.endDate = oneoff.startDate.addingTimeInterval(1800)
                oneoff.timeZone = TimeZone(secondsFromGMT: 0)
                oneoff.alarms = [EKAlarm(relativeOffset: -600)]
                try events.save(oneoff, span: .thisEvent, commit: true)
                let series = EKEvent(eventStore: events)
                series.calendar = calendar
                series.title = prefix + " series " + String(index)
                series.startDate = oneoff.startDate.addingTimeInterval(3600)
                series.endDate = series.startDate.addingTimeInterval(1800)
                series.timeZone = TimeZone(secondsFromGMT: 0)
                series.alarms = [EKAlarm(relativeOffset: -600)]
                series.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .daily, interval: 1,
                                                          end: EKRecurrenceEnd(occurrenceCount: 3))]
                try events.save(series, span: .thisEvent, commit: true)
                let occurrenceStart = series.startDate.addingTimeInterval(86_400)
                let predicate = events.predicateForEvents(withStart: occurrenceStart.addingTimeInterval(-60),
                    end: occurrenceStart.addingTimeInterval(3600), calendars: [calendar])
                guard let middle = events.events(matching: predicate).first(where: { $0.title == series.title }) else {
                    throw FixtureError.invalidFixture
                }
                middle.startDate = occurrenceStart.addingTimeInterval(1800)
                middle.endDate = middle.startDate.addingTimeInterval(1800)
                try events.save(middle, span: .thisEvent, commit: true)
            }
            report.status = "fixtureServerIdentityPending"
            // CalDAV assigns external UIDs asynchronously; do not test provisional
            // source identities or mistake a local save for server propagation.
            var ready = false
            for _ in 0..<30 {
                events.reset()
                let fixtureEvents = try owned.flatMap { try scopedEvents(events, item: $0, start: start) }
                if fixtureEvents.count == 8 && fixtureEvents.allSatisfy({ $0.calendarItemExternalIdentifier != nil }) {
                    ready = true
                    break
                }
                try await Task.sleep(for: .seconds(1))
            }
            guard ready else { throw FixtureError.invalidFixture }
            let store = try SyncStore(url: folder.appendingPathComponent("sync.sqlite"))
            var state = CalendarSyncState()
            state.configuration.daouBaseURL = "eventkit"
            state.configuration.daouCalendarURL = owned[0].id
            state.configuration.googleCalendarID = owned[1].id
            state.configuration.systemAccountsConfirmed = true
            state.pairKey = "eventkit|\(owned[0].id)|\(owned[1].id)"
            try await store.save(state)
            let coordinator = SyncCoordinator(store: store,
                daou: SystemCalendarProvider(side: .daou, calendarID: owned[0].id),
                google: SystemCalendarProvider(side: .google, calendarID: owned[1].id))
            report.status = "fixturePreviewFailed"
            let preview = try await coordinator.run(allowWrites: false)
            guard preview.toDaou == 4, preview.toGoogle == 4,
                  preview.excluded == 0, preview.held == 0, preview.conflicts == 0 else {
                report.counts = counts(preview)
                throw FixtureError.invalidFixture
            }
            report.checks?["previewBothDirections"] = true
            events.reset()
            guard try owned.allSatisfy({ try scopedEvents(events, item: $0, start: start).count == 4 }) else {
                throw FixtureError.invalidFixture
            }
            report.checks?["previewDidNotWrite"] = true
            state = try await store.load()
            try state.beginSystemSync(reviewedPairKey: state.pairKey)
            try await store.save(state)
            report.status = "fixtureInitialSyncFailed"
            let synced = try await coordinator.run(allowWrites: true)
            report.counts = counts(synced)
            guard synced.completed == 8, synced.held == 0, synced.conflicts == 0 else {
                throw FixtureError.invalidFixture
            }
            report.checks?["oneoffRecurrenceAndMovedExceptionCopied"] = true
            report.status = "fixtureDuplicateCheckFailed"
            let repeated = try await coordinator.run(allowWrites: true)
            events.reset()
            guard repeated.completed == 0, repeated.toDaou == 0, repeated.toGoogle == 0,
                  try owned.allSatisfy({ try scopedEvents(events, item: $0, start: start).count == 8 }) else {
                throw FixtureError.invalidFixture
            }
            report.checks?["repeatDidNotDuplicate"] = true
            report.status = "fixtureEditFailed"
            for (index, item) in owned.enumerated() {
                guard let original = try scopedEvents(events, item: item, start: start).first(where: {
                    $0.title == prefix + " oneoff " + String(index) && $0.url == nil
                }) else { throw FixtureError.invalidFixture }
                original.title += " edited"
                original.startDate = original.startDate.addingTimeInterval(900)
                original.endDate = original.endDate.addingTimeInterval(900)
                original.alarms = [EKAlarm(relativeOffset: -900)]
                try events.save(original, span: .thisEvent, commit: true)
            }
            let updated = try await coordinator.run(allowWrites: true)
            guard updated.completed == 2, updated.toDaou == 1, updated.toGoogle == 1,
                  updated.held == 0, updated.conflicts == 0 else { throw FixtureError.invalidFixture }
            events.reset()
            for item in owned {
                let list = try scopedEvents(events, item: item, start: start)
                let edited = list.filter { $0.title?.hasSuffix(" edited") == true }
                guard list.count == 8, edited.count == 2,
                      edited.allSatisfy({ $0.alarms?.contains(where: { $0.relativeOffset == -900 }) == true }),
                      list.allSatisfy({ $0.hasAlarms }) else { throw FixtureError.invalidFixture }
            }
            report.checks?["editsAndAlarmsBothDirections"] = true
            let final = try await coordinator.run(allowWrites: true)
            guard final.completed == 0, final.held == 0, final.conflicts == 0 else { throw FixtureError.invalidFixture }
            report.checks?["editedCopiesSettled"] = true
            report.status = "roundtripPassed"
        } catch {
            // Preserve the last fixed stage code, never interpolate the error.
        }
        events.reset()
        report.cleanupComplete = !uncertainCreation
        for item in owned {
            guard let calendar = events.calendar(withIdentifier: item.id) else { continue }
            guard calendar.title == item.name, item.name.hasPrefix(prefix + " "),
                  calendar.source.sourceIdentifier == item.sourceID else {
                report.cleanupComplete = false
                continue
            }
            do { try events.removeCalendar(calendar, commit: true) }
            catch { report.cleanupComplete = false }
        }
        events.reset()
        if owned.contains(where: { events.calendar(withIdentifier: $0.id) != nil }) {
            report.cleanupComplete = false
        }
        report.fixtureLeftBehind = !report.cleanupComplete
        let manifest = CleanupManifest(token: token, calendars: owned, uncertainCreation: uncertainCreation)
        do {
            let retained = try finalizeCleanup(folder: folder, manifest: manifest, cleanupComplete: report.cleanupComplete)
            report.cleanupManifestPath = retained?.path
            report.cleanupToken = retained == nil ? nil : token
        } catch {
            // Never destroy recovery information after a failed cleanup or journal
            // write. The token locates the protected directory without exposing IDs.
            report.cleanupComplete = false
            report.cleanupToken = token
            let manifestURL = folder.appendingPathComponent("cleanup.json")
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                report.cleanupManifestPath = manifestURL.path
            }
        }
        return report
    }

    private static func scopedEvents(_ store: EKEventStore, item: OwnedCalendar, start: Date) throws -> [EKEvent] {
        guard let calendar = store.calendar(withIdentifier: item.id), calendar.title == item.name,
              calendar.source.sourceIdentifier == item.sourceID else { throw FixtureError.invalidFixture }
        let predicate = store.predicateForEvents(withStart: start.addingTimeInterval(-86_400),
            end: start.addingTimeInterval(5 * 86_400), calendars: [calendar])
        return store.events(matching: predicate)
    }
}
