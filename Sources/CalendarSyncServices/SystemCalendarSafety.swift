@preconcurrency import EventKit
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

/// Value boundary for EventKit's read-only metadata and supported content.
/// The decoder never needs to retain or mutate an EventKit object.
struct SystemCalendarEventSnapshot {
    var localID: String
    var externalID: String?
    var occurrenceDate: Date?
    var hasRecurrenceRules: Bool
    var isDetached: Bool
    var hasAttendees: Bool
    var url: URL?
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var timeZoneID: String
    var isFloating: Bool
    var defaultTimeZone: TimeZone
    var notes: String?
    var location: String?
    var lastModifiedDate: Date?
    var alarms: [CalendarEventAlarm]?
    var alarmExclusion: CalendarEventExclusion?

    init(event: EKEvent, localID: String) throws {
        guard let start = event.startDate, let end = event.endDate else { throw SystemCalendarError.invalidDate }
        self.localID = localID
        externalID = event.calendarItemExternalIdentifier
        occurrenceDate = event.occurrenceDate
        hasRecurrenceRules = event.hasRecurrenceRules
        isDetached = event.isDetached
        hasAttendees = event.hasAttendees
        url = event.url
        title = event.title ?? ""
        startDate = start
        endDate = end
        isAllDay = event.isAllDay
        timeZoneID = event.timeZone?.identifier ?? TimeZone.current.identifier
        isFloating = !event.isAllDay && event.timeZone == nil
        defaultTimeZone = .current
        notes = event.notes
        location = event.location
        lastModifiedDate = event.lastModifiedDate
        let alarmContent = SystemCalendarSafety.alarmContent(event.alarms)
        alarms = alarmContent.values
        alarmExclusion = alarmContent.exclusion
    }
}

enum SystemCalendarSafety {
    static func decodeEvent(_ event: EKEvent, localID eventID: String) throws -> CalendarEvent {
        try decodeSnapshot(SystemCalendarEventSnapshot(event: event, localID: eventID))
    }

    static func decodeSnapshot(_ event: SystemCalendarEventSnapshot) throws -> CalendarEvent {
        let originalMarker = SystemCalendarSafety.marker(from: event.url)
        // Newly constructed ordinary EventKit events can expose occurrenceDate
        // once startDate is set. Recurrence flags, not that date alone, decide
        // whether the server UID needs an occurrence suffix.
        let isOccurrence = event.hasRecurrenceRules || event.isDetached
        // A managed ordinary copy converted into a series has one shared
        // marker. Never reinterpret it as multiple independent mapped copies.
        let marker = isOccurrence ? nil : originalMarker
        let externalID = event.externalID
        // Prefer the server UID. EventKit's local ID can change after a full sync.
        var id = SystemCalendarSafety.eventID(marker: marker, externalID: externalID, localID: event.localID)
        var exclusion: CalendarEventExclusion?
        if isOccurrence {
            if let externalID, !externalID.isEmpty, let occurrenceDate = event.occurrenceDate {
                id = try occurrenceID(externalID: externalID, originalDate: occurrenceDate,
                    isAllDay: event.isAllDay, isFloating: event.isFloating, timeZone: event.defaultTimeZone)
            } else {
                exclusion = .other("missingOccurrenceDate")
            }
            if originalMarker != nil { exclusion = .other("managedRecurringSeries") }
        }
        if let alarmExclusion = event.alarmExclusion { exclusion = alarmExclusion }
        if event.url != nil && originalMarker == nil { exclusion = .other("existingURL") }
        if marker == nil && (externalID == nil || externalID?.isEmpty == true) { exclusion = .other("missingServerID") }
        let title = event.title
        if title.contains("/") { exclusion = .other("slashTitle") }
        let time: CalendarEventTime
        if event.isAllDay {
            do {
                // EventKit returns floating all-day dates in the default zone.
                time = try SystemCalendarSafety.allDayTime(start: event.startDate, end: event.endDate, timeZone: event.defaultTimeZone)
            } catch SystemCalendarError.invalidDate {
                time = .allDay(startDate: dayString(event.startDate, timeZone: event.defaultTimeZone),
                               exclusiveEndDate: dayString(event.endDate, timeZone: event.defaultTimeZone))
                exclusion = .other("invalidDate")
            }
        } else {
            time = .timed(start: event.startDate, end: event.endDate,
                         timeZoneID: event.timeZoneID)
            if event.startDate >= event.endDate { exclusion = .other("invalidDate") }
        }
        let content = SystemCalendarSafety.normalized(CalendarEventContent(title: title, time: time,
            notes: event.notes, location: event.location, alarms: event.alarms))
        return CalendarEvent(id: id,
            version: try SystemCalendarSafety.version(content: content, modified: event.lastModifiedDate),
            content: content, exclusion: exclusion, syncMarker: marker,
            protectedSource: event.hasAttendees ? true : nil)
    }

    struct OccurrenceIdentity: Equatable {
        let externalID: String
        let originalDate: Date
        var isAllDay = false
        var isFloating = false
        var timeZone = TimeZone.current
    }

