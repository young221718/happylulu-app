import Foundation
import EventKit
import SQLite3
import CalendarSyncCore
import CalendarSyncServices

/// Runs before application models start, without writing sync state or events.
/// SQLite may maintain WAL auxiliary files even with a read-only connection.
enum CalendarSyncDiagnostics {
    struct SummaryCounts: Encodable {
        let toDaou: Int
        let toGoogle: Int
        let conflicts: Int
        let held: Int
        let excluded: Int
        let completed: Int
        let mode: SyncRunMode?

        init(_ summary: SyncRunSummary) {
            toDaou = summary.toDaou
            toGoogle = summary.toGoogle
            conflicts = summary.conflicts
            held = summary.held
            excluded = summary.excluded
            completed = summary.completed
            mode = summary.mode
        }
    }

    struct StoredReport: Encodable {
        let enabled: Bool
        let hasSelectedPair: Bool
        let hasSuccessfulSync: Bool
        let hasNextRun: Bool
        let nextRunDue: Bool
        let pendingCount: Int
        let conflictCount: Int
        let lastPreview: SummaryCounts?
        let cachedExclusions: [String: [String: Int]]
        let cachedPlannerCounts: [String: Int]
        let cachedPlannerHoldReasons: [String: Int]
    }

    struct LiveCalendarReport: Encodable {
        let status: String
        let eventCount: Int
        // Flags overlap; one event may contribute to several reason counts.
        let flags: [String: Int]
    }

    struct Report: Encodable {
        let permission: String
        let calendarReadBlocked: Bool
        let storageStatus: String
        let stored: StoredReport?
        let live: [String: LiveCalendarReport]?
    }

