import Foundation
import EventKit
import CalendarSyncCore
@testable import CalendarSyncServices

private enum ExpandedServiceError: Error { case failed(String) }
private func expandedServiceCheck(_ condition: Bool, _ message: String) throws {
    if !condition { throw ExpandedServiceError.failed(message) }
}

private func expandedFixtureEvent() -> EKEvent {
    let event = EKEvent(eventStore: EKEventStore())
    event.title = "Personal copy"
    event.startDate = Date(timeIntervalSince1970: 1_800_000_000)
    event.endDate = Date(timeIntervalSince1970: 1_800_003_600)
    event.timeZone = TimeZone(secondsFromGMT: 0)
    event.notes = "Notes"
    event.location = "Room"
    event.url = URL(string: "happylulu://sync/00000000-0000-0000-0000-000000000001")
    return event
}

func testSystemExpandedAlarmSupport() throws {
    let event = expandedFixtureEvent()
    event.addAlarm(EKAlarm(relativeOffset: -900))
    event.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: 1_799_999_000)))
    let decoded = try SystemCalendarSafety.decodeEvent(event, localID: "local-fixture")
    try expandedServiceCheck(decoded.exclusion == nil, "display alarm-bearing events must be eligible for personal copy: \(String(describing: decoded.exclusion)); types=\((event.alarms ?? []).map { $0.type.rawValue })")
    let alarms = decoded.content.alarms ?? []
    try expandedServiceCheck(alarms.count == 2 && alarms.contains(.relative(-900)) && alarms.contains(.absolute(Date(timeIntervalSince1970: 1_799_999_000))),
                             "relative and absolute EventKit alarms must survive decoding")
    let copied = expandedFixtureEvent()
    copied.alarms = try SystemCalendarSafety.eventKitAlarms(decoded.content.alarms)
    let roundTrip = try SystemCalendarSafety.decodeEvent(copied, localID: "personal-copy")
    try expandedServiceCheck(roundTrip.content == decoded.content && !copied.hasRecurrenceRules && !copied.hasAttendees,
                             "ordinary personal copies preserve supported alarm semantics without recurrence or participants")
    copied.alarms = try SystemCalendarSafety.eventKitAlarms(Array(alarms.reversed()) + [alarms[0]])
    try expandedServiceCheck(try SystemCalendarSafety.decodeEvent(copied, localID: "personal-copy").content == decoded.content,
                             "alarm ordering and duplicate triggers normalize without perpetual updates")
    copied.alarms = [EKAlarm(relativeOffset: -300)]
    try expandedServiceCheck(try SystemCalendarSafety.decodeEvent(copied, localID: "personal-copy").version != roundTrip.version,
                             "alarm-only edits change the conditional-write version")
    let email = EKAlarm(relativeOffset: -300)
    email.emailAddress = "fixture@example.invalid"
    let audio = EKAlarm(relativeOffset: -300)
    audio.soundName = "Fixture"
    let location = EKAlarm(relativeOffset: -300)
    location.structuredLocation = EKStructuredLocation(title: "Fixture location")
    for (alarm, reason) in [(email, "alarmEmail"), (audio, "alarmAudio"), (location, "alarmLocation")] {
        copied.alarms = [alarm]
        let held = try SystemCalendarSafety.decodeEvent(copied, localID: "personal-copy")
        try expandedServiceCheck(held.exclusion == .other(reason), "unsupported alarm form must have a specific hold reason")
    }
    for write in [
        { try ICalendarCodec.create(decoded.content, mappingID: "fixture") },
        { try GoogleEventCodec.writeJSON(decoded.content, mappingID: nil) }
    ] {
        do {
            _ = try write()
            throw ExpandedServiceError.failed("legacy REST adapters must not silently discard supported EventKit alarms")
        } catch CalendarCodecError.unsupportedEvent {}
    }
}

func testSystemExpandedInvitationProtection() async throws {
    let event = expandedFixtureEvent()
    var snapshot = try SystemCalendarEventSnapshot(event: event, localID: "local-fixture")
    snapshot.hasAttendees = true
    let decoded = try SystemCalendarSafety.decodeSnapshot(snapshot)
    try expandedServiceCheck(decoded.exclusion == nil && decoded.protectedSource == true,
                             "invitations may be copied but remain protected origins")
    let backend = FakeSystemCalendarBackend()
    backend.insert(decoded)
    let provider = SystemCalendarProvider(side: .daou, backend: backend)
    var changed = decoded.content
    changed.title = "Unsafe reverse edit"
    for operation in [SyncOperation.update(mappingID: "pair", target: .daou, targetEventID: decoded.id,
        expectedVersion: decoded.version, content: changed), .delete(mappingID: "pair", target: .daou,
        targetEventID: decoded.id, expectedVersion: decoded.version)] {
        do {
            _ = try await provider.apply(operation)
            throw ExpandedServiceError.failed("provider must reject a protected invitation target")
        } catch CalendarCodecError.unsupportedEvent {}
    }
    try expandedServiceCheck(try backend.event(id: decoded.id) == decoded, "rejected target writes preserve invitation contents")
}