    static func occurrenceID(externalID: String, originalDate: Date, isAllDay: Bool = false,
                             isFloating: Bool = false, timeZone: TimeZone = .current) throws -> String {
        let milliseconds = originalDate.timeIntervalSince1970 * 1000
        guard !externalID.isEmpty, milliseconds.isFinite,
              milliseconds >= Double(Int64.min), milliseconds < Double(Int64.max) else {
            throw SystemCalendarError.invalidDate
        }
        let encoded = Data(externalID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        if isAllDay {
            return "occurrence:\(encoded):day:\(dayString(originalDate, timeZone: timeZone))"
        }
        if isFloating {
            let formatter = civilFormatter(timeZone: timeZone)
            return "occurrence:\(encoded):floating:\(formatter.string(from: originalDate))"
        }
        return "occurrence:\(encoded):\(Int64(milliseconds.rounded()))"
    }

    static func occurrenceIdentity(_ id: String) -> OccurrenceIdentity? {
        let components = id.split(separator: ":", omittingEmptySubsequences: false)
        guard (components.count == 3 || components.count == 4), components[0] == "occurrence" else { return nil }
        var encoded = String(components[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), let externalID = String(data: data, encoding: .utf8), !externalID.isEmpty else { return nil }
        if components.count == 3, let milliseconds = Int64(components[2]) {
            return OccurrenceIdentity(externalID: externalID, originalDate: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
        }
        guard components.count == 4 else { return nil }
        let formatter: DateFormatter
        if components[2] == "day" { formatter = dayFormatter(timeZone: .current) }
        else if components[2] == "floating" { formatter = civilFormatter(timeZone: .current) }
        else { return nil }
        let token = String(components[3])
        guard let date = formatter.date(from: token), formatter.string(from: date) == token else { return nil }
        return OccurrenceIdentity(externalID: externalID, originalDate: date,
            isAllDay: components[2] == "day", isFloating: components[2] == "floating")
    }

    static func matchingOccurrence(id: String, events: [EKEvent]) throws -> EKEvent? {
        let identities = events.map { event -> OccurrenceIdentity? in
            guard event.hasRecurrenceRules || event.isDetached else { return nil }
            guard let externalID = event.calendarItemExternalIdentifier, let originalDate = event.occurrenceDate else { return nil }
            return OccurrenceIdentity(externalID: externalID, originalDate: originalDate,
                isAllDay: event.isAllDay, isFloating: !event.isAllDay && event.timeZone == nil)
        }
        return try matchingOccurrenceIndex(id: id, identities: identities).map { events[$0] }
    }

    static func matchingOccurrenceIndex(id: String, identities: [OccurrenceIdentity?]) throws -> Int? {
        guard let identity = occurrenceIdentity(id) else { throw SystemCalendarError.uncertainWrite }
        let matches = try identities.indices.filter { index in
            guard let candidate = identities[index], candidate.externalID == identity.externalID,
                  candidate.isAllDay == identity.isAllDay, candidate.isFloating == identity.isFloating else { return false }
            return try occurrenceID(externalID: candidate.externalID, originalDate: candidate.originalDate,
                isAllDay: candidate.isAllDay, isFloating: candidate.isFloating, timeZone: candidate.timeZone) == id
        }
        guard matches.count <= 1 else { throw SystemCalendarError.uncertainWrite }
        return matches.first
    }

    static func alarmContent(_ alarms: [EKAlarm]?) -> (values: [CalendarEventAlarm]?, exclusion: CalendarEventExclusion?) {
        var values: [CalendarEventAlarm] = []
        for alarm in alarms ?? [] {
            let reason: String?
            if alarm.structuredLocation != nil || alarm.proximity != .none { reason = "alarmLocation" }
            else if alarm.type == .email || alarm.emailAddress != nil { reason = "alarmEmail" }
            else if alarm.type == .audio || alarm.soundName != nil { reason = "alarmAudio" }
            else if alarm.type != .display { reason = "alarmProcedure" }
            else { reason = nil }
            if let reason { return (nil, .other(reason)) }
            if let absoluteDate = alarm.absoluteDate {
                guard absoluteDate.timeIntervalSince1970.isFinite else { return (nil, .other("alarmInvalidTrigger")) }
                values.append(.absolute(absoluteDate))
            } else {
                guard alarm.relativeOffset.isFinite else { return (nil, .other("alarmInvalidTrigger")) }
                values.append(.relative(alarm.relativeOffset))
            }
        }
        return (values.isEmpty ? nil : values, nil)
    }

    static func eventKitAlarms(_ alarms: [CalendarEventAlarm]?) throws -> [EKAlarm]? {
        let values = try (alarms ?? []).map { alarm in
            switch alarm {
            case .relative(let offset):
                guard offset.isFinite else { throw CalendarCodecError.unsupportedEvent }
                return EKAlarm(relativeOffset: offset)
            case .absolute(let date):
                guard date.timeIntervalSince1970.isFinite else { throw CalendarCodecError.unsupportedEvent }
                return EKAlarm(absoluteDate: date)
            }
        }
        return values.isEmpty ? nil : values
    }


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
        if let alarms = content.alarms {
            let sorted = alarms.sorted { left, right in
                switch (left, right) {
                case let (.relative(a), .relative(b)): return a < b
                case let (.absolute(a), .absolute(b)): return a < b
                case (.relative, .absolute): return true
                case (.absolute, .relative): return false
                }
            }
            var unique: [CalendarEventAlarm] = []
            for alarm in sorted where unique.last != alarm { unique.append(alarm) }
            content.alarms = unique.isEmpty ? nil : unique
        }
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

    private static func civilFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = dayFormatter(timeZone: timeZone)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS"
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
    private static func dayString(_ date: Date, timeZone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
