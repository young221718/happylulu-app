import CryptoKit
import Foundation
import CalendarSyncCore

/// The bridge owns EventKit objects; the provider works with immutable values.
/// All bridge calls are serialized by its owning provider actor.
struct SystemCalendarRecord: Sendable {
    let physicalID: String
    let event: CalendarEvent
}

protocol SystemCalendarBackend: Sendable {
    func validateCalendar() throws
    func events(start: Date, end: Date) throws -> [SystemCalendarRecord]
    func event(id: String) throws -> CalendarEvent?
    func create(content: CalendarEventContent, marker: String) throws -> CalendarEvent
    func update(id: String, expectedVersion: String, content: CalendarEventContent) throws -> CalendarEvent
    func delete(id: String, expectedVersion: String) throws
}

enum SystemCalendarSafety {
    static func eventID(marker: String?, externalID: String?, localID: String) -> String {
        // A server UID also works outside the listing window and if a server
        // removes a copy's URL. sync: is a provisional ID until the UID arrives.
        externalID.map { "external:" + $0 } ?? marker.map { "sync:" + $0 } ?? localID
    }

    static func markerURL(_ mappingID: String) throws -> URL {
        guard let uuid = UUID(uuidString: mappingID),
              let url = URL(string: "happylulu://sync/\(uuid.uuidString)") else {
            throw SystemCalendarError.uncertainWrite
        }
        return url
    }

    static func marker(from url: URL?) -> String? {
        guard let url, url.scheme == "happylulu", url.host == "sync",
              url.query == nil, url.fragment == nil,
              let uuid = UUID(uuidString: String(url.path.dropFirst())) else { return nil }
        return uuid.uuidString
    }

    static func version(content: CalendarEventContent, modified: Date?) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(content)
        let payload = Data("\(modified?.timeIntervalSince1970 ?? 0)|".utf8) + encoded
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    static func normalized(_ content: CalendarEventContent) -> CalendarEventContent {
        var content = content
        if content.notes == "" { content.notes = nil }
        if content.location == "" { content.location = nil }
        return content
    }

    static func allDayTime(start: Date, end: Date, timeZone: TimeZone = .current) throws -> CalendarEventTime {
        guard start < end else { throw SystemCalendarError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        // macOS can return the last second of the final day; other backends
        // return midnight of the following day. Preserve both representations.
        let exclusiveEnd: Date
        if end == lastDay {
            exclusiveEnd = lastDay
        } else {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
                throw SystemCalendarError.invalidDate
            }
            exclusiveEnd = nextDay
        }
        guard firstDay < exclusiveEnd else { throw SystemCalendarError.invalidDate }
        let formatter = dayFormatter(timeZone: timeZone)
        return .allDay(startDate: formatter.string(from: firstDay),
                       exclusiveEndDate: formatter.string(from: exclusiveEnd))
    }

    static func eventKitDates(for time: CalendarEventTime) throws -> (Date, Date) {
        let (start, end) = try dates(for: time)
        // Write the last second of the final day on macOS, so an exclusive
        // midnight does not turn into an additional all-day calendar day.
        if case .allDay = time { return (start, end.addingTimeInterval(-1)) }
        return (start, end)
    }

    private static func dayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    static func dates(for time: CalendarEventTime) throws -> (Date, Date) {
        switch time {
        case let .timed(start, end, _):
            guard start < end else { throw SystemCalendarError.invalidDate }
            return (start, end)
        case let .allDay(start, end):
            let formatter = dayFormatter(timeZone: .current)
            guard let startDate = formatter.date(from: start),
                  let endDate = formatter.date(from: end), startDate < endDate,
                  formatter.string(from: startDate) == start,
                  formatter.string(from: endDate) == end else { throw SystemCalendarError.invalidDate }
            return (startDate, endDate)
        }
    }
}