func testSystemExpandedRecurrenceSupport() throws {
    let event = expandedFixtureEvent()
    event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
    var first = try SystemCalendarEventSnapshot(event: event, localID: "shared-local-id")
    first.url = nil
    first.externalID = "server-series:UID/with-delimiters"
    first.occurrenceDate = first.startDate
    var second = first
    second.occurrenceDate = first.startDate.addingTimeInterval(86_400)
    second.startDate = second.occurrenceDate!
    second.endDate = second.startDate.addingTimeInterval(3600)
    let firstDecoded = try SystemCalendarSafety.decodeSnapshot(first)
    let secondDecoded = try SystemCalendarSafety.decodeSnapshot(second)
    try expandedServiceCheck(firstDecoded.exclusion == nil && secondDecoded.exclusion == nil && firstDecoded.id != secondDecoded.id,
                             "recurring occurrences with one UID must have distinct eligible identities")
    second.isDetached = true
    second.localID = "changed-local-id"
    second.startDate = second.startDate.addingTimeInterval(7200)
    second.endDate = second.endDate.addingTimeInterval(7200)
    let moved = try SystemCalendarSafety.decodeSnapshot(second)
    try expandedServiceCheck(moved.id == secondDecoded.id && moved.content.time != secondDecoded.content.time,
                             "moved exception retains original occurrence identity while copying its actual time")
    let firstIdentity = SystemCalendarSafety.OccurrenceIdentity(externalID: first.externalID!, originalDate: first.occurrenceDate!)
    let secondIdentity = SystemCalendarSafety.OccurrenceIdentity(externalID: second.externalID!, originalDate: second.occurrenceDate!)
    try expandedServiceCheck(try SystemCalendarSafety.matchingOccurrenceIndex(id: moved.id, identities: [firstIdentity, nil, secondIdentity]) == 2,
                             "finder targets the original date of the moved occurrence rather than the first series member")
    try expandedServiceCheck(try SystemCalendarSafety.matchingOccurrenceIndex(id: moved.id, identities: [firstIdentity]) == nil,
                             "occurrence missing from the live window remains unavailable")
    do {
        _ = try SystemCalendarSafety.matchingOccurrenceIndex(id: moved.id, identities: [secondIdentity, secondIdentity])
        throw ExpandedServiceError.failed("duplicate UID and original occurrence date must be ambiguous")
    } catch SystemCalendarError.uncertainWrite {}
    first.occurrenceDate = nil
    try expandedServiceCheck(try SystemCalendarSafety.decodeSnapshot(first).exclusion == .other("missingOccurrenceDate"),
                             "series without original occurrence metadata cannot be copied with a guessed identity")
    let zone = TimeZone(identifier: "Asia/Seoul")!
    let utc = TimeZone(secondsFromGMT: 0)!
    let parser = ISO8601DateFormatter()
    let koreanDay = parser.date(from: "2026-10-20T00:00:00+09:00")!
    let utcDay = parser.date(from: "2026-10-20T00:00:00Z")!
    let dayID = try SystemCalendarSafety.occurrenceID(externalID: "floating-day", originalDate: koreanDay,
        isAllDay: true, timeZone: zone)
    try expandedServiceCheck(dayID == (try SystemCalendarSafety.occurrenceID(externalID: "floating-day",
        originalDate: utcDay, isAllDay: true, timeZone: utc)),
        "all-day occurrence identity follows civil date across system timezone changes")
    let dayIdentity = SystemCalendarSafety.OccurrenceIdentity(externalID: "floating-day", originalDate: utcDay,
        isAllDay: true, timeZone: utc)
    try expandedServiceCheck(try SystemCalendarSafety.matchingOccurrenceIndex(id: dayID, identities: [dayIdentity]) == 0,
        "all-day finder matches the same civil occurrence after a timezone change")
    let koreanFloating = koreanDay.addingTimeInterval(9.5 * 3600)
    let utcFloating = utcDay.addingTimeInterval(9.5 * 3600)
    let floatingID = try SystemCalendarSafety.occurrenceID(externalID: "floating-time", originalDate: koreanFloating,
        isFloating: true, timeZone: zone)
    try expandedServiceCheck(floatingID == (try SystemCalendarSafety.occurrenceID(externalID: "floating-time",
        originalDate: utcFloating, isFloating: true, timeZone: utc)),
        "floating timed recurrence identity follows civil time across system timezone changes")
    let floatingIdentity = SystemCalendarSafety.OccurrenceIdentity(externalID: "floating-time", originalDate: utcFloating,
        isFloating: true, timeZone: utc)
    try expandedServiceCheck(try SystemCalendarSafety.matchingOccurrenceIndex(id: floatingID, identities: [floatingIdentity]) == 0,
        "floating timed finder retains the original civil occurrence")
}

