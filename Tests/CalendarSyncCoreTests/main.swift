import Foundation
import CalendarSyncCore

private enum CheckError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        if case let .failed(message) = self { return message }
        return "unknown failure"
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckError.failed(message) }
}

private func event(_ id: String, _ version: String, _ title: String, exclusion: CalendarEventExclusion? = nil) -> CalendarEvent {
    CalendarEvent(
        id: id,
        version: version,
        content: CalendarEventContent(
            title: title,
            time: .timed(start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600), timeZoneID: "Asia/Seoul")
        ),
        exclusion: exclusion
    )
}

private func mapped(_ baseline: SyncBaseline? = nil) -> CalendarMapping {
    CalendarMapping(id: "pair-1", daouEventID: "d-1", googleEventID: "g-1", baseline: baseline)
}

private func checkOperation(
    _ decision: SyncDecision,
    _ expected: SyncOperation,
    _ expectedBaseline: SyncBaseline
) throws {
    guard case let .operation(actual, newBaseline) = decision else {
        throw CheckError.failed("expected operation, got \(decision)")
    }
    try check(actual == expected, "wrong operation \(actual)")
    try check(newBaseline == expectedBaseline, "wrong post-write baseline")
}

private func run() throws -> Int {
    var count = 0
    let old = event("d-1", "d-etag-1", "original")
    let oldGoogle = event("g-1", "g-etag-1", "original")
    let previous = SyncBaseline.content(old.content)

    let newDaou = event("d-1", "d-etag-2", "daou edit")
    try checkOperation(
        SyncPlanner.plan(mapping: mapped(previous), daou: .present(newDaou), google: .present(oldGoogle)),
        .update(mappingID: "pair-1", target: .google, targetEventID: "g-1", expectedVersion: "g-etag-1", content: newDaou.content),
        .content(newDaou.content)
    ); count += 1

    let newGoogle = event("g-1", "g-etag-2", "google edit")
    try checkOperation(
        SyncPlanner.plan(mapping: mapped(previous), daou: .present(old), google: .present(newGoogle)),
        .update(mappingID: "pair-1", target: .daou, targetEventID: "d-1", expectedVersion: "d-etag-1", content: newGoogle.content),
        .content(newGoogle.content)
    ); count += 1

    let sameGoogle = event("g-1", "g-etag-2", "daou edit")
    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .present(newDaou), google: .present(sameGoogle)) == .settled(.content(newDaou.content)), "same independent edits should settle"); count += 1

    let doubleEdit = SyncPlanner.plan(mapping: mapped(previous), daou: .present(newDaou), google: .present(newGoogle))
    guard case let .conflict(conflict) = doubleEdit else { throw CheckError.failed("different double edits must conflict") }
    try check(conflict.reason == .simultaneousEdits, "wrong simultaneous edit reason"); count += 1

    try checkOperation(
        SyncPlanner.plan(mapping: mapped(previous), daou: .confirmedDeleted, google: .present(oldGoogle)),
        .delete(mappingID: "pair-1", target: .google, targetEventID: "g-1", expectedVersion: "g-etag-1"),
        .deleted
    ); count += 1

    try checkOperation(
        SyncPlanner.plan(mapping: mapped(previous), daou: .present(old), google: .confirmedDeleted),
        .delete(mappingID: "pair-1", target: .daou, targetEventID: "d-1", expectedVersion: "d-etag-1"),
        .deleted
    ); count += 1

    let deletionEdit = SyncPlanner.plan(mapping: mapped(previous), daou: .confirmedDeleted, google: .present(newGoogle))
    guard case let .conflict(conflict) = deletionEdit else { throw CheckError.failed("delete versus edit must conflict") }
    try check(conflict.reason == .editVersusDeletion, "wrong deletion conflict reason"); count += 1

    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .confirmedDeleted, google: .confirmedDeleted) == .settled(.deleted), "both deletions should settle"); count += 1
    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .absent, google: .present(oldGoogle)) == .held(.unverifiedAbsence), "missing listing must not delete"); count += 1
    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .unavailable(.permissionDenied), google: .present(oldGoogle)) == .held(.incompleteObservation), "failed read must not delete"); count += 1

    let newPair = CalendarMapping(id: "new-pair", daouEventID: "d-1", googleEventID: nil, baseline: nil)
    try checkOperation(
        SyncPlanner.plan(mapping: newPair, daou: .present(old), google: .absent),
        .create(mappingID: "new-pair", target: .google, sourceEventID: "d-1", content: old.content),
        previous
    ); count += 1
    let reverseNewPair = CalendarMapping(id: "new-pair", daouEventID: nil, googleEventID: "g-1", baseline: nil)
    try checkOperation(
        SyncPlanner.plan(mapping: reverseNewPair, daou: .absent, google: .present(oldGoogle)),
        .create(mappingID: "new-pair", target: .daou, sourceEventID: "g-1", content: oldGoogle.content),
        previous
    ); count += 1

    try check(SyncPlanner.plan(mapping: mapped(), daou: .absent, google: .absent) == .held(.unverifiedAbsence),
              "an empty initial pair must not write"); count += 1

    let unpairedSameTitle = SyncPlanner.plan(mapping: mapped(), daou: .present(old), google: .present(oldGoogle))
    guard case let .conflict(conflict) = unpairedSameTitle else { throw CheckError.failed("initial matching title should not be auto-paired") }
    try check(conflict.reason == .initialPairAmbiguous, "wrong initial-pair reason"); count += 1

    try check(SyncPlanner.plan(mapping: newPair, daou: .present(old), google: .confirmedDeleted) == .held(.unverifiedAbsence), "initial tombstone must not resurrect"); count += 1
    try check(SyncPlanner.plan(mapping: mapped(.deleted), daou: .present(old), google: .confirmedDeleted) == .held(.tombstoneResurrection), "known tombstone must not resurrect"); count += 1

    let excluded = event("d-1", "v", "meeting", exclusion: .invitation)
    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .present(excluded), google: .present(oldGoogle)) == .held(.excludedEvent(.invitation)), "invitation must not auto-write"); count += 1

    let noVersion = event("g-1", "", "original")
    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .present(newDaou), google: .present(noVersion)) == .held(.missingVersion), "update requires target version"); count += 1

    let swappedID = event("other", "v", "original")
    try check(SyncPlanner.plan(mapping: mapped(previous), daou: .present(swappedID), google: .present(oldGoogle)) == .held(.identityMismatch), "wrong mapped ID must not write"); count += 1

    let incompleteMapping = CalendarMapping(id: "incomplete", daouEventID: "d-1", googleEventID: nil, baseline: previous)
    try check(SyncPlanner.plan(mapping: incompleteMapping, daou: .present(old), google: .confirmedDeleted) == .held(.incompleteMapping), "incomplete mapping must not delete"); count += 1

    let allDay = CalendarEventContent(title: "holiday", time: .allDay(startDate: "2026-09-29", exclusiveEndDate: "2026-09-30"))
    let roundTrip = try JSONDecoder().decode(CalendarMapping.self, from: JSONEncoder().encode(CalendarMapping(id: "all-day", daouEventID: "d", googleEventID: "g", baseline: .content(allDay))))
    try check(roundTrip.baseline == .content(allDay), "all-day baseline must persist exactly"); count += 1

    return count
}

@main
private enum Main {
    static func main() {
        do {
            let count = try run()
            print("CalendarSyncCore: \(count) checks passed")
        } catch {
            fputs("CalendarSyncCore: \(error)\n", stderr)
            exit(1)
        }
    }
}
