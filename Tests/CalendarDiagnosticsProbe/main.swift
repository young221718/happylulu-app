import Foundation
import EventKit
import SQLite3
import CalendarSyncCore
import CalendarSyncServices

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HappyLulu-diagnostics-fixture-\(UUID())")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let databaseURL = folder.appendingPathComponent("sync.sqlite")
let now = Date(timeIntervalSince1970: 1_800_000_000)
let sensitive = "PRIVATE_TITLE_ACCOUNT_ID_NOTES"
var state = CalendarSyncState()
state.configuration.daouBaseURL = "eventkit"
state.configuration.daouCalendarURL = sensitive + "-daou"
state.configuration.googleCalendarID = sensitive + "-google"
state.configuration.enabled = false
state.lastSuccessAt = now.addingTimeInterval(-100)
state.nextRunAt = now.addingTimeInterval(-10)
var summary = SyncRunSummary()
summary.held = 2
summary.issues = [SyncReviewIssue(id: sensitive, side: .daou, title: sensitive, reason: sensitive)]
state.lastPreview = summary
let event = CalendarEvent(id: sensitive, version: "v1", content: CalendarEventContent(
    title: sensitive, time: .timed(start: now, end: now.addingTimeInterval(3600), timeZoneID: "UTC"),
    notes: sensitive, location: sensitive), exclusion: .recurring)
state.daouObserved[event.id] = event
state.mappings["private-mapping"] = CalendarMapping(id: "private-mapping", daouEventID: event.id,
                                                   googleEventID: nil, baseline: nil)
var database: OpaquePointer?
require(sqlite3_open(databaseURL.path, &database) == SQLITE_OK, "fixture DB opens")
require(sqlite3_exec(database, "CREATE TABLE state (id INTEGER PRIMARY KEY, document BLOB)", nil, nil, nil) == SQLITE_OK,
        "fixture table creates")
var statement: OpaquePointer?
require(sqlite3_prepare_v2(database, "INSERT INTO state VALUES(1, ?)", -1, &statement, nil) == SQLITE_OK,
        "fixture insert prepares")
let document = try JSONEncoder().encode(state)
document.withUnsafeBytes { bytes in
    _ = sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(document.count), nil)
    require(sqlite3_step(statement) == SQLITE_DONE, "fixture document persists")
}
sqlite3_finalize(statement)
sqlite3_close(database)
let before = try Data(contentsOf: databaseURL)
let filesBefore = try FileManager.default.contentsOfDirectory(atPath: folder.path)
var readerCalls = 0
let report = CalendarSyncDiagnostics.inspect(databaseURL: databaseURL, authorization: .denied, now: now) { _, _ in
    readerCalls += 1
    return [:]
}
let encoded = try JSONEncoder().encode(report)
require(readerCalls == 0 && report.calendarReadBlocked, "denied permission never reads EventKit events")
require(report.storageStatus == "ok", "stored state loads with read-only SQLite")
require(report.stored?.enabled == false && report.stored?.nextRunDue == true,
        "diagnostics preserves paused and overdue facts")
require(report.stored?.lastPreview?.held == 2, "stored summary retains held count")
require(report.stored?.cachedPlannerCounts["held"] == 1,
        "real planner identifies excluded cached mapping as held")
require(report.stored?.cachedPlannerHoldReasons["excluded:recurring"] == 1,
        "real planner reports a safe category for its hold reason")
require(report.stored?.cachedExclusions["daou"]?["recurring"] == 1,
        "exclusion aggregate retains category")
require(!String(decoding: encoded, as: UTF8.self).contains(sensitive), "JSON omits all private fixture strings")
require(try Data(contentsOf: databaseURL) == before, "closed rollback fixture database bytes stay unchanged")
require(try FileManager.default.contentsOfDirectory(atPath: folder.path) == filesBefore,
        "closed rollback fixture has no new auxiliary files")

