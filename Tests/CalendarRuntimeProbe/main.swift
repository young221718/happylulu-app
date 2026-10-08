import Foundation
import EventKit
import CalendarSyncCore
import CalendarSyncServices

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

actor ProbeProvider: CalendarProvider {
    nonisolated let side: CalendarSide
    var events: [String: CalendarEvent]
    var writes = 0
    init(_ side: CalendarSide, events: [CalendarEvent] = []) {
        self.side = side
        self.events = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
    }
    func replace(_ event: CalendarEvent) { events[event.id] = event }
    func fetchChanges(cursor: String?, pageToken: String?) async throws -> CalendarChangePage {
        CalendarChangePage(changes: events.values.map(CalendarChange.upsert), isFullSnapshot: true)
    }
    func observe(eventID: String) async throws -> CalendarObservation {
        events[eventID].map(CalendarObservation.present) ?? .unavailable(.unknown)
    }
    func apply(_ operation: SyncOperation) async throws -> CalendarWriteReceipt {
        guard case let .create(mappingID, target, _, content) = operation, target == side else {
            throw CalendarProviderError.wrongSide
        }
        let id = "copy:" + mappingID
        events[id] = CalendarEvent(id: id, version: "copy-v1", content: content, syncMarker: mappingID)
        writes += 1
        return CalendarWriteReceipt(eventID: id, version: "copy-v1")
    }
}