func testSystemExpandedRecurrenceCopies() async throws {
    try await withStore { store in
        let event = expandedFixtureEvent()
        event.startDate = Date().addingTimeInterval(3600)
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        event.alarms = [EKAlarm(relativeOffset: -900)]
        var first = try SystemCalendarEventSnapshot(event: event, localID: "series-local")
        first.url = nil
        first.externalID = "recurrence-server-uid"
        first.occurrenceDate = first.startDate
        var second = first
        second.occurrenceDate = first.startDate.addingTimeInterval(86_400)
        second.startDate = second.occurrenceDate!.addingTimeInterval(7200)
        second.endDate = second.startDate.addingTimeInterval(3600)
        second.isDetached = true
        let originalFirst = try SystemCalendarSafety.decodeSnapshot(first)
        var originalSecond = try SystemCalendarSafety.decodeSnapshot(second)
        let source = FakeSystemCalendarBackend()
        let destination = FakeSystemCalendarBackend()
        source.insert(originalFirst)
        source.insert(originalSecond)
        var state = CalendarSyncState()
        state.configuration.daouBaseURL = "eventkit"
        state.configuration.daouCalendarURL = "fixture-daou"
        state.configuration.googleCalendarID = "fixture-google"
        state.configuration.systemAccountsConfirmed = true
        try await store.save(state)
        let coordinator = SyncCoordinator(store: store,
            daou: SystemCalendarProvider(side: .daou, backend: source),
            google: SystemCalendarProvider(side: .google, backend: destination))
        let preview = try await coordinator.run(allowWrites: false)
        try expandedServiceCheck(preview.toGoogle == 2 && destination.writes() == 0,
                                 "preview contains each normal or moved recurrence without writes")
        state = try await store.load()
        state.configuration.previewAccepted = true
        state.configuration.enabled = true
        try await store.save(state)
        let written = try await coordinator.run(allowWrites: true)
        try expandedServiceCheck(written.completed == 2 && destination.writes() == 2,
                                 "each recurrence creates exactly one personal copy")
        state = try await store.load()
        try expandedServiceCheck(state.mappings.count == 2 && state.pendingOperations.isEmpty,
                                 "occurrence-specific mappings retain independent journals")
        for mapping in state.mappings.values {
            guard let id = mapping.googleEventID, let copy = try destination.event(id: id) else {
                throw ExpandedServiceError.failed("each occurrence must have a persisted destination copy")
            }
            try expandedServiceCheck(id.hasPrefix("sync:") && copy.protectedSource != true &&
                                     copy.content.alarms == [.relative(-900)],
                                     "copies are ordinary personal items with preserved display alarms")
        }
        let repeated = try await coordinator.run(allowWrites: true)
        try expandedServiceCheck(repeated.completed == 0 && destination.writes() == 2,
                                 "a repeated cycle does not duplicate any occurrence")
        originalSecond.content.notes = "Changed exception"
        originalSecond.version = "exception-v2"
        source.insert(originalSecond)
        let updated = try await coordinator.run(allowWrites: true)
        try expandedServiceCheck(updated.completed == 1,
                                 "editing a moved exception updates only its own copy")
        source.insertPhysicalDuplicate(originalSecond)
        let ambiguousPreview = try await coordinator.run(allowWrites: false)
        try expandedServiceCheck(ambiguousPreview.held == 1 && ambiguousPreview.excluded == 1,
                                 "duplicate server UID and original date hold the ambiguous occurrence")
        let ambiguousState = try await store.load()
        try expandedServiceCheck(ambiguousState.daouObserved[originalSecond.id]?.exclusion == .other("ambiguousOccurrence"),
                                 "ambiguous occurrences expose a specific review reason")
    }
}