func testCommittedWALState(_ fixtureState: CalendarSyncState, folder: URL, now: Date) throws {
    let url = folder.appendingPathComponent("wal-sync.sqlite")
    var writer: OpaquePointer?
    require(sqlite3_open(url.path, &writer) == SQLITE_OK, "WAL writer opens")
    defer { sqlite3_close(writer) }
    require(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE state (id INTEGER PRIMARY KEY, document BLOB)",
                         nil, nil, nil) == SQLITE_OK, "WAL fixture initializes")

    func saveDocument(_ data: Data) {
        var statement: OpaquePointer?
        require(sqlite3_prepare_v2(writer, "INSERT INTO state VALUES(1, ?) ON CONFLICT(id) DO UPDATE SET document=excluded.document",
                                  -1, &statement, nil) == SQLITE_OK, "WAL fixture upsert prepares")
        defer { sqlite3_finalize(statement) }
        data.withUnsafeBytes { bytes in
            require(sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), nil) == SQLITE_OK,
                    "WAL fixture binds document")
            require(sqlite3_step(statement) == SQLITE_DONE, "WAL fixture commits document")
        }
    }

    func storedDocument() -> Data {
        var statement: OpaquePointer?
        require(sqlite3_prepare_v2(writer, "SELECT document FROM state WHERE id=1", -1, &statement, nil) == SQLITE_OK,
                "WAL logical document query prepares")
        defer { sqlite3_finalize(statement) }
        require(sqlite3_step(statement) == SQLITE_ROW, "WAL logical document exists")
        guard let bytes = sqlite3_column_blob(statement, 0) else { fatalError("WAL logical document has bytes") }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    saveDocument(try JSONEncoder().encode(fixtureState))
    require(sqlite3_exec(writer, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil) == SQLITE_OK,
            "initial WAL document checkpoints")
    let checkpointedDatabase = try Data(contentsOf: url)
    var latestState = fixtureState
    latestState.configuration.enabled = true
    latestState.nextRunAt = now.addingTimeInterval(100)
    var latestSummary = SyncRunSummary()
    latestSummary.held = 7
    latestState.lastPreview = latestSummary
    let latestDocument = try JSONEncoder().encode(latestState)
    require(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK, "WAL update begins")
    saveDocument(latestDocument)
    require(sqlite3_exec(writer, "COMMIT", nil, nil, nil) == SQLITE_OK, "WAL update commits")
    require(try Data(contentsOf: url) == checkpointedDatabase,
            "latest committed state remains in WAL instead of main database")
    require(try Data(contentsOf: URL(fileURLWithPath: url.path + "-wal")).count > 32,
            "fixture contains committed WAL frames")
    let logicalBefore = storedDocument()
    require(logicalBefore == latestDocument, "writer sees latest committed logical document")
    let report = CalendarSyncDiagnostics.inspect(databaseURL: url, authorization: .denied, now: now)
    require(report.storageStatus == "ok" && report.stored?.enabled == true &&
            report.stored?.nextRunDue == false && report.stored?.lastPreview?.held == 7,
            "production readonly inspector reads latest committed WAL state while writer stays open")
    require(storedDocument() == logicalBefore, "WAL inspection leaves logical state.document unchanged")
    // SQLite auxiliary-file maintenance is permitted; no claim is made that
    // WAL or SHM bytes, sizes, or timestamps stay unchanged during a read.
    print("PASS calendar diagnostics: committed WAL visible with writer open; logical document unchanged")
}
try testCommittedWALState(state, folder: folder, now: now)
let missing = CalendarSyncDiagnostics.inspect(databaseURL: folder.appendingPathComponent("missing.sqlite"),
                                               authorization: .notDetermined, now: now)
require(missing.storageStatus == "missing" && missing.calendarReadBlocked, "missing DB does not get created")
if #available(macOS 14.0, *) {
    let writeOnly = CalendarSyncDiagnostics.inspect(databaseURL: databaseURL, authorization: .writeOnly, now: now) { _, _ in
        readerCalls += 1
        return [:]
    }
    require(writeOnly.calendarReadBlocked && readerCalls == 0, "write-only permission never reads event details")
    _ = CalendarSyncDiagnostics.inspect(databaseURL: databaseURL, authorization: .fullAccess, now: now) { _, _ in
        readerCalls += 1
        return [:]
    }
    require(readerCalls == 1, "full access permits selected-calendar reader")
}
// An unsaved in-memory EventKit object exercises overlapping flags without
// querying a calendar, requesting permission, or saving an event.
let unsavedEvent = EKEvent(eventStore: EKEventStore())
unsavedEvent.title = sensitive + "/private"
unsavedEvent.url = URL(string: "https://example.invalid/private")
unsavedEvent.isAllDay = true
unsavedEvent.startDate = now
unsavedEvent.endDate = now.addingTimeInterval(86_400)
unsavedEvent.addAlarm(EKAlarm(relativeOffset: -300))
unsavedEvent.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
let flags = CalendarSyncDiagnostics.eventFlags(unsavedEvent)
for flag in ["slashTitle", "nonSyncURL", "alarms", "recurringOrDetached", "validAllDay"] {
    require(flags.contains(flag), "overlapping in-memory exclusion flags retain \(flag)")
}
unsavedEvent.url = URL(string: "happylulu://sync/00000000-0000-0000-0000-000000000001")
let managedFlags = CalendarSyncDiagnostics.eventFlags(unsavedEvent)
require(!managedFlags.contains("nonSyncURL") && !managedFlags.contains("missingServerIDAndMarker"),
        "valid managed marker prevents URL and missing-server-ID exclusions")
print("PASS calendar diagnostics: read-only SQLite, sanitized planner aggregates, permission-gated event reads")