@main struct RuntimeProbe {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        require(!CalendarSyncRuntimeChecks.hasAnotherProcess(currentPID: 41, runningPIDs: [41]),
                "runtime entry must ignore its own process")
        require(CalendarSyncRuntimeChecks.hasAnotherProcess(currentPID: 41, runningPIDs: [41, 42]),
                "runtime entry must reject another same-bundle process")
        let recoveryFolder = folder.appendingPathComponent("recovery")
        let ownership = CalendarSyncRuntimeChecks.CleanupManifest(token: UUID().uuidString,
            calendars: [.init(id: "PRIVATE_OWNED_ID", name: "PRIVATE_OWNED_NAME", sourceID: "PRIVATE_SOURCE_ID")],
            uncertainCreation: false)
        let retained = try CalendarSyncRuntimeChecks.finalizeCleanup(folder: recoveryFolder,
            manifest: ownership, cleanupComplete: false)
        require(retained != nil && FileManager.default.fileExists(atPath: retained!.path),
                "failed cleanup must retain an exact ownership manifest")
        let restored = try JSONDecoder().decode(CalendarSyncRuntimeChecks.CleanupManifest.self,
                                                from: Data(contentsOf: retained!))
        require(restored.calendars.first?.id == "PRIVATE_OWNED_ID" && restored.calendars.first?.sourceID == "PRIVATE_SOURCE_ID",
                "recovery must preserve exact calendar and source identities")
        let fileMode = try FileManager.default.attributesOfItem(atPath: retained!.path)[.posixPermissions] as? NSNumber
        let directoryMode = try FileManager.default.attributesOfItem(atPath: recoveryFolder.path)[.posixPermissions] as? NSNumber
        require(fileMode?.intValue == 0o600 && directoryMode?.intValue == 0o700,
                "cleanup recovery information must be private to this user")
        let removed = try CalendarSyncRuntimeChecks.finalizeCleanup(folder: recoveryFolder,
            manifest: ownership, cleanupComplete: true)
        require(removed == nil && !FileManager.default.fileExists(atPath: recoveryFolder.path),
                "verified cleanup may remove its private recovery folder")
        let absentURL = folder.appendingPathComponent("absent/sync.sqlite")
        var providerConstructed = false
        let denied = await CalendarSyncRuntimeChecks.execute(mode: .previewSelected, databaseURL: absentURL,
            authorization: .denied, providerFactory: { _, _ in
                providerConstructed = true
                return (ProbeProvider(.daou), ProbeProvider(.google))
            })
        require(denied.status == "permissionRequired", "denied read permission must stop execution")
        require(!providerConstructed && !FileManager.default.fileExists(atPath: absentURL.path),
                "permission denial must not open state or create providers")
        if #available(macOS 14.0, *) {
            let addOnly = await CalendarSyncRuntimeChecks.execute(mode: .isolatedRoundtrip,
                databaseURL: absentURL, authorization: .writeOnly)
            require(addOnly.status == "permissionRequired" && !FileManager.default.fileExists(atPath: absentURL.path),
                    "write-only permission must not create a runtime fixture")
        }
        let granted: EKAuthorizationStatus
        if #available(macOS 14.0, *) { granted = .fullAccess } else { granted = .authorized }
        let url = folder.appendingPathComponent("fixture/sync.sqlite")
        let store = try SyncStore(url: url)
        var state = CalendarSyncState()
        state.configuration.daouBaseURL = "eventkit"
        state.configuration.daouCalendarURL = "PRIVATE_DAOU"
        state.configuration.googleCalendarID = "PRIVATE_GOOGLE"
        state.configuration.systemAccountsConfirmed = true
        state.pairKey = "eventkit|PRIVATE_DAOU|PRIVATE_GOOGLE"
        try await store.save(state)
        let start = Date().addingTimeInterval(3600)
        let source = CalendarEvent(id: "PRIVATE_EVENT", version: "v1", content: .init(title: "PRIVATE_TITLE",
            time: .timed(start: start, end: start.addingTimeInterval(1800), timeZoneID: "UTC")))
        let daou = ProbeProvider(.daou, events: [source])
        let google = ProbeProvider(.google)
        let factory: CalendarSyncRuntimeChecks.ProviderFactory = { _, _ in (daou, google) }
        let preview = await CalendarSyncRuntimeChecks.execute(mode: .previewSelected, databaseURL: url,
            authorization: granted, providerFactory: factory)
        require(preview.status == "previewReady" && preview.counts?["toGoogle"] == 1,
                "preview must use normal coordinator planning")
        let previewWrites = await google.writes
        require(previewWrites == 0, "preview must never apply an event write")
        let encoded = String(decoding: try JSONEncoder().encode(preview), as: UTF8.self)
        require(!encoded.contains("PRIVATE_"), "report must omit IDs, titles, and account names")
        let wrong = await CalendarSyncRuntimeChecks.execute(mode: .resumeSelected(reviewedReceipt: "wrong"),
            databaseURL: url, authorization: granted, providerFactory: factory)
        let wrongState = try await store.load()
        let wrongWrites = await google.writes
        require(wrong.status == "previewChanged" && !wrongState.configuration.enabled && wrongWrites == 0,
                "unreviewed receipt must not enable or write")
        var changed = source
        changed.version = "v2"
        changed.content.title += " changed"
        await daou.replace(changed)
        let drift = await CalendarSyncRuntimeChecks.execute(mode: .resumeSelected(reviewedReceipt: preview.receipt!),
            databaseURL: url, authorization: granted, providerFactory: factory)
        let driftWrites = await google.writes
        require(drift.status == "previewChanged" && driftWrites == 0, "new event content must invalidate receipt")
        let fresh = await CalendarSyncRuntimeChecks.execute(mode: .previewSelected, databaseURL: url,
            authorization: granted, providerFactory: factory)
        let resumed = await CalendarSyncRuntimeChecks.execute(mode: .resumeSelected(reviewedReceipt: fresh.receipt!),
            databaseURL: url, authorization: granted, providerFactory: factory)
        let resumedState = try await store.load()
        let resumedWrites = await google.writes
        require(resumed.status == "syncCompleted" && resumed.counts?["completed"] == 1 && resumedWrites == 1,
                "matching fresh receipt must apply reviewed sync")
        require(resumedState.configuration.enabled && resumedState.nextRunAt != nil,
                "resume must persist enabled schedule")
        print("PASS calendar runtime guard, preview, sanitized receipt, drift rejection, and reviewed resume")
    }
}