/// Models EventKit's refusal to identify a specific occurrence through a
/// previously mapped, UID-only external ID after that copy becomes a series.
private final class ConvertedSeriesBackend: SystemCalendarBackend, @unchecked Sendable {
    let storage = FakeSystemCalendarBackend()
    let legacyID: String
    private let lock = NSLock()
    private var seriesWrites = 0

    init(legacyID: String) { self.legacyID = legacyID }
    func validateCalendar() throws { try storage.validateCalendar() }
    func events(start: Date, end: Date) throws -> [SystemCalendarRecord] { try storage.events(start: start, end: end) }
    func event(id: String) throws -> CalendarEvent? {
        if id == legacyID { throw SystemCalendarError.uncertainWrite }
        return try storage.event(id: id)
    }
    func create(content: CalendarEventContent, marker: String) throws -> CalendarEvent {
        try storage.create(content: content, marker: marker)
    }
    func update(id: String, expectedVersion: String, content: CalendarEventContent) throws -> CalendarEvent {
        if id == legacyID { lock.withLock { seriesWrites += 1 } }
        return try storage.update(id: id, expectedVersion: expectedVersion, content: content)
    }
    func delete(id: String, expectedVersion: String) throws {
        if id == legacyID { lock.withLock { seriesWrites += 1 } }
        try storage.delete(id: id, expectedVersion: expectedVersion)
    }
    func unsafeWrites() -> Int { lock.withLock { seriesWrites } }
}

func testSystemConvertedLegacySeriesIsolation() async throws {
    try await withStore { store in
        let source = FakeSystemCalendarBackend()
        let destination = ConvertedSeriesBackend(legacyID: "external:converted-copy")
        let mappingID = UUID().uuidString
        let original = sample("external:ordinary-source", title: "Originally ordinary")
        source.insert(original)
        source.insert(sample("external:unrelated-source", title: "Unrelated eligible event"))
        let converted = expandedFixtureEvent()
        converted.startDate = Date().addingTimeInterval(3600)
        converted.endDate = converted.startDate.addingTimeInterval(3600)
        converted.url = try SystemCalendarSafety.markerURL(mappingID)
        converted.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
        var snapshot = try SystemCalendarEventSnapshot(event: converted, localID: "local-converted-copy")
        snapshot.externalID = "converted-copy"
        snapshot.occurrenceDate = snapshot.startDate
        let recurrence = try SystemCalendarSafety.decodeSnapshot(snapshot)
        try expandedServiceCheck(recurrence.exclusion == .other("managedRecurringSeries"),
                                 "a managed ordinary copy converted to recurrence remains excluded from new imports")
        destination.storage.insert(recurrence)
        var state = CalendarSyncState()
        state.configuration.daouBaseURL = "eventkit"
        state.configuration.daouCalendarURL = "fixture-daou"
        state.configuration.googleCalendarID = "fixture-google"
        state.configuration.systemAccountsConfirmed = true
        state.configuration.previewAccepted = true
        state.configuration.enabled = true
        state.lastSuccessAt = Date()
        state.mappings[mappingID] = CalendarMapping(id: mappingID, daouEventID: original.id,
            googleEventID: destination.legacyID, baseline: .content(original.content))
        try await store.save(state)
        let provider = SystemCalendarProvider(side: .google, backend: destination)
        try expandedServiceCheck(try await provider.observe(eventID: destination.legacyID) == .unavailable(.unknown),
                                 "ambiguous legacy UID is an unavailable read observation")
        let coordinator = SyncCoordinator(store: store,
            daou: SystemCalendarProvider(side: .daou, backend: source), google: provider)
        let result = try await coordinator.run(allowWrites: true)
        try expandedServiceCheck(result.completed == 1 && result.held == 1 && destination.storage.writes() == 1,
                                 "converted legacy series is held while an unrelated event completes")
        for operation in [SyncOperation.update(mappingID: mappingID, target: .google,
            targetEventID: destination.legacyID, expectedVersion: "old-version", content: original.content),
            .delete(mappingID: mappingID, target: .google, targetEventID: destination.legacyID, expectedVersion: "old-version")] {
            do {
                _ = try await provider.apply(operation)
                throw ExpandedServiceError.failed("ambiguous legacy UID must still reject direct writes")
            } catch SystemCalendarError.uncertainWrite {}
            do {
                _ = try await provider.recover(operation)
                throw ExpandedServiceError.failed("ambiguous legacy UID must still reject recovery writes")
            } catch SystemCalendarError.uncertainWrite {}
        }
        try expandedServiceCheck(destination.unsafeWrites() == 0,
                                 "no direct, planned, delete, or recovery write reaches the series")
    }
}
