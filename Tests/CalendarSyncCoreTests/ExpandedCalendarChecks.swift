import Foundation
import CalendarSyncCore

private enum ExpandedCoreError: Error { case failed(String) }
private func expandedCheck(_ condition: Bool, _ message: String) throws {
    if !condition { throw ExpandedCoreError.failed(message) }
}

func testExpandedCalendarCore() throws -> Int {
    let content = CalendarEventContent(title: "Meeting", time: .timed(
        start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_003_600), timeZoneID: "UTC"),
        notes: "Notes", location: "Room", alarms: [.relative(-900), .absolute(Date(timeIntervalSince1970: 1_799_999_000))])
    var invitation = CalendarEvent(id: "invitation", version: "source-v1", content: content, protectedSource: true)
    var copy = CalendarEvent(id: "copy", version: "copy-v1", content: content)
    let mapping = CalendarMapping(id: "pair", daouEventID: invitation.id, googleEventID: copy.id, baseline: .content(content))
    copy.content.title = "Copy edit"
    try expandedCheck(SyncPlanner.plan(mapping: mapping, daou: .present(invitation), google: .present(copy)) ==
                      .held(.excludedEvent(.invitation)), "editing a personal copy must never edit its invitation origin")
    try expandedCheck(SyncPlanner.plan(mapping: mapping, daou: .present(invitation), google: .confirmedDeleted) ==
                      .held(.excludedEvent(.invitation)), "deleting a personal copy must never delete its invitation origin")
    var durableMapping = mapping
    durableMapping.protectedSources = [.daou]
    invitation.protectedSource = nil
    try expandedCheck(SyncPlanner.plan(mapping: durableMapping, daou: .present(invitation), google: .present(copy)) ==
                      .held(.excludedEvent(.invitation)), "persisted protection survives missing attendee metadata")
    invitation.protectedSource = true
    copy.content = content
    invitation.content.notes = "Organizer update"
    guard case let .operation(operation, _) = SyncPlanner.plan(mapping: mapping, daou: .present(invitation), google: .present(copy)) else {
        throw ExpandedCoreError.failed("organizer updates must still flow to personal copies")
    }
    guard case let .update(_, target, _, _, _) = operation else {
        throw ExpandedCoreError.failed("organizer update must update the ordinary copy")
    }
    try expandedCheck(target == .google, "organizer update targets the ordinary copy")
    let initial = CalendarMapping(id: "new", daouEventID: invitation.id, googleEventID: nil, baseline: nil)
    guard case let .operation(.create(_, target, _, copiedContent), _) = SyncPlanner.plan(
        mapping: initial, daou: .present(invitation), google: .absent) else {
        throw ExpandedCoreError.failed("an invitation can create an ordinary personal copy")
    }
    try expandedCheck(target == .google && copiedContent.alarms == content.alarms,
                      "initial invitation copies preserve supported alarms")
    var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(invitation)) as! [String: Any]
    legacyObject.removeValue(forKey: "protectedSource")
    var legacyContent = legacyObject["content"] as! [String: Any]
    legacyContent.removeValue(forKey: "alarms")
    legacyObject["content"] = legacyContent
    let legacy = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: legacyObject))
    try expandedCheck(legacy.protectedSource == nil && legacy.content.alarms == nil,
                      "older stored observations remain readable")
    let roundTrip = try JSONDecoder().decode(CalendarEventContent.self, from: JSONEncoder().encode(content))
    try expandedCheck(roundTrip == content, "relative and absolute alarm tags persist exactly")
    return 8
}