    static func run() throws {
        let report = inspect(databaseURL: SyncStore.standardURL,
                             authorization: EKEventStore.authorizationStatus(for: .event))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    static func inspect(databaseURL: URL, authorization: EKAuthorizationStatus, now: Date = Date(),
                        liveReader: ((CalendarSyncState, Date) -> [String: LiveCalendarReport])? = nil) -> Report {
        let permission = permissionName(authorization)
        let canRead = permission == "fullAccess" || permission == "authorized"
        do {
            guard let state = try readState(databaseURL) else {
                return Report(permission: permission, calendarReadBlocked: !canRead,
                              storageStatus: "missing", stored: nil, live: nil)
            }
            return Report(permission: permission, calendarReadBlocked: !canRead, storageStatus: "ok",
                          stored: summarize(state, now: now),
                          live: canRead ? (liveReader ?? readSelectedCalendars)(state, now) : nil)
        } catch {
            // Never echo SQLite paths or decoded fields in diagnostic errors.
            return Report(permission: permission, calendarReadBlocked: !canRead,
                          storageStatus: "unreadable", stored: nil, live: nil)
        }
    }

    private static func permissionName(_ status: EKAuthorizationStatus) -> String {
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return "fullAccess" }
            if status == .writeOnly { return "writeOnly" }
        } else if status == .authorized { return "authorized" }
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        default: return "unknown"
        }
    }

    private enum ReadError: Error { case invalidState }

    private static func readState(_ url: URL) throws -> CalendarSyncState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw ReadError.invalidState
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT document FROM state WHERE id = 1", -1, &statement, nil) == SQLITE_OK else {
            throw ReadError.invalidState
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return CalendarSyncState() }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw ReadError.invalidState
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        let state = try JSONDecoder().decode(CalendarSyncState.self, from: data)
        guard state.version == 1 else { throw ReadError.invalidState }
        return state
    }

    private static func exclusionName(_ exclusion: CalendarEventExclusion) -> String {
        switch exclusion {
        case .recurring: "recurring"
        case .invitation: "invitation"
        case .approvalManaged: "approvalManaged"
        case .unsupportedProperties: "unsupportedProperties"
        case .other: "other"
        }
    }

    private static func summarize(_ state: CalendarSyncState, now: Date) -> StoredReport {
        var exclusions: [String: [String: Int]] = [:]
        for (side, events) in [("daou", state.daouObserved), ("google", state.googleObserved)] {
            var counts = ["total": events.count, "excluded": 0]
            for event in events.values {
                if let exclusion = event.exclusion {
                    counts["excluded", default: 0] += 1
                    counts[exclusionName(exclusion), default: 0] += 1
                }
            }
            exclusions[side] = counts
        }
        func observation(_ id: String?, in events: [String: CalendarEvent]) -> CalendarObservation {
            guard let id else { return .absent }
            // A missing cached event does not prove a deletion. No provider
            // request is made to resolve that uncertainty in diagnostics.
            return events[id].map(CalendarObservation.present) ?? .unavailable(.outsideWindow)
        }
        var decisions = ["settled": 0, "operation": 0, "conflict": 0, "held": 0, "pendingJournal": 0]
        var holdReasons: [String: Int] = [:]
        for mapping in state.mappings.values {
            if state.pendingOperations[mapping.id] != nil {
                decisions["pendingJournal", default: 0] += 1
                continue
            }
            let decision = SyncPlanner.plan(mapping: mapping,
                daou: observation(mapping.daouEventID, in: state.daouObserved),
                google: observation(mapping.googleEventID, in: state.googleObserved))
            switch decision {
            case .settled: decisions["settled", default: 0] += 1
            case .operation: decisions["operation", default: 0] += 1
            case .conflict: decisions["conflict", default: 0] += 1
            case .held(let reason):
                decisions["held", default: 0] += 1
                let key: String
                switch reason {
                case .excludedEvent(let exclusion): key = "excluded:" + exclusionName(exclusion)
                case .incompleteObservation: key = "incompleteObservation"
                case .incompleteMapping: key = "incompleteMapping"
                case .unverifiedAbsence: key = "unverifiedAbsence"
                case .identityMismatch: key = "identityMismatch"
                case .missingVersion: key = "missingVersion"
                case .tombstoneResurrection: key = "tombstoneResurrection"
                }
                holdReasons[key, default: 0] += 1
            }
        }
        return StoredReport(enabled: state.configuration.enabled,
            hasSelectedPair: state.configuration.hasSelectedPair, hasSuccessfulSync: state.lastSuccessAt != nil,
            hasNextRun: state.nextRunAt != nil, nextRunDue: state.nextRunAt.map { $0 <= now } ?? false,
            pendingCount: state.pendingOperations.count, conflictCount: state.conflicts.count,
            lastPreview: state.lastPreview.map(SummaryCounts.init), cachedExclusions: exclusions, cachedPlannerCounts: decisions,
            cachedPlannerHoldReasons: holdReasons)
    }

    private static func readSelectedCalendars(_ state: CalendarSyncState, _ now: Date) -> [String: LiveCalendarReport] {
        guard state.configuration.daouBaseURL == "eventkit" else { return [:] }
        let store = EKEventStore()
        var result: [String: LiveCalendarReport] = [:]
        for (side, id) in [("daou", state.configuration.daouCalendarURL), ("google", state.configuration.googleCalendarID)] {
            guard let id, let calendar = store.calendar(withIdentifier: id) else {
                result[side] = LiveCalendarReport(status: "selectedCalendarMissing", eventCount: 0, flags: [:])
                continue
            }
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-30 * 86_400),
                end: now.addingTimeInterval(365 * 86_400), calendars: [calendar])
            let events = store.events(matching: predicate)
            var counts: [String: Int] = [:]
            for event in events {
                for flag in eventFlags(event) { counts[flag, default: 0] += 1 }
            }
            result[side] = LiveCalendarReport(status: calendar.allowsContentModifications ? "readableWritable" : "readableReadOnly",
                                             eventCount: events.count, flags: counts)
        }
        return result
    }

    static func eventFlags(_ event: EKEvent) -> [String] {
        let marker: Bool
        if let url = event.url, url.scheme == "happylulu", url.host == "sync",
           url.query == nil, url.fragment == nil,
           UUID(uuidString: String(url.path.dropFirst())) != nil { marker = true }
        else { marker = false }
        var flags: [String] = []
        if event.hasRecurrenceRules || event.isDetached { flags.append("recurringOrDetached") }
        if event.hasAttendees { flags.append("invitation") }
        if event.hasAlarms { flags.append("alarms") }
        if event.url != nil && !marker { flags.append("nonSyncURL") }
        if event.calendarItemExternalIdentifier == nil && !marker { flags.append("missingServerIDAndMarker") }
        if (event.title ?? "").contains("/") { flags.append("slashTitle") }
        if event.isAllDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            if let start = event.startDate, let end = event.endDate, start < end {
                let first = calendar.startOfDay(for: start)
                let last = calendar.startOfDay(for: end)
                let exclusiveEnd = end == last ? last : calendar.date(byAdding: .day, value: 1, to: last)
                flags.append(exclusiveEnd.map { first < $0 } == true ? "validAllDay" : "invalidAllDay")
            } else { flags.append("invalidAllDay") }
        }
        return flags
    }
}
